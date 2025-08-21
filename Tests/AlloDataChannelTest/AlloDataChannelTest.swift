//
//  AlloWebRTCTest.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-06-17.
//

 import XCTest
 @preconcurrency import OpenCombineShim
 @testable import AlloDataChannel
 
 class AlloDataChannelTests: XCTestCase {
     func testCreatingOffer() async throws
     {
        AlloWebRTCPeer.enableLogging(at: .debug)
        let peer1 = AlloWebRTCPeer()
        let peer2 = AlloWebRTCPeer()
        
        let p1chan = try peer1.createDataChannel(label: "test", streamId: 1, negotiated: true)
        let p2chan = try peer2.createDataChannel(label: "test", streamId: 1, negotiated: true)
        try peer1.lockLocalDescription(type: .offer)
        
        try await peer1.$gatheringState.waitFor(value: .complete)
        let offer = try peer1.createOffer()
        
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
