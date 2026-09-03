//
//  BackpressureTest.swift
//  AlloDataChannel
//

import Foundation
import Testing
@testable import AlloDataChannel

@Suite(.serialized) struct BackpressureTests
{
    @Test func aBurstBuffersAndThenReportsItselfDrained() async throws
    {
        let sender = makeLoopbackPeer()
        let receiver = makeLoopbackPeer()

        let out = try sender.createDataChannel(label: "screen/burst-1", reliability: .reliable)
        try await connect(sender, to: receiver)
        try await waitUntil { out.isOpen }

        let drained = Flag()
        out.setBufferedAmountLowThreshold(64 * 1024)
        out.onBufferedAmountLow = { drained.raise() }

        let message = Data(repeating: 0x5a, count: 64 * 1024)
        var peakBuffered = 0
        for _ in 0..<256
        {
            try out.send(data: message)
            peakBuffered = max(peakBuffered, out.bufferedAmount)
        }

        #expect(peakBuffered > 0, "a 16 MiB burst must outrun the transport")
        try await waitUntil { drained.isRaised }
        #expect(out.bufferedAmount <= 64 * 1024)
    }
}

/// The low callback arrives on libdatachannel's thread; the test reads from its own.
private final class Flag: @unchecked Sendable
{
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.lock(); defer { lock.unlock() }; raised = true }
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return raised }
}
