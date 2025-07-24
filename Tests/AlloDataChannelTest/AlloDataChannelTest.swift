//
//  AlloWebRTCTest.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-06-17.
//

 import XCTest
 @preconcurrency import OpenCombineShim
 @testable import AlloDataChannel
 
 enum TestError: Error {
    case timedOut
    case wrongValue
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

extension Publisher
where Output: Equatable & Sendable
{
    public func waitFor(predicate: @Sendable @escaping (Output) -> Bool, timeout: TimeInterval = 1) async throws
    {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TestError.timedOut
            }
            let asyncStream = self.asyncStream()
            group.addTask {
                for try await value in asyncStream where predicate(value) {
                    return
                }
                throw TestError.wrongValue
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
 
 class AlloDataChannelTests: XCTestCase {
     func testCreatingOffer() async throws
     {
        let peer1 = AlloWebRTCPeer()
        let peer2 = AlloWebRTCPeer()
        
        let p1chan = try peer1.createDataChannel(label: "test", streamId: 1, negotiated: true)
        let p2chan = try peer2.createDataChannel(label: "test", streamId: 1, negotiated: true)
        try peer1.lockLocalDescription(type: .offer)
        
        let offer = try peer1.createOffer()
        try await peer1.$gatheringState.waitFor(value: .complete)
        
        try peer2.set(remote: offer, type: .offer)
        try peer2.lockLocalDescription(type: .answer)
        
        try await peer2.$gatheringState.waitFor(value: .complete)
        let answer = try peer2.createAnswer()
        
        try peer1.set(remote: answer, type: .answer)
        
        try await peer1.$state.waitFor(value: .connected)
        try await peer2.$state.waitFor(value: .connected)
        try await p1chan.$open.waitFor(value: true)
        try await p2chan.$open.waitFor(value: true)
        
        let message = "Test".data(using: .utf8)!
        try p1chan.send(data: message)
        
        try await p2chan.$lastMessage.waitFor(value: message)
     }
 }
