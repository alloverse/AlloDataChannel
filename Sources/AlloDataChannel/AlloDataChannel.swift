//
//  AlloWebRTC.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-02-11.
//

import Foundation
import datachannel
import Combine

public class AlloWebRTCPeer: ObservableObject
{
    // MARK: - Types
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
    
    public enum State: UInt32
    {
        case new = 0
        case connecting = 1
        case connected = 2
        case disconnected = 3
        case failed = 4
        case closed = 5
    }

    public enum IceState: UInt32
    {
        case new = 0
        case checking = 1
        case connected = 2
        case completed = 3
        case failed = 4
        case disconnected = 5
        case closed = 6
    }

    public enum GatheringState: UInt32
    {
        case new = 0
        case inProgress = 1
        case complete = 2
    }

    public enum SignalingState: UInt32
    {
        case stable = 0
        case haveLocalOffer = 1
        case haveRemoteOffer = 2
        case haveLocalPRAnswer = 3
        case haveRemotePRAnswer = 4
    }

    public enum LogLevel: UInt32
    {
        case none = 0
        case fatal = 1
        case error = 2
        case warning = 3
        case info = 4
        case debug = 5
        case verbose = 6
    }

    public enum CertificateType: UInt32
    {
        case standard = 0 // ECDSA
        case ECDSA = 1
        case RSA = 2
    }

    public enum Codec: UInt32
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

    public enum Direction: UInt32
    {
        case unknown = 0
        case sendonly = 1
        case recvonly = 2
        case sendrecv = 3
        case inactive = 4
    }
    
    public struct Description
    {
        public enum DescriptionType: String
        {
            case unspecified = "unspec"
            case offer = "offer"
            case answer = "answer"
            case PRAnswer = "pranswer"
            case rollback = "rollback"
        }
        
        public let type: DescriptionType
        public let sdp: String
    }
    
    public struct ICECandidate
    {
        public let candidate: String
        public let mid: String
    }
    
    // MARK: - External state
    @Published public var state: State = .new
    @Published public var signalingState: SignalingState = .stable
    @Published public var iceState: IceState = .new
    @Published public var gatheringState: GatheringState = .new
    
    @Published public var localDescription: Description? = nil
    @Published public var candidates: [ICECandidate] = []


    // MARK: - Internal state
    private let peerId: Int32
    
    // MARK: - API: Setup and teardown
    public init() throws
    {
        //rtcInitLogger(RTC_LOG_VERBOSE, nil)
        
        var config = rtcConfiguration()
        config.disableAutoNegotiation = true
        config.forceMediaTransport = true
        
        peerId = try Error.orValue(rtcCreatePeerConnection(&config))
        
        try setupCallbacks()
    }
    
    deinit {
        rtcDeletePeerConnection(peerId)
    }
        
    public func close()
    {
        rtcClosePeerConnection(peerId)
    }
    
    // MARK: - Signalling
    
