//
//  SFUmain.swift
//  AlloDataChannel
//
//  Created by Nevyn Bengtsson on 2025-08-21.
//

import Foundation
import AlloDataChannel
import OpenCombineShim

class Receiver
{
    let peer = AlloWebRTCPeer()
    var track: AlloWebRTCPeer.Track! = nil
}

@main
struct App
{
    mutating func main() async throws
    {
        /// SETUP
        //AlloWebRTCPeer.enableLogging(at: .info)
        var stdin = FileHandle.standardInput.bytes.lines.makeAsyncIterator()
        let ingressPeer = AlloWebRTCPeer()
        var receivers: [Receiver] = []
        var cancellables: Set<AnyCancellable> = []
        let trackSsrc: UInt32 = 42
        
        /// SETUP INGRESS PEER
        ingressPeer.$state.debugSink("Ingress state", in: &cancellables)
        let ingressVideo = try ingressPeer.createTrack(streamId: "videostream", trackId: "videotrack", direction: .recvonly, codec: .H264, sampleOrBitrate: 30000, channelCount: 0, ssrc: trackSsrc)
        
        try ingressVideo.installRtcpReceivingSession()
        ingressVideo.$lastMessage.sink
        { message in
            for receiver in receivers
            {
                guard let data = message, receiver.track.isOpen else { return }
                do {
                    // TODO: reinterpret_cast<rtc::RtpHeader *>(message.data())->setSsrc(targetSSRC)
                    try receiver.track?.send(data: data)
                } catch let e
                {
                    print("Failed to forward packet to \(receiver.peer.peerId): \(e)")
                }
            }
        }.store(in: &cancellables)
        
        try ingressPeer.lockLocalDescription(type: .unspecified)
        
        try await ingressPeer.$gatheringState.waitFor(value: .complete)
        let offer = ingressPeer.localDescription!
        let messageString = String(data: try JSONEncoder().encode(offer), encoding: .utf8)!
        print("Please copy this offer and paste it to the SENDER:\n\(messageString)")
        
        print("\nPlease paste the answer from the SENDER:\n")
        let answer = try await stdin.next()!
        
        let incomingMessage = try JSONDecoder().decode(AlloWebRTCPeer.Description.self, from: answer.data(using: .utf8)!)
        try ingressPeer.set(remote: incomingMessage)
        
        /// SETUP EGRESS PEERS
        var receiverIndex = 0
        while(true)
        {
            let receiver = Receiver()
            receivers.append(receiver)
            receiver.peer.$state.debug("Egress[\(receiverIndex)] state").sink()
            {
                if $0 == .connected && ingressVideo.isOpen
                {
                    try! ingressVideo.requestKeyFrame()
                }
            }.store(in: &cancellables)
            
            receiver.track = try receiver.peer.createTrack(streamId: "videostream", trackId: "videotrack", direction: .sendonly, codec: .H264, sampleOrBitrate: 30000, channelCount: 0, ssrc: trackSsrc)
            try receiver.track.installRtcpReceivingSession()
            receiver.track.onKeyFrameRequested = {
                print("Receiver \(receiverIndex) requested keyframe, forwarding request to ingress")
                guard ingressVideo.isOpen else { return }
                try! ingressVideo.requestKeyFrame()
            }
            try receiver.peer.lockLocalDescription(type: .unspecified)
            
            try await receiver.peer.$gatheringState.waitFor(value: .complete)
            let offer = receiver.peer.localDescription!
            let messageString = String(data: try JSONEncoder().encode(offer), encoding: .utf8)!
            print("Please copy this offer and paste it to the next RECEIVER:\n\(messageString)")

            print("\nPlease paste the answer from the RECEIVER:\n")
            let answer = try await stdin.next()!
            let incomingMessage = try JSONDecoder().decode(AlloWebRTCPeer.Description.self, from: answer.data(using: .utf8)!)
            try receiver.peer.set(remote: incomingMessage)
            
            // request keyframe?
            
            receiverIndex += 1
        }
    }
    
    static func main() async throws
    {
        var app = App()
        do {
            try await app.main()
        } catch let e {
            print("Fatal error in main: \(e)")
            throw e
        }
    }
}
