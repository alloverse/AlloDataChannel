//
//  AlloWebRTC.swift
//  AlloWebRTC
//
//  Created by Nevyn Bengtsson on 2025-02-11.
//

import Foundation
import datachannel
import OpenCombineShim
import AlloDataChannelCpp

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
    
    public enum State: UInt32, Sendable
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

    public enum GatheringState: UInt32, Sendable
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
        
        public var isVideo: Bool
        {
            switch self
            {
            case .H264, .VP8, .VP9, .H265, .AV1: return true
            case .OPUS, .PCMU, .PCMA, .AAC, .G722: return false
            }
        }
    }

    public enum Direction: UInt32
    {
        case unknown = 0
        case sendonly = 1
        case recvonly = 2
        case sendrecv = 3
        case inactive = 4
    }
    
    public struct Description: Codable
    {
        public enum DescriptionType: String, Codable
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
        public init(candidate: String, mid: String)
        {
            self.candidate = candidate
            self.mid = mid
        }
    }
    
    public struct IPOverride
    {
        public let from: String
        public let to: String
        public init(from: String, to: String)
        {
            self.from = from
            self.to = to
        }
    }
    
    // MARK: - External state
    @Published public var state: State = .new
    @Published public var signalingState: SignalingState = .stable
    @Published public var iceState: IceState = .new
    @Published public var gatheringState: GatheringState = .new
    
    @Published public var localDescription: Description? = nil
    @Published public var candidates: [ICECandidate] = []
    
    @Published public var channels: Set<Channel> = [] // both datachannels and tracks
    @Published public var dataChannels: Set<DataChannel> = []
    @Published public var tracks: Set<Track> = []


    // MARK: - Internal state
    public let peerId: Int32
    private let ipOverride: IPOverride?
    
    // MARK: - API: Setup and teardown
    /// - Parameter bindAddress: gather candidates on this interface only; "127.0.0.1" keeps
    ///   the connection inside the machine, and needs no macOS local-network permission.
    /// - Parameter maxMessageSize: the largest single message, in bytes, that may be sent on
    ///   any data channel of this peer connection. It is advertised in the SDP as
    ///   `a=max-message-size` and the sending side obeys the *remote* peer's value, so both
    ///   peers must be configured with it for a large message to get through. Nil keeps
    ///   libdatachannel's default of 256 KiB.
    public init(
        autoNegotiate: Bool = false,
        forceMediaTransport: Bool = true,
        portRange: Range<Int>? = nil,
        ipOverride: IPOverride? = nil,
        bindAddress: String? = nil,
        maxMessageSize: Int? = nil
    )
    {
        var config = rtcConfiguration()
        config.disableAutoNegotiation = !autoNegotiate
        config.forceMediaTransport = forceMediaTransport
        if let portRange
        {
            config.portRangeBegin = UInt16(portRange.lowerBound)
            config.portRangeEnd = UInt16(portRange.upperBound)
        }
        if let maxMessageSize
        {
            config.maxMessageSize = Int32(maxMessageSize)
        }

        self.peerId = withOptionalCString(bindAddress) { bind in
            config.bindAddress = bind
            return try! Error.orValue(rtcCreatePeerConnection(&config))
        }
        self.ipOverride = ipOverride
        Teardown.remember(peer: peerId)

        try! setupCallbacks()
    }
    
    deinit {
        Teardown.forget(peer: peerId)
        rtcDeletePeerConnection(peerId)
    }
        
    public func close()
    {
        rtcClosePeerConnection(peerId)
    }

    /// Drop a channel from the published sets, whichever side closed it.
    fileprivate func forget(_ channel: Channel)
    {
        channels.remove(channel)
        if let dataChannel = channel as? DataChannel { dataChannels.remove(dataChannel) }
        if let track = channel as? Track { tracks.remove(track) }
    }
    
    nonisolated(unsafe) static var loggingCallback: ((LogLevel, String) -> Void)? = nil
    static public func enableLogging(at level: LogLevel, to callback: ((LogLevel, String) -> Void)? = nil)
    {
        loggingCallback = callback
        rtcInitLogger(rtcLogLevel(level.rawValue), (callback != nil) ? { clevel, msg in
            guard let msg else { return }
            let level = LogLevel(rawValue: clevel.rawValue)!
            let str = String(cString: msg)
            AlloWebRTCPeer.loggingCallback?(level, str)
        } : nil)
    }
    
    // MARK: - Signalling
    
    public func createOffer() throws -> String
    {
        var size: Int32 = 0
        size = try Error.orValue(rtcCreateOffer(peerId, nil, size)) + 1024
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(size)) {
            let _ = try Error.orValue(rtcCreateOffer(peerId, $0.baseAddress, size))
            return sanitizeSdp(String(cString: $0.baseAddress!))
        }
    }
    
    public func createAnswer() throws -> String
    {
        var size: Int32 = 0
        size = try Error.orValue(rtcCreateAnswer(peerId, nil, size)) + 1024
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(size)) {
            let _ = try Error.orValue(rtcCreateAnswer(peerId, $0.baseAddress, size))
            return sanitizeSdp(String(cString: $0.baseAddress!))
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
    
    public func set(remote description: Description) throws
    {
        try set(remote: description.sdp, type: description.type)
    }
    
    public func set(remote description: String, type: Description.DescriptionType) throws
    {
        let _ = try Error.orValue(withCStrings([description, type.rawValue]) { vals in
            return rtcSetRemoteDescription(peerId, vals[0], vals[1])}
        )
    }
    
    public func add(remote candidate: ICECandidate) throws
    {
        let _ = try Error.orValue(withCStrings([candidate.candidate, candidate.mid]) { vals in
            return rtcAddRemoteCandidate(peerId, vals[0], vals[1])}
        )
    }
    
    // MARK: - Channels
    
    public class Channel: Equatable, Hashable
    {
        weak var peer: AlloWebRTCPeer?
        public let id: Int32
        internal init(peer: AlloWebRTCPeer? = nil, id: Int32)
        {
            self.peer = peer
            self.id = id
            Teardown.remember(channel: id)
            
            try! setupCallbacks()
        }
        deinit
        {
            // Add some check that we're really closed before deleting? Because if we're not, we might still
            // be in peer's list of channels/tracks etc...
            Teardown.forget(channel: id)
            rtcDelete(id)
        }
        
        @Published public var isOpen: Bool = false
        @Published public var lastError: String? = nil
        @Published public var lastMessage: Data? = nil
        
        public func send(data: Data) throws
        {
            let _ = try Error.orValue(data.withUnsafeBytes { ptr in
                return rtcSendMessage(id, ptr.bindMemory(to: CChar.self).baseAddress!, Int32(data.count))
            })
        }

        /// Bytes handed to `send` that the transport has not yet put on the wire. Rises when
        /// the sender outruns the link, and is the signal to send less: `send` itself never
        /// blocks and never reports congestion.
        ///
        /// Force-tries, like `DataChannel.reliability`: the C call only fails on an id that
        /// is no longer a channel, which cannot happen while this object is alive.
        public var bufferedAmount: Int
        {
            Int(try! Error.orValue(rtcGetBufferedAmount(id)))
        }

        /// Arm `onBufferedAmountLow` to fire when `bufferedAmount` drops to `bytes` or below.
        /// The threshold is a level, not a one-shot: the callback fires on every crossing.
        /// Force-tries, on the same grounds as `bufferedAmount`.
        public func setBufferedAmountLowThreshold(_ bytes: Int)
        {
            _ = try! Error.orValue(rtcSetBufferedAmountLowThreshold(id, Int32(bytes)))
        }

        /// Called when the send queue has drained past the threshold set with
        /// `setBufferedAmountLowThreshold`, on libdatachannel's own thread. Hop to your own
        /// executor before touching anything the rest of your program owns.
        public var onBufferedAmountLow: (() -> Void)? = nil
        
        public func close()
        {
            rtcClose(id)
            peer?.forget(self)
        }
        
        internal func setupCallbacks() throws
        {
            rtcSetUserPointer(id, Unmanaged.passUnretained(self).toOpaque())

            let _ = try Error.orValue(rtcSetOpenCallback(id) { _, ptr  in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                this.isOpen = true
            })
            let _ = try Error.orValue(rtcSetClosedCallback(id) { _, ptr  in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                this.isOpen = false
                this.peer?.forget(this)
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
            let _ = try Error.orValue(rtcSetBufferedAmountLowCallback(id) { _, ptr in
                let this = Unmanaged<Channel>.fromOpaque(ptr!).takeUnretainedValue()
                this.onBufferedAmountLow?()
            })
        }
        
        public static func == (lhs: AlloWebRTCPeer.Channel, rhs: AlloWebRTCPeer.Channel) -> Bool
        {
            lhs.id == rhs.id
        }
        public var hashValue: Int {
            return Int(id)
        }
    }
    
    // MARK: - Data Channels
    
    public class DataChannel: Channel
    {
        /// The SCTP stream this channel rides on. Nil until the channel opens: a channel
        /// negotiated in-band has no stream assigned until the association is up.
        public var streamId: Int32? {
            let stream = rtcGetDataChannelStream(id)
            return stream >= 0 ? stream : nil
        }
        public let label: String
        internal override init(peer: AlloWebRTCPeer? = nil, id: Int32)
        {
            let len = try! Error.orValue(rtcGetDataChannelLabel(id, nil, 0))
            var buf = [CChar](repeating: 0, count: Int(len))
            let _ = try! Error.orValue(rtcGetDataChannelLabel(id, &buf, len))
            self.label = String(cString: &buf)
            
            super.init(peer: peer, id: id)
        }

        /// What this channel actually negotiated. On a channel opened by the remote peer,
        /// this is what that peer asked for, carried over in the DCEP OPEN message.
        public var reliability: Reliability {
            var c = rtcReliability()
            _ = try! Error.orValue(rtcGetDataChannelReliability(id, &c))
            return Reliability(c: c)
        }
    }
    
    /// Delivery guarantees for a data channel (RFC 8831 §6.1). Loss policy and ordering are
    /// independent: every `Loss` exists in an ordered and an unordered form on the wire.
    public struct Reliability: Equatable, Sendable
    {
        public enum Loss: Equatable, Sendable
        {
            /// Retransmit until delivered, like TCP. The SCTP default.
            case retransmitForever
            /// Give up after this many retransmissions. `0` sends once and never retransmits.
            case maxRetransmits(UInt32)
            /// Give up once the message is older than this.
            case maxPacketLifeTime(ms: UInt32)
        }

        public let loss: Loss
        /// Deliver in send order, head-of-line blocking behind an outstanding message. With a
        /// lossy `loss`, an abandoned message is skipped rather than waited for.
        public let ordered: Bool

        public init(loss: Loss, ordered: Bool)
        {
            self.loss = loss
            self.ordered = ordered
        }

        /// Ordered and fully reliable, like TCP.
        public static let reliable = Self(loss: .retransmitForever, ordered: true)
        /// Unordered with no retransmissions, like UDP. Correct for real-time media,
        /// where a late frame is worthless and a retransmission only adds latency.
        public static let unreliable = Self(loss: .maxRetransmits(0), ordered: false)

        fileprivate var c: rtcReliability
        {
            switch loss
            {
            case .retransmitForever:
                return rtcReliability(unordered: !ordered, unreliable: false, maxPacketLifeTime: 0, maxRetransmits: 0)
            case .maxRetransmits(let n):
                return rtcReliability(unordered: !ordered, unreliable: true, maxPacketLifeTime: 0, maxRetransmits: n)
            case .maxPacketLifeTime(let ms):
                return rtcReliability(unordered: !ordered, unreliable: true, maxPacketLifeTime: ms, maxRetransmits: 0)
            }
        }

        fileprivate init(c: rtcReliability)
        {
            // capi reports at most one limit, and neither when reliable; a lifetime of 0 is "unset".
            ordered = !c.unordered
            loss = !c.unreliable ? .retransmitForever
                 : c.maxPacketLifeTime > 0 ? .maxPacketLifeTime(ms: c.maxPacketLifeTime)
                 : .maxRetransmits(c.maxRetransmits)
        }
    }

    public func createDataChannel(label: String, reliability: Reliability = .reliable, streamId: UInt16? = nil, negotiated: Bool = false) throws -> DataChannel
    {
        let dataChannelId = try Error.orValue(withCStrings([label]) { vals in
            var initData = rtcDataChannelInit(
                reliability: reliability.c,
                protocol: nil,
                negotiated: negotiated,
                manualStream: streamId != nil,
                stream: streamId ?? 0
            )
            return rtcCreateDataChannelEx(peerId, vals[0], &initData)
        })
        if let existing = self.dataChannels.first(where: { $0.id == dataChannelId })
        {
            return existing
        }
        let chan = DataChannel(peer: self, id: dataChannelId)
        self.channels.insert(chan)
        self.dataChannels.insert(chan)
        return chan
    }
    
    // MARK: - Tracks
    
    public class Track: Channel
    {
        public let streamId: String
        public let trackId: String
        public let direction: Direction
        
        public let ssrcs: [UInt32]
        public var onKeyFrameRequested: (() -> Void)?
        {
            didSet
            {
                _ = try! Error.orValue(rtcChainPliHandler(id, onKeyFrameRequested == nil ? nil :
                { _, ptr in
                    let this = Unmanaged<Track>.fromOpaque(ptr!).takeUnretainedValue()
                    this.onKeyFrameRequested?()
                }))
            }
        }

        internal required init(peer: AlloWebRTCPeer? = nil, id: Int32, streamId: String, trackId: String)
        {
            let needed = Int(try! Error.orValue(rtcGetSsrcsForTrack(id, nil, 0)))
            var cssrcs = [UInt32](repeating: 0, count: needed)
            if needed > 0
            {
                _ = try! Error.orValue(cssrcs.withUnsafeMutableBufferPointer { buf in
                    rtcGetSsrcsForTrack(id, buf.baseAddress, Int32(buf.count))
                })
            }
            self.ssrcs = cssrcs
            
            var direction = rtcDirection(rawValue: 0)
            _ = try! Error.orValue(rtcGetTrackDirection(id, &direction))
            
            self.streamId = streamId
            self.trackId = trackId
            self.direction = Direction(rawValue: direction.rawValue)!
            super.init(peer: peer, id: id)
        }
        
        
        public func payloadTypesForCodec(_ codecName: String) throws -> [UInt8]
        {
            return try withCStrings([codecName]) { vals in
                let needed = Int(try Error.orValue(rtcGetTrackPayloadTypesForCodec(id, vals[0], nil, 0)))
                var pts = [Int32](repeating: 0, count: needed)
                _ = try Error.orValue(pts.withUnsafeMutableBufferPointer { buf in
                    rtcGetTrackPayloadTypesForCodec(id, vals[0], buf.baseAddress, Int32(buf.count))
                })
                return pts.map { UInt8($0) }
            }
        }
        
        // Installs a handler that manages bitrate negotiation, keyframe requests, etc.
        private var hasInstalledRtcpReceivingSession = false
        public func installRtcpReceivingSession() throws
        {
            guard hasInstalledRtcpReceivingSession == false else { return }
            _ = try Error.orValue(rtcChainRtcpReceivingSession(id))
            hasInstalledRtcpReceivingSession = true
        }
        
        // Only possible if a RtcpReceivingSession is installed
        public func requestKeyFrame() throws
        {
            let _ = try Error.orValue(rtcRequestKeyframe(id))
        }
        
        // Only possible if a RtcpReceivingSession is installed
        public func requestBitRate(_ bps: UInt32) throws
        {
            let _ = try Error.orValue(rtcRequestBitrate(id, bps))
        }
        
        internal static func GetMid(_ id: Int32) throws -> String
        {
            let len = try Error.orValue(rtcGetTrackMid(id, nil, 0))
            var buf = [CChar](repeating: 0, count: Int(len))
            let _ = try! Error.orValue(rtcGetTrackMid(id, &buf, len))
            return String(cString: &buf)
        }
        
        internal static func GetDescription(_ id: Int32) throws -> String
        {
            let len = try Error.orValue(rtcGetTrackDescription(id, nil, 0))
            var buf = [CChar](repeating: 0, count: Int(len))
            let _ = try! Error.orValue(rtcGetTrackDescription(id, &buf, len))
            return String(cString: &buf)
        }
        
        internal struct Msid
        {
            let streamId: String
            let trackId: String
        }
        
        internal static func GetMsid(_ id: Int32) throws -> Msid
        {
            // No accessor in libdatachannel's API to get stream & track ID afaik, so we need to parse sdp, both unified and plan b.
            let desc = try GetDescription(id)
            let sdp = desc.replacingOccurrences(of: "\r\n", with: "\n")
            
            if let line = sdp.split(separator: "\n").first(where: { $0.hasPrefix("a=msid:") }) {
                let parts = line.dropFirst("a=msid:".count).split(separator: " ")
                if parts.count >= 2 { return Msid(streamId: String(parts[0]), trackId: String(parts[1])) }
                if parts.count == 1 { return Msid(streamId: String(parts[0]), trackId: String(parts[0])) }
            }
            if let line = sdp.split(separator: "\n").first(where: { $0.contains(" msid ") && $0.hasPrefix("a=ssrc:") }) {
                // format: a=ssrc:<num> msid <streamId> <trackId?>
                let tokens = line.split(separator: " ")
                if let msidIdx = tokens.firstIndex(of: Substring("msid")), msidIdx + 2 < tokens.count {
                    let maybeStream = tokens[msidIdx + 1]
                    let maybeTrack = tokens[msidIdx + 2]
                    return Msid(streamId: String(maybeStream), trackId: String(maybeTrack))
                }
            }

            throw Error.failure
        }
    }
    

    private struct PayloadTypeAllocator
    {
        internal struct Key: Hashable
        {
            let codec: Codec
            let profile: String?
            let clock: Int
            let channels: Int
        }
        internal enum Error : Swift.Error { case exhausted }
        private var next: Int32 = 96
        private var map: [Key: Int32] = [:]

        internal mutating func payloadType(for key: Key) throws -> Int32
        {
            if let pt = map[key] { return pt }
            guard next < 127 else
            {
                throw Error.exhausted
            }
            next += 1
            let pt = next
            map[key] = pt
            return pt
        }
    }
    private var pat = PayloadTypeAllocator()
    private struct SsrcAllocator
    {
        private var used = Set<UInt32>()
        internal mutating func reserve(_ ssrc: UInt32) { used.insert(ssrc) } // call when parsing remote SDP too
        internal mutating func next() -> UInt32
        {
            while true
            {
                let candidate = UInt32.random(in: 1...UInt32.max)
                if !used.contains(candidate) { used.insert(candidate); return candidate }
            }
        }
    }
    private var sa = SsrcAllocator()
    
    /// Create an audio or video track to send and/or receive to the side of this peer connection
    /// After creating a track, remember to lockLocalDescription to start negotiation
    public func createTrack(
        streamId: String, // Group of related medias have the same streamId; e g a webcam feed will have the same streamId for video and audio
        trackId: String,  // ... but different trackIds
        direction: Direction, // on this side, are we sending, receiving, both?
        codec: Codec,
        codecProfile: String? = nil, // applicable to some codecs, e g baseline for h264
        sampleOrBitrate: Int, // sample rate for audio, bitrate for video
        channelCount: Int, // 0 for video, 1 for mono audio, 2 for stereo
        mid: String? = nil, // override if you don't want it to be streamId
        ssrc: UInt32? = nil // override if you don't want to auto-allocate an SSRC for this track
    ) throws -> Track
    {
        guard !streamId.contains(" ") && !trackId.contains(" ") && (mid == nil || !mid!.contains(" ")) else
        {
            fatalError("Invalid stream, track ID or mid: must not contain spaces")
        }
        let mid = mid ?? "\(streamId)"
        let pt = try pat.payloadType(for: PayloadTypeAllocator.Key(codec: codec, profile: codecProfile, clock: sampleOrBitrate, channels: channelCount))
        let actualSsrc: UInt32
        if let ssrc
        {
            sa.reserve(ssrc)
            actualSsrc = ssrc
        }
        else
        {
            actualSsrc = sa.next()
        }
        let name = "t\(actualSsrc)"
        // TODO: Expose setBitrate in rtcTrackInit
        let tid = try Error.orValue(withCStrings([streamId, trackId, mid, codecProfile ?? "", name]) { vals in
            var initData = rtcTrackInit(
                direction: rtcDirection(direction.rawValue),
                codec: rtcCodec(codec.rawValue),
                payloadType: pt,
                ssrc: actualSsrc,
                mid: vals[2],
                name: vals[4],
                msid: vals[0],
                trackId: vals[1],
                profile: codecProfile != nil ? vals[3] : nil
            )
            return rtcAddTrackEx(peerId, &initData)
        })
        if let existing = tracks.first(where: { $0.id == tid })
        {
            return existing
        }
        let track = Track(peer: self, id: tid, streamId: streamId, trackId: trackId)
        self.channels.insert(track)
        self.tracks.insert(track)
        return track
    }
    
    
    // MARK: - Internals
    private func setupCallbacks() throws
    {
        rtcSetUserPointer(peerId, Unmanaged.passUnretained(self).toOpaque())
        
        let _ = try Error.orValue(rtcSetLocalDescriptionCallback(peerId) { _, sdp, type, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            let sdp = this.sanitizeSdp(String(cString: sdp!))
            let type = Description.DescriptionType(rawValue: String(cString: type!))!
            this.localDescription = Description(type: type, sdp: sdp)
        })
        let _ = try Error.orValue(rtcSetLocalCandidateCallback(peerId) { _, candidate, mid, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            let candidate = String(cString: candidate!)
            let mid = String(cString: mid!)
            
            let fixedCandidate = this.sanitizeSdp(candidate)
            
            this.candidates.append(ICECandidate(candidate: fixedCandidate, mid: mid))
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
        let _ = try Error.orValue(rtcSetDataChannelCallback(peerId) { _, dcid, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            if !this.channels.contains(where: { $0.id == dcid })
            {
                let chan = DataChannel(peer: this, id: dcid)
                this.channels.insert(chan)
                this.dataChannels.insert(chan)
            }
        })
        let _ = try Error.orValue(rtcSetTrackCallback(peerId) { _, dcid, ptr  in
            let this = Unmanaged<AlloWebRTCPeer>.fromOpaque(ptr!).takeUnretainedValue()
            if !this.channels.contains(where: { $0.id == dcid })
            {
                let msid = try! Track.GetMsid(dcid)
                let track = Track(peer: this, id: dcid, streamId: msid.streamId, trackId: msid.trackId)
                this.channels.insert(track)
                this.tracks.insert(track)
                for ssrc in track.ssrcs
                {
                    this.sa.reserve(ssrc)
                }
            }
        })
    }
    
    private func sanitizeSdp(_ sdp: String) -> String
    {
        guard let ipOverride else { return sdp }
        
        return sdp.replacingOccurrences(of: ipOverride.from, with: ipOverride.to)
    }
}


public func RtpHeaderRewriteSSRC(in data: inout Data, to ssrc: UInt32)
{
    // RTP header is at least 12 bytes; bail fast if too small
    guard data.count >= 12 else { return }
    data.withUnsafeMutableBytes
    { rawBuf in
        guard let base = rawBuf.baseAddress else { return }
        RTPHeaderRewriteSSRC(base, UInt32(rawBuf.count), ssrc)
    }
}
public func RtpHeaderRewritePayloadType(in data: inout Data, to payloadType: UInt8)
{
    // RTP header is at least 12 bytes; bail fast if too small
    guard data.count >= 12 else { return }
    data.withUnsafeMutableBytes
    { rawBuf in
        guard let base = rawBuf.baseAddress else { return }
        RTPHeaderRewritePayloadType(base, UInt32(rawBuf.count), payloadType)
    }
}

public func LibdatachannelVersion() -> String
{
    return String(cString: GetLibdatachannelVersion()!)
}
