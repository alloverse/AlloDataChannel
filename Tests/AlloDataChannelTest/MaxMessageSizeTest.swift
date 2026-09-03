//
//  MaxMessageSizeTest.swift
//  AlloDataChannel
//

import Foundation
import Testing
@testable import AlloDataChannel

@Suite(.serialized) struct MaxMessageSizeTests
{
    static let oneMiB = 1024 * 1024

    /// Deterministic filler, so a byte-equality failure is reproducible.
    static func payload(_ count: Int) -> Data
    {
        var byte = UInt8(0)
        return Data((0..<count).map { _ in byte &+= 37; return byte })
    }

    @Test func aMessageLargerThanTheDefaultNeedsBothPeersRaised() async throws
    {
        let sender = makeLoopbackPeer(maxMessageSize: 2 * 1024 * 1024)
        let receiver = makeLoopbackPeer(maxMessageSize: 2 * 1024 * 1024)

        let out = try sender.createDataChannel(label: "screen/big-1", reliability: .reliable)
        try await connect(sender, to: receiver)
        try await waitUntil { out.isOpen }
        try await waitUntil { receiver.dataChannels.contains { $0.label == "screen/big-1" } }
        let incoming = receiver.dataChannels.first { $0.label == "screen/big-1" }!

        #expect(try sender.createOffer().contains("a=max-message-size:2097152"), "the limit is negotiated, so it must reach the SDP")

        let message = Self.payload(Self.oneMiB)
        try out.send(data: message)
        try await waitUntil { incoming.lastMessage != nil }
        #expect(incoming.lastMessage == message)
    }

    /// Negative control: libdatachannel's default is 256 KiB, and the sender obeys the remote's.
    @Test func aMessageLargerThanTheDefaultIsRejectedAtDefaultSize() async throws
    {
        let sender = makeLoopbackPeer()
        let receiver = makeLoopbackPeer()

        let out = try sender.createDataChannel(label: "screen/big-1", reliability: .reliable)
        try await connect(sender, to: receiver)
        try await waitUntil { out.isOpen }

        #expect(throws: AlloWebRTCPeer.Error.self) { try out.send(data: Self.payload(Self.oneMiB)) }
    }
}
