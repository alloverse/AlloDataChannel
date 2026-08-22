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
        let peer1 = makeLoopbackPeer()
        let peer2 = makeLoopbackPeer()

        let p1chan = try peer1.createDataChannel(label: "test", streamId: 1, negotiated: true)
        let p2chan = try peer2.createDataChannel(label: "test", streamId: 1, negotiated: true)

        try await connect(peer1, to: peer2)
        try await waitUntil(timeout: TimeInterval(10)) { p1chan.isOpen }
        try await waitUntil(timeout: TimeInterval(10)) { p2chan.isOpen }

        let message = "Test".data(using: .utf8)!
        try p1chan.send(data: message)

        try await waitUntil(timeout: TimeInterval(10)) { p2chan.lastMessage == message }
    }

    /// The voice path needs channels opened in-band (only the sender creates them) that
    /// drop rather than retransmit. Prove both: that the label and reliability survive the
    /// trip through DCEP, and that messages flow on the resulting channel.
    func testUnreliableInBandChannel() async throws
    {
        let sender = makeLoopbackPeer()
        let receiver = makeLoopbackPeer()

        let out = try sender.createDataChannel(label: "voice/abc-1", reliability: .unreliable)
        let received = Collector(of: receiver)

        try await connect(sender, to: receiver)
        try await waitUntil(timeout: TimeInterval(10)) { out.isOpen }

        // The receiver never called createDataChannel; the channel arrives over DCEP.
        try await waitUntil { receiver.dataChannels.contains { $0.label == "voice/abc-1" } }
        let incoming = receiver.dataChannels.first { $0.label == "voice/abc-1" }!
        received.observe(incoming)

        XCTAssertEqual(out.reliability, .unreliable)
        XCTAssertEqual(incoming.reliability, .unreliable, "reliability must survive DCEP to the receiving side")
        XCTAssertEqual(incoming.reliability.loss, .maxRetransmits(0), "a retransmitted voice frame is a late voice frame")

        let sent = (0..<200).map { seq in withUnsafeBytes(of: UInt32(seq).bigEndian) { Data($0) } }
        for message in sent { try out.send(data: message) }

        // Loopback drops nothing, so every frame must land. Order is not guaranteed on an
        // unordered channel, so compare as sets.
        try await waitUntil { received.count == sent.count }
        XCTAssertEqual(Set(received.messages), Set(sent))
    }

    /// Reliability is per-channel: the control channels must stay ordered and reliable even
    /// while an unreliable media channel shares the same peer connection.
    func testMixedReliabilityOnOnePeerConnection() async throws
    {
        let sender = makeLoopbackPeer()
        let receiver = makeLoopbackPeer()

        let control = try sender.createDataChannel(label: "interactions", reliability: .reliable, streamId: 1, negotiated: true)
        let controlIn = try receiver.createDataChannel(label: "interactions", reliability: .reliable, streamId: 1, negotiated: true)
        let media = try sender.createDataChannel(label: "voice/abc-1", reliability: .unreliable)

        try await connect(sender, to: receiver)
        try await waitUntil(timeout: TimeInterval(10)) { control.isOpen }
        try await waitUntil(timeout: TimeInterval(10)) { controlIn.isOpen }
        try await waitUntil(timeout: TimeInterval(10)) { media.isOpen }

        XCTAssertEqual(control.reliability, .reliable)
        XCTAssertEqual(controlIn.reliability, .reliable)
        XCTAssertEqual(media.reliability, .unreliable)
        XCTAssertTrue(control.reliability.ordered)
        XCTAssertFalse(media.reliability.ordered)
    }

    /// A forwarder that stops must take its channel with it on the far side, or the receiver
    /// keeps a stream nothing will ever write to.
    func testRemoteCloseRemovesTheChannel() async throws
    {
        let sender = makeLoopbackPeer()
        let receiver = makeLoopbackPeer()
        let out = try sender.createDataChannel(label: "voice/abc-1", reliability: .unreliable)

        try await connect(sender, to: receiver)
        try await waitUntil(timeout: TimeInterval(10)) { out.isOpen }
        try await waitUntil { receiver.dataChannels.contains { $0.label == "voice/abc-1" } }

        out.close()
        try await waitUntil { receiver.dataChannels.isEmpty }
        XCTAssertTrue(sender.dataChannels.isEmpty, "the closing side forgets it too")
    }
}


// MARK: - Harness

extension XCTestCase
{
    /// A peer that gathers candidates on loopback only, so a test never depends on the host
    /// having a usable network interface (or on macOS granting local-network access).
    func makeLoopbackPeer() -> AlloWebRTCPeer { AlloWebRTCPeer(bindAddress: "127.0.0.1") }

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

}

/// Accumulates every message seen on the channels it observes. `lastMessage` only keeps one
/// message, so a test that counts has to subscribe rather than sample.
private final class Collector: @unchecked Sendable
{
    // Recursive: `@Published` replays its current value synchronously on subscribe, so
    // `observe` re-enters through the sink while it still holds the lock.
    private let lock = NSRecursiveLock()
    private var storage: [Data] = []
    private var cancellables = Set<AnyCancellable>()

    init(of peer: AlloWebRTCPeer)
    {
        peer.$dataChannels.sink { [weak self] channels in
            for channel in channels { self?.observe(channel) }
        }.store(in: &cancellables)
    }

    func observe(_ channel: AlloWebRTCPeer.DataChannel)
    {
        lock.lock(); defer { lock.unlock() }
        guard observed.insert(channel.id).inserted else { return }
        channel.$lastMessage.sink { [weak self] message in
            guard let self, let message else { return }
            lock.lock(); defer { lock.unlock() }
            storage.append(message)
        }.store(in: &cancellables)
    }
    private var observed = Set<Int32>()

    var messages: [Data] { lock.lock(); defer { lock.unlock() }; return storage }
    var count: Int { lock.lock(); defer { lock.unlock() }; return storage.count }
}
