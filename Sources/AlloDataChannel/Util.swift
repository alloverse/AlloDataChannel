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

private extension Publisher where Output: Sendable
{
    // OpenCombine doesn't have Publisher.values, so make our own
    func asyncStream() -> AsyncThrowingStream<Output, any Error>
    {
        AsyncThrowingStream(Output.self, bufferingPolicy: .unbounded) { continuation in
            let cancellable = sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        continuation.finish()
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                },
                receiveValue: { value in
                    _ = continuation.yield(value)
                }
            )

            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

enum PublisherError: Error {
    case timedOut
    case wrongValue
}

extension Publisher
where Output: Equatable & Sendable
{
    public func waitFor(predicate: @Sendable @escaping (Output) -> Bool, timeout: TimeInterval = 1) async throws
    {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw PublisherError.timedOut
            }
            let asyncStream = self.asyncStream()
            group.addTask {
                for try await value in asyncStream where predicate(value) {
                    return
                }
                throw PublisherError.wrongValue
            }

            try await group.next()
            group.cancelAll()
        }
    }
    
    public func waitFor(value: Output, timeout: TimeInterval = 1) async throws
    {
        try await waitFor(predicate: { $0 == value}, timeout: timeout)
    }
}
