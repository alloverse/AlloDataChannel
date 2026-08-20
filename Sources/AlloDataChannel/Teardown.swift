//
//  Teardown.swift
//  AlloDataChannel
//

import Foundation
import datachannel

/// Shuts libdatachannel down while it still exists.
///
/// The C API keeps every peer connection, channel and track in static maps. Anything still in
/// them when `main` returns is destroyed by those maps' own static destructors, and by then the
/// library's other statics are gone: `SctpTransport` writes a shutdown ABORT through a registry
/// of live instances that is itself a static, so it dereferences it after destruction (SIGSEGV at
/// address 0x28, in `SctpTransport::WriteCallback`). Any peer that is still connected at exit —
/// or whose Swift wrapper is merely still retained — hits this.
///
/// `rtcCleanup()` on its own doesn't help: its `eraseAll()` clears the maps while holding their
/// lock, and the destructors it triggers fire callbacks that take that same lock, so it
/// deadlocks. Deleting objects one by one does not, because `rtcDelete*` closes them outside the
/// lock; once the maps are empty, `rtcCleanup()` only has to join the library's threads and
/// finish usrsctp, which is what makes the following static destruction safe.
///
/// Registration is what an app would otherwise have to remember to do by hand at every exit path,
/// GUI apps included, so it's automatic: the handler is installed with the first peer connection.
enum Teardown
{
    private static let lock = NSLock()
    private nonisolated(unsafe) static var peers: Set<Int32> = []
    private nonisolated(unsafe) static var channels: Set<Int32> = []

    static func remember(peer id: Int32)
    {
        lock.withLock {
            _ = installed
            peers.insert(id)
        }
    }
    static func forget(peer id: Int32) { lock.withLock { _ = peers.remove(id) } }
    static func remember(channel id: Int32) { lock.withLock { _ = channels.insert(id) } }
    static func forget(channel id: Int32) { lock.withLock { _ = channels.remove(id) } }

    private static let installed: Void = {
        atexit { Teardown.run() }
    }()

    /// Channels before peers: a channel deleted after its peer is gone has nothing left to reset
    /// its stream over, and would take its closed callback into an already dismantled connection.
    private static func run()
    {
        let (channels, peers) = lock.withLock { (self.channels, self.peers) }
        for id in channels { rtcDelete(id) }
        for id in peers { rtcDeletePeerConnection(id) }
        rtcCleanup()
    }
}