    public func createOffer() throws -> String
    {
        var size: Int32 = 0
        size = try Error.orValue(rtcCreateOffer(peerId, nil, size)) + 1024
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(size)) {
            let _ = try Error.orValue(rtcCreateOffer(peerId, $0.baseAddress, size))
            return String(cString: $0.baseAddress!)
        }
    }
    
    public func createAnswer() throws -> String
    {
        var size: Int32 = 0
        size = try Error.orValue(rtcCreateAnswer(peerId, nil, size)) + 1024
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(size)) {
            let _ = try Error.orValue(rtcCreateAnswer(peerId, $0.baseAddress, size))
            return String(cString: $0.baseAddress!)
        }
    }
    
    /// When local state is configured and you're ready to send offer/answer, lock it in with this method.
    public func lockLocalDescription(type: Description.DescriptionType) throws
    {
        let _ = try Error.orValue(
            type.rawValue.utf8CString.withUnsafeBufferPointer() {
                return rtcSetLocalDescription(peerId, $0.baseAddress)
            }
        )
    }
    
    public func set(remote description: String, type: Description.DescriptionType) throws
    {
        let _ = try Error.orValue(withCStrings([description, type.rawValue]) { vals in
            return rtcSetRemoteDescription(peerId, vals[0], vals[1])}
        )
    }
    
    // MARK: - Data channels
    
    public class Channel
    {
        weak var peer: AlloWebRTCPeer?
        let id: Int32
        internal init(peer: AlloWebRTCPeer? = nil, id: Int32)
        {
            self.peer = peer
            self.id = id
            
            try! setupCallbacks()
        }
        deinit {
            rtcDelete(id)
        }
        
        @Published public var open: Bool = false
        @Published public var lastError: String? = nil
        @Published public var lastMessage: Data? = nil
        
        public func send(data: Data) throws
        {
            let _ = try Error.orValue(data.withUnsafeBytes { ptr in
                return rtcSendMessage(id, ptr.bindMemory(to: CChar.self).baseAddress!, Int32(data.count))
            })
        }
        
        public func close()
        {
            rtcClose(id)
        }
        
        private func setupCallbacks() throws
        {
            rtcSetUserPointer(id, Unmanaged.passUnretained(self).toOpaque())

            let _ = try Error.orValue(rtcSetOpenCallback(id) { _, ptr  in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                this.open = true
            })
            let _ = try Error.orValue(rtcSetClosedCallback(id) { _, ptr  in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                this.open = false
            })
            let _ = try Error.orValue(rtcSetErrorCallback(id) { _, cerror, ptr  in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                let error = String(cString: cerror!)
                this.lastError = error
            })
            let _ = try Error.orValue(rtcSetMessageCallback(id) { _, cdata, size, ptr  in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                let data = Data(bytes: cdata!, count: Int(size))
                this.lastMessage = data
            })
        }
    }
    
    public func createDataChannel(label: String, reliable: Bool = true, streamId: UInt16? = nil, negotiated: Bool = false) throws -> Channel
    {
        let dataChannelId = try Error.orValue(withCStrings([label]) { vals in
            var initData = rtcDataChannelInit(
                reliability:
                    rtcReliability(unordered: !reliable, unreliable: !reliable, maxPacketLifeTime: 0, maxRetransmits: 0),
                protocol: nil,
                negotiated: negotiated,
                manualStream: streamId != nil,
                stream: streamId ?? 0
            )
            return rtcCreateDataChannelEx(peerId, vals[0], &initData)
        })
        
        return Channel(peer: self, id: dataChannelId)
    }
    
    // MARK: - Media streams
    
    public func forwardStream(from otherPeer: AlloWebRTCPeer, streamId: String) -> Bool {
        //return awebrtc_peer_forward_stream(otherPeer.peer, peer, streamId) == 1
        return false
    }
    
    // MARK: - Internals
    private func setupCallbacks() throws
    {
        rtcSetUserPointer(peerId, Unmanaged.passUnretained(self).toOpaque())
        
        let _ = try Error.orValue(rtcSetLocalDescriptionCallback(peerId) { _, sdp, type, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            let sdp = String(cString: sdp!)
            let type = Description.DescriptionType(rawValue: String(cString: type!))!
            this.localDescription = Description(type: type, sdp: sdp)
        })
        let _ = try Error.orValue(rtcSetLocalCandidateCallback(peerId) { _, candidate, mid, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            let candidate = String(cString: candidate!)
            let mid = String(cString: mid!)
            this.candidates.append(ICECandidate(candidate: candidate, mid: mid))
        })
        let _ = try Error.orValue(rtcSetStateChangeCallback(peerId) { _, state, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            this.state = State(rawValue: state.rawValue)!
        })
        let _ = try Error.orValue(rtcSetIceStateChangeCallback(peerId) { _, state, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            this.iceState = IceState(rawValue: state.rawValue)!
        })
        let _ = try Error.orValue(rtcSetGatheringStateChangeCallback(peerId) { _, state, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            this.gatheringState = GatheringState(rawValue: state.rawValue)!
        })
        let _ = try Error.orValue(rtcSetSignalingStateChangeCallback(peerId) { _, state, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            this.signalingState = SignalingState(rawValue: state.rawValue)!
        })
    }
}
