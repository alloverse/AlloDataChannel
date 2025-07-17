//
//  AlloWebRTC.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-02-11.
//

import Foundation
import datachannel

public class AlloWebRTCPeer
{
    // MARK: Types
    public enum Error : Int32, Swift.Error
    {
        case invalid = -1
        case failure = -2
        case elementNotAvailable = -3
        case bufferTooSmall = -4
        
        static func fromInt32(_ code: Int32) -> Error {
            return Self(rawValue: code) ?? .invalid
        }
        static func orValue(_ code: Int32) throws -> Int32
        {
            guard code >= 0 else {
                throw Error.fromInt32(code)
            }
            return code
        }
    }
    
    enum State: UInt32
    {
        case new = 0
        case connecting = 1
        case connected = 2
        case disconnected = 3
        case failed = 4
        case closed = 5
    }

    enum IceState: UInt32
    {
        case new = 0
        case checking = 1
        case connected = 2
        case completed = 3
        case failed = 4
        case disconnected = 5
        case closed = 6
    }

    enum GatheringState: UInt32
    {
        case new = 0
        case inProgress = 1
        case complete = 2
    }

    enum SignalingState: UInt32
    {
        case stable = 0
        case haveLocalOffer = 1
        case haveRemoteOffer = 2
        case haveLocalPRAnswer = 3
        case haveRemotePRAnswer = 4
    }

    enum LogLevel: UInt32
    {
        case none = 0
        case fatal = 1
        case error = 2
        case warning = 3
        case info = 4
        case debug = 5
        case verbose = 6
    }

    enum CertificateType: UInt32
    {
        case standard = 0 // ECDSA
        case ECDSA = 1
        case RSA = 2
    }

    enum Codec: UInt32
    {
        // video
        case H264 = 0
        case VP8 = 1
        case VP9 = 2
        case H265 = 3
        case AV1 = 4

        // audio
        case OPUS = 128
        case PCMU = 129
        case PCMA = 130
        case AAC = 131
        case G722 = 132
    }

    enum Direction: UInt32
    {
        case unknown = 0
        case sendonly = 1
        case recvonly = 2
        case sendrecv = 3
        case inactive = 4
    }

    // MARK: Internal state
    private let peerId: Int32
    
    // MARK: Public API
    public init() throws
    {
        //rtcInitLogger(RTC_LOG_INFO, nil)
        
        var config = rtcConfiguration()
        config.disableAutoNegotiation = true
        config.forceMediaTransport = true
        
        peerId = try Error.orValue(rtcCreatePeerConnection(&config))
        
        rtcSetUserPointer(peerId, Unmanaged.passUnretained(self).toOpaque())
        
        try setupCallbacks()
    }
    
    deinit {
        rtcDeletePeerConnection(peerId)
    }
    
    private func setupCallbacks() throws
    {
        //let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
        let _ = try Error.orValue(rtcSetLocalDescriptionCallback(peerId) { _, sdp, type, _  in
            let sdp = String(cString: sdp!)
            let type = String(cString: type!)
            print(">> Local description (type \(type): \(sdp)")
        })
        let _ = try Error.orValue(rtcSetLocalCandidateCallback(peerId) { _, candidate, mid, _  in
            let candidate = String(cString: candidate!)
            let mid = String(cString: mid!)
            print(">> New local candidate: \(candidate) // \(mid)")
        })
        let _ = try Error.orValue(rtcSetStateChangeCallback(peerId) { _, state, _  in
            let state = State(rawValue: state.rawValue)!
            print(">> New RTC state: \(state)")
        })
        let _ = try Error.orValue(rtcSetIceStateChangeCallback(peerId) { _, state, _  in
            let state = IceState(rawValue: state.rawValue)!
            print(">> New ICE state: \(state)")
        })
        let _ = try Error.orValue(rtcSetGatheringStateChangeCallback(peerId) { _, state, _  in
            let state = GatheringState(rawValue: state.rawValue)!
            print(">> New gathering state: \(state)")
        })
        let _ = try Error.orValue(rtcSetSignalingStateChangeCallback(peerId) { _, state, _  in
            let state = SignalingState(rawValue: state.rawValue)!
            print(">> New signaling state: \(state) ")
        })
    }
    
    public func close()
    {
        rtcClosePeerConnection(peerId)
    }
    
    public func createOffer() async throws -> String
    {
        var size: Int32 = 0
        size = try Error.orValue(rtcCreateOffer(peerId, nil, size))
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(size)) {
            let _ = try Error.orValue(rtcCreateOffer(peerId, $0.baseAddress, size))
            return String(cString: $0.baseAddress!)
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
        /*data.withUnsafeBytes { bytes in
            awebrtc_peer_send_data(peer, channel, bytes.baseAddress, data.count)
        }*/
    }
    
    public func forwardStream(from otherPeer: AlloWebRTCPeer, streamId: String) -> Bool {
        //return awebrtc_peer_forward_stream(otherPeer.peer, peer, streamId) == 1
        return false
    }
}
