//
//  ReliabilityTest.swift
//  AlloDataChannel
//

import Foundation
import Testing
@testable import AlloDataChannel

@Suite(.serialized) struct ReliabilityTests
{
    /// What a screen stream asks for: ordered, but a frame older than a second is dropped
    /// rather than retransmitted. Both halves have to survive DCEP to the receiving side.
    @Test func anOrderedLifetimeLimitedChannelSurvivesDCEP() async throws
    {
        let sender = makeLoopbackPeer()
        let receiver = makeLoopbackPeer()

        let wanted = AlloWebRTCPeer.Reliability(loss: .maxPacketLifeTime(ms: 1000), ordered: true)
        let out = try sender.createDataChannel(label: "screen/abc-1", reliability: wanted)

        try await connect(sender, to: receiver)
        try await waitUntil { out.isOpen }
        try await waitUntil { receiver.dataChannels.contains { $0.label == "screen/abc-1" } }
        let incoming = receiver.dataChannels.first { $0.label == "screen/abc-1" }!

        #expect(out.reliability == wanted)
        #expect(incoming.reliability == wanted)
        #expect(incoming.reliability.ordered)
    }
}
