//
//  MediaForwardingUnit.swift
//  AlloDataChannel
//
//  Created by Nevyn Bengtsson on 2025-08-27.
//

import Foundation
import Combine

/// A `MediaForwardingUnit` forwards audio or video data from one track on one peer, to a corresponding freshly created track on given peer.
// TODO: Reuse a single instance to forward to multiple peers?
public class MediaForwardingUnit
{
    public let ingressTrack: AlloWebRTCPeer.Track
    public let egressTrack: AlloWebRTCPeer.Track
    public let egressPeer: AlloWebRTCPeer
    private var ssrc: UInt32? = nil
    private var cancellables: Set<AnyCancellable> = []
    
    /// Creates a `MediaForwardingUnit` that forwards the given track to the given peer immediately. It will create a new track in the outgoing peer, and start sending messages on it as soon as that track is available.
    /// Please note: you must `lockLocalDescription` for the outgoing peer and perform renegotiation to open the track yourself after creating this instance.
    public init(forwarding track: AlloWebRTCPeer.Track, to peer: AlloWebRTCPeer) throws
    {
        ingressTrack = track
        try ingressTrack.installRtcpReceivingSession()
        egressPeer = peer
        egressTrack = try egressPeer.createTrack(
            streamId: ingressTrack.streamId,
            trackId: ingressTrack.trackId,
            direction: .sendonly,
            codec: .OPUS, //TODO: ingressTrack.codec,
            sampleOrBitrate: 3000, // TODO: ingressTrack.sampleOrBitrate,
            channelCount: 1, //TODO: ingressTrack.channelCount
        )
        try egressTrack.installRtcpReceivingSession()
        egressTrack.onKeyFrameRequested = {
            guard self.ingressTrack.isOpen else { return }
            try? self.ingressTrack.requestKeyFrame()
        }
        
        
        ingressTrack.$lastMessage.sink
        { message in
            guard var data = message, self.egressTrack.isOpen else { return }
            if self.ssrc == nil
            {
                self.ssrc = self.ingressTrack.ssrcs.first!
            }
            do {
                RtpHeaderRewriteSSRC(in: &data, to: self.ssrc!)
                try self.egressTrack.send(data: data)
            } catch let e
            {
                print("Failed to forward packet to \(self.egressPeer.peerId): \(e)")
            }
        }.store(in: &cancellables)
    }
    
    /// Stops forwarding on the track and breaks reference cycles. Does not delete the outgoing track.
    public func stop()
    {
        for c in cancellables { c.cancel() }
        egressTrack.onKeyFrameRequested = nil
    }
}
