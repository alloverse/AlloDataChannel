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
    //var track: MediaTrack?
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
        
        /// SETUP INGRESS PEER
        ingressPeer.$state.debugSink("Ingress state", in: &cancellables)
        let dchan = try ingressPeer.createDataChannel(label: "test", streamId: 1, negotiated: true)
        // TODO: Create media track for receiving
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
            receiver.peer.$state.debugSink("Egress[\(receiverIndex)] state", in: &cancellables)
            
            let dchan = try receiver.peer.createDataChannel(label: "test", streamId: 1, negotiated: true)
            // TODO: Create media track for sending
            try receiver.peer.lockLocalDescription(type: .unspecified)
            
            try await receiver.peer.$gatheringState.waitFor(value: .complete)
            let offer = receiver.peer.localDescription!
            let messageString = String(data: try JSONEncoder().encode(offer), encoding: .utf8)!
            print("Please copy this offer and paste it to the next RECEIVER:\n\(messageString)")

            print("\nPlease paste the answer from the RECEIVER:\n")
            let answer = try await stdin.next()!
            let incomingMessage = try JSONDecoder().decode(AlloWebRTCPeer.Description.self, from: answer.data(using: .utf8)!)
            try ingressPeer.set(remote: incomingMessage)
            
            receiverIndex += 1
        }
    }
    
    static func main() async throws
    {
        var app = App()
        try await app.main()
    }
}
