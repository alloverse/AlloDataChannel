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

void ADCRewriteSSRCInRtpHeader(void *message, uint32_t length, uint32_t targetSSRC);


#if __cplusplus
}
#endif
