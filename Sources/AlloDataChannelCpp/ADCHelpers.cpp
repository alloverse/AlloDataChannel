//
//  ADCHelpers.cpp
//  AlloDataChannel
//
//  Created by Nevyn Bengtsson on 2025-08-25.
//

#include "ADCHelpers.h"
#include <rtc/rtc.hpp>

void RTPHeaderRewriteSSRC(void *message, uint32_t length, uint32_t targetSSRC)
{
    auto rtp = reinterpret_cast<rtc::RtpHeader *>(message);
    rtp->setSsrc(targetSSRC);
}

void RTPHeaderRewritePayloadType(void *message, uint32_t length, uint8_t targetPT)
{
    auto rtp = reinterpret_cast<rtc::RtpHeader *>(message);
    rtp->setPayloadType(targetPT);
}
