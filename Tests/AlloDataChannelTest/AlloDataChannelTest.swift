//
//  AlloWebRTCTest.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-06-17.
//

 import XCTest
 @testable import AlloDataChannel
 
 class AlloDataChannelTests: XCTestCase {
     func testCreatingOffer() async throws
     {
        let peer = try AlloWebRTCPeer()
        let offer = try await peer.createOffer()
        print("Offer: \(offer)")
     }
 }
