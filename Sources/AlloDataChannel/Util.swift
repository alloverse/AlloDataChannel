//
//  Util.swift
//  AlloDataChannel
//
//  Created by Nevyn Bengtsson on 2025-07-17.
//

import Foundation
@preconcurrency import OpenCombineShim

/// Passes an arbitrary number of Swift `String`s to a C callback that
/// expects the same number of `const char *` parameters.
// TODO: figure out how to do this with type parameter packs instead
@inlinable
func withCStrings<R>(
    _ strings: [String],
    _ body: ([UnsafePointer<CChar>]) throws -> R
) rethrows -> R
{
    let utf8Buffers = strings.map { $0.utf8CString }

    func recurse(_ index: Int,
                 _ accumulated: [UnsafePointer<CChar>]) throws -> R
    {
        if index == utf8Buffers.count
        {
            return try body(accumulated)
        }

        return try utf8Buffers[index].withUnsafeBufferPointer { buf in
            var next = accumulated
            next.append(buf.baseAddress!)
            return try recurse(index + 1, next)
        }
    }

    return try recurse(0, [])
}

/// `withCStrings` for a value that may be absent, where the C API wants NULL.
@inlinable
func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R
{
    guard let string else { return try body(nil) }
    return try string.utf8CString.withUnsafeBufferPointer { try body($0.baseAddress!) }
}

extension Published.Publisher
{
    @inlinable
    public func debug(
        _ prefix: String = "",
        to output: @escaping (String) -> Void = { Swift.print($0) }
    ) -> Publishers.HandleEvents<Self>
    {
        handleEvents(receiveOutput: { value in
            output("\(prefix) = \(value)")
        })
    }

    @inlinable
    public func debugSink(
        _ prefix: String = "",
        in bag: inout Set<AnyCancellable>,
        to output: @escaping (String) -> Void = { Swift.print($0) }
    )
    {
        self.debug(prefix, to: output)
            .sink { _ in }
            .store(in: &bag)
    }
}

enum PublisherError: Error {
    case timedOut
}

/// One-shot latch: `signal()` may happen before, during or after `wait()`.
private final class Latch: @unchecked Sendable
{
    private let lock = NSLock()
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal()
    {
        lock.lock()
        guard !signalled else { return lock.unlock() }
        signalled = true
        let waiting = waiters
        waiters = []
        lock.unlock()
        // Off-thread: `signal()` is called from inside a Combine sink on libdatachannel's
        // network thread. Resuming inline runs the awaiting task there, and its teardown
        // re-enters the subscription that is delivering to us — a deadlock.
        for waiter in waiting { Task.detached { waiter.resume() } }
    }

    func wait() async
    {
        // Cancellation must release the waiter: a task group awaits every child before it
        // returns, so one continuation that ignores cancellation hangs the whole group -
        // turning every timeout into a deadlock instead of an error.
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if signalled { lock.unlock(); continuation.resume() }
                else { waiters.append(continuation); lock.unlock() }
            }
        } onCancel: {
            signal()
        }
    }
}

/// Poll `condition` until it holds. Reading the property is always truthful, where
/// subscribing to it races libdatachannel publishing from its own threads.
public func waitUntil(timeout: TimeInterval = 10, interval: TimeInterval = 0.002, _ condition: @escaping () -> Bool) async throws
{
    let deadline = Date().addingTimeInterval(timeout)
    while !condition()
    {
        guard Date() < deadline else { throw PublisherError.timedOut }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

extension Publisher
where Output: Equatable & Sendable
{
    /// Wait until this publisher emits a value satisfying `predicate`.
    ///
    /// Subscribes *before* suspending, so a `@Published` property that already holds a
    /// matching value resolves immediately — libdatachannel publishes from its own threads,
    /// and a wait that only listens for future changes loses that race.
    public func waitFor(predicate: @Sendable @escaping (Output) -> Bool, timeout: TimeInterval = 1) async throws
    {
        let latch = Latch()
        let cancellable = sink(
            receiveCompletion: { _ in },
            receiveValue: { if predicate($0) { latch.signal() } }
        )
        defer { cancellable.cancel() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw PublisherError.timedOut
            }
            group.addTask { await latch.wait() }

            try await group.next()
            group.cancelAll()
        }
    }

    public func waitFor(value: Output, timeout: TimeInterval = 1) async throws
    {
        try await waitFor(predicate: { $0 == value}, timeout: timeout)
    }
}
