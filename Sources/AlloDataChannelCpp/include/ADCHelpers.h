//
//  ADCHelpers.h
//  AlloDataChannel
//
//  Created by Nevyn Bengtsson on 2025-08-25.
//

#include <stdint.h>

#if __cplusplus
extern "C" {
#endif

/// RTP header contains an SSRC, which is the "unique identifier" for the RTP track. When forwarding packets from another track, you have to rewrite the SSRC to match the outgoing track, rather then using the incoming tracks' existing SSRC.
void RTPHeaderRewriteSSRC(void *message, uint32_t length, uint32_t targetSSRC);


#if __cplusplus
}
#endif
