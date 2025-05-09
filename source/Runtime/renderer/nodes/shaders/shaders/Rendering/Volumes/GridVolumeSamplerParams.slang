/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#pragma once
#include "utils/HostDeviceShared.slangh"

USTC_CG_NAMESPACE_OPEN_SCOPE

/** Enumeration of available volume transmittance estimators.
*/
enum class TransmittanceEstimator
{
    DeltaTracking,
    RatioTracking,
    RatioTrackingLocalMajorant,  // BrickedGrid only.
};

FALCOR_ENUM_INFO(TransmittanceEstimator, {
    { TransmittanceEstimator::DeltaTracking, "DeltaTracking" },
    { TransmittanceEstimator::RatioTracking, "RatioTracking" },
    { TransmittanceEstimator::RatioTrackingLocalMajorant, "RatioTrackingLocalMajorant" },
});
FALCOR_ENUM_REGISTER(TransmittanceEstimator);

enum class DistanceSampler
{
    DeltaTracking,
    DeltaTrackingLocalMajorant,  // BrickedGrid only.
};

FALCOR_ENUM_INFO(DistanceSampler, {
    { DistanceSampler::DeltaTracking, "DeltaTracking" },
    { DistanceSampler::DeltaTrackingLocalMajorant, "DeltaTrackingLocalMajorant" },
});
FALCOR_ENUM_REGISTER(DistanceSampler);

#ifdef HOST_CODE
inline bool requiresBrickedGrid(DistanceSampler d) { return d == DistanceSampler::DeltaTrackingLocalMajorant; }
inline bool requiresBrickedGrid(TransmittanceEstimator t) { return t == TransmittanceEstimator::RatioTrackingLocalMajorant; }
#endif

USTC_CG_NAMESPACE_CLOSE_SCOPE
