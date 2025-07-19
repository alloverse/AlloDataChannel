//
//  AlloWebRTCTest.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-06-17.
//

 import XCTest
 import Combine
 @testable import AlloDataChannel
 
 enum TestError: Error {
    case timedOut
    case wrongValue
}
extension Publisher
where Output: Equatable
{
    public func waitFor(predicate: @escaping (Output) -> Bool, timeout: TimeInterval = 1) async throws
    {
        var iter = first(where: predicate).values.makeAsyncIterator()
        // TODO: use timeout to throw if exceeded
        let found = try await iter.next()
        guard let found, predicate(found) else {
            throw TestError.wrongValue
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
        let peer1 = try AlloWebRTCPeer()
        let peer2 = try AlloWebRTCPeer()
        
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
