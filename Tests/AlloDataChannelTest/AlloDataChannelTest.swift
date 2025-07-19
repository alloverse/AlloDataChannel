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
    public func waitFor(value: Output, timeout: TimeInterval = 1) async throws
    {
        var iter = first(where: {$0 == value}).values.makeAsyncIterator()
        // TODO: use timeout to throw if exceeded
        let found = try await iter.next()
        guard found == value else {
            throw TestError.wrongValue
        }
    }
}
 
 class AlloDataChannelTests: XCTestCase {
     func testCreatingOffer() async throws
     {
        let peer1 = try AlloWebRTCPeer()
        let peer2 = try AlloWebRTCPeer()
        
        let p1chan = try peer1.createDataChannel(label: "test")
        
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
     }
 }
