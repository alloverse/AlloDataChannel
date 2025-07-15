//
//  AlloWebRTCTest.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-06-17.
//

 import XCTest
 @testable import AlloDataChannel
 
 class ExampleTests: XCTestCase {
     func testExample() async throws
     {
        let peer = AlloWebRTCPeer()
        let constraints = ""
        let offer = try await peer?.createOffer(constrainedBy: constraints)
        print("Offer: \(offer ?? "<nil>")")
     }
 }
