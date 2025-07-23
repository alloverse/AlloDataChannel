# AlloDataChannel

AlloDataChannel is a Swift WebRTC library based on [libdatachannel](https://github.com/paullouisageneau/libdatachannel) 
rather than [Google's WebRTC](https://webrtc.googlesource.com/src/+/refs/heads/main/docs/native-code), 
the only other option in Swift land.

The reason for this library to exist is to be able to write server side WebRTC applications in Swift, 
which Google's framework is not capable of†. It is primarily used by allonet2 to build Alloverse apps in Swift.

†: Google's WebRTC assumes that any outgoing media stream is meant to come from a capture device. It also cannot 
   access raw stream data, so it is not possible to implement an SFU with it. (The underlying C++ library is capable 
   of it, but it is not exposed through the ObjC layer. I attempted to add it, but the code base is very difficult 
   to work with due to its size and complexity, so it was easier to build it from scratch.)

## Overview

This package provides a minimal Swift wrapper around libdatachannel, specifically designed for server-side use. 
It excludes audio/video capture capabilities to avoid platform-specific dependencies like microphone access.

It contains pre-built binaries of libdatachannel so that you don't have to build them yourself. They are however 
stored in Git LFS, so make sure to have that installed before cloning this repo.

This repo's submodules are only needed to rebuild the libdatachannel binaries. If you are using the binary 
distribution as is, you can skip submodule update after cloning.

## Status

- [x] Mac support
- [ ] Linux support
- [x] Functional
- [ ] Well tested


## Building the C/C++ parts

The wrapper parts can be built with a regular `swift build`. If you want to compile all of libdatachannel 
(E g to add another platform), use the following steps.

### Prerequisites

* CMake 3.13 or newer
* Docker Desktop

### Build

On an Apple Silicon Mac, from root of repo:

1. `git submodule init --update --recursive`
2. `bash Scripts/build-libdatachannel.sh`

This will build both Mac and Linux binaries, and package as xcframework.

## Usage

WebRTC is peer to peer, so there isn't quite a server and client role. However, it is common to have one side initiate with an offer, and the other side to answer. Both the offer and the answer are "just" a description of streams available ("SDP") and a list of possible connection routes to reach those streams ("ICE candidates").

```swift
import AlloDataChannel

func offerer(signalling) async throws
{
    // Create and configure a peer to represent the offerer side, and then lock configuration.
    let peer = AlloWebRTCPeer()
    let datachannel = try peer.createDataChannel(label: "test", streamId: 1, negotiated: true)
    try peer.lockLocalDescription(type: .offer)
    
    // Wait for ICE gathering to finish so we have all connection options available, and then send off an offer to the answerer side (over websockets or some other signalling transport)
    try await peer.$gatheringState.waitFor(value: .complete)
    let offer = try peer.createOffer()
    signalling.sendOffer(offer)
    
    // Receive answer and use it to try to establish a connection to the other peer
    let answer = await signalling.receiveAnswer()
    try peer.set(remote: answer, type: .answer)
    
    // Once we're connected, send off a test message over the newly established data channel!
    try await peer.$state.waitFor(value: .connected)
    try await datachannel.$open.waitFor(value: true)

    let message = "Test".data(using: .utf8)!
    try datachannel.send(data: message)
}

func answerer(signalling) async throws
{
    // For the other side, set up a configured peer as well
    let peer = AlloWebRTCPeer()
    let datachannel = try peer.createDataChannel(label: "test", streamId: 1, negotiated: true)
    
    // On this side though, first receive the offer, and then use that to generate an answer
    let offer = await signalling.receiveOffer()
    try peer.set(remote: offer, type: .offer)
    try peer.lockLocalDescription(type: .answer)
    
    // Send off the answer
    try await peer.$gatheringState.waitFor(value: .complete)
    let answer = try peer.createAnswer()
    signalling.sendAnswer(answer)
    
    // .. and soon, you should be connected
    try await peer.$state.waitFor(value: .connected)
    try await datachannel.$open.waitFor(value: true)
    
    // Now you can just wait for the incoming message
    let iter = datachannel.$lastMessage.values.makeAsyncIterator()
    let message = try await iter.next()
    print("Received: \(message)")
}

```

## Integration

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/alloverse/AlloDataChannel")
```

Then depend on it:

```swift
.target(
    name: "YourTarget",
    dependencies: ["AlloDataChannel"]
)
```
