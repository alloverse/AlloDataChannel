# AlloDataChannel

Minimal WebRTC library for Alloverse server-side applications.

## Overview

This package provides a minimal Swift wrapper around libdatachannel, specifically designed for server-side use. It excludes audio/video capture capabilities to avoid platform-specific dependencies like microphone access.

It contains pre-built binaries of libdatachannel so that you don't have to build them yourself. They are however stored in Git LFS, so make sure to have that installed before cloning this repo.

This repo's submodules are only needed to rebuild the libdatachannel binaries. If you are using the binary distribution as is, you can skip submodule update after cloning.

## Features

- SDP offer/answer handling
- ICE candidate processing  
- Data channel communication
- Media stream forwarding
- Cross-platform support (macOS, Linux for now)

## Building

The wrapper parts can be built with a regular `swift build`. If you want to compile all of libdatachannel (E g to add another platform), use the following steps.

### Prerequisites

* CMake 3.13 or newer

### Build

On an Apple Silicon Mac, from root of repo:

1. `git submodule init --update --recursive`
2. `bash Scripts/build-libdatachannel.sh`



## Usage

```swift
import AlloDataChannel

... TBD

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
