//
//  LoopbackPair.swift
//  AlloDataChannel
//

import Foundation
@testable import AlloDataChannel

// Free functions rather than an XCTestCase extension, so the Swift Testing suites reach them too.

/// Loopback-only peer, so tests need no usable network interface.
func makeLoopbackPeer(maxMessageSize: Int? = nil) -> AlloWebRTCPeer
{
    AlloWebRTCPeer(bindAddress: "127.0.0.1", maxMessageSize: maxMessageSize)
}

/// Connect two peers over in-process loopback. Any negotiated channels must already exist
/// on both sides; in-band channels only on the offering side.
func connect(_ offerer: AlloWebRTCPeer, to answerer: AlloWebRTCPeer, timeout: TimeInterval = 10) async throws
{
    try offerer.lockLocalDescription(type: .offer)
    try await waitUntil(timeout: TimeInterval(timeout)) { offerer.gatheringState == .complete }
    let offer = try offerer.createOffer()

    try answerer.set(remote: offer, type: .offer)
    try answerer.lockLocalDescription(type: .answer)
    try await waitUntil(timeout: TimeInterval(timeout)) { answerer.gatheringState == .complete }
    let answer = try answerer.createAnswer()

    try offerer.set(remote: answer, type: .answer)

    try await waitUntil(timeout: TimeInterval(timeout)) { offerer.state == .connected }
    try await waitUntil(timeout: TimeInterval(timeout)) { answerer.state == .connected }
}
