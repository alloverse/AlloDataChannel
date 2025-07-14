//
//  AlloWebRTC.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-02-11.
//

import Foundation
import libdatachannel

public class AlloWebRTCPeer
{
    private let peer: OpaquePointer
    
    public struct Error : Swift.Error
    {
        let type: Int
        let subtype: Int
        let message: String
    }
    
    public init?() {
        let observers = AlloWebRTCPeerObservers()
        guard let peer = awebrtc_peer_create(true, false, observers) else {
            return nil
        }
        self.peer = peer
        self.observers = observers
    }
    
    deinit {
        awebrtc_peer_destroy(peer)
    }
    
    private var observers: AlloWebRTCPeerObservers
    
    public func close()
    {
        awebrtc_peer_close(peer)
    }
    
    public func createOffer(constrainedBy constraints: AlloWebRTCOfferAnswerConstraints) async throws -> String
    {
        try await withCheckedThrowingContinuation
        { cont in
            awebrtc_peer_create_offer(peer, constraints) { error, sdp in
                if let error = error {
                    //cont.resume(throwing: Self.Error(type: error., subtype: <#T##Int#>, message: <#T##String#>))
                } else {
                    //cont.resume(returning: String(cString: sdp.c_str()))
                }
            }
        }
    }
    
    public func createAnswer(for offerSdp: String, constrainedBy constraints: [String:String]? = nil) -> String?
    {
        // TODO: implement
        return ""
    }
    
    public func createDataChannel(label: String, reliable: Bool = true)
    {
        // TODO: implement
    }
    
    public func set(local description: String, isOffer: Bool) async throws
    {
    
    }
    
    public func set(remote description: String, isOffer: Bool) async throws
    {
    
    }
    
    public func send(data: Data, on channel: String)
    {
        data.withUnsafeBytes { bytes in
            awebrtc_peer_send_data(peer, channel, bytes.baseAddress, data.count)
        }
    }
    
    public func forwardStream(from otherPeer: AlloWebRTCPeer, streamId: String) -> Bool {
        return awebrtc_peer_forward_stream(otherPeer.peer, peer, streamId) == 1
    }
}
