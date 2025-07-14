# AlloDataChannel

Minimal WebRTC library for Alloverse server-side applications.

## Overview

This package provides a minimal Swift wrapper around libdatachannel, specifically designed for server-side use. It excludes audio/video capture capabilities to avoid platform-specific dependencies like microphone access.

It contains pre-built binaries of libdatachannel so that you don't have to build them yourself.

## Features

- SDP offer/answer handling
- ICE candidate processing  
- Data channel communication
- Media stream forwarding
- Cross-platform support (macOS, Linux for now)

## Building

The wrapper parts can be built with a regular `swift build`. If you want to compile all of libdatachannel (E g to add another platform), use the following steps.

### Prerequisites

...

### Build

...

### Platform Support

Currently supports:

  - macOS ARM64
  - Linux x64

Binaries are stored in `Binaries/` directory and can be committed with Git LFS.

## Usage

```swift
import AlloDataChannel

...
```

## Integration

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/alloverse/AllDataChannel", from: "1.0.0")
```

Then depend on it:

```swift
.target(
    name: "YourTarget",
    dependencies: ["AlloDataChannel"]
)
```
