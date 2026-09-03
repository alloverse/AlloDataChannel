import Testing
@testable import AlloDataChannel

@Suite struct CodecTests
{
    /// The audio cases start at 128, so a `rawValue <= 128` test calls OPUS video.
    @Test func videoCodecsAreVideoAndAudioCodecsAreNot()
    {
        #expect(AlloWebRTCPeer.Codec.H264.isVideo)
        #expect(AlloWebRTCPeer.Codec.AV1.isVideo)
        #expect(!AlloWebRTCPeer.Codec.OPUS.isVideo)
        #expect(!AlloWebRTCPeer.Codec.G722.isVideo)
    }
}
