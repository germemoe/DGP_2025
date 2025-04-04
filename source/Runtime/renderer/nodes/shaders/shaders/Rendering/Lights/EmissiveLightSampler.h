/***************************************************************************
 # Copyright (c) 2015-24, NVIDIA CORPORATION. All rights reserved.
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
#include "EmissiveLightSamplerType.slangh"
#include "Core/Macros.h"
#include "Core/Program/DefineList.h"
#include "Scene/Lights/LightCollection.h"

namespace USTC_CG
{
    class RenderContext;
    struct ShaderVar;

    /** Base class for emissive light sampler implementations.

        All light samplers follows the same interface to make them interchangeable.
        If an unrecoverable error occurs, these functions may throw exceptions.
    */
    class HD_USTC_CG_API EmissiveLightSampler
    {
    public:
        virtual ~EmissiveLightSampler() = default;

        /** Updates the sampler to the current frame.
            \param[in] pRenderContext The render context.
            \param[in] pLightCollection Updated LightCollection
            \return True if the sampler was updated.
        */
        virtual bool update(RenderContext* pRenderContext, ref<ILightCollection> pLightCollection) { return false; }

        /** Return a list of shader defines to use this light sampler.
        *   \return Returns a list of shader defines.
        */
        virtual DefineList getDefines() const;

        /** Bind the light sampler data to a given shader var
        */
        virtual void bindShaderData(const ShaderVar& var) const {}

        /** Returns the type of emissive light sampler.
            \return The type of the derived class.
        */
        EmissiveLightSamplerType getType() const { return mType; }

    protected:
        EmissiveLightSampler(EmissiveLightSamplerType type, ref<ILightCollection> pLightCollection);
        void setLightCollection(ref<ILightCollection> pLightCollection);

        // Internal state
        const EmissiveLightSamplerType mType;       ///< Type of emissive sampler. See EmissiveLightSamplerType.slangh.
        ref<Device> mpDevice;
        ref<ILightCollection> mpLightCollection;
        sigs::Connection mUpdateFlagsConnection;
        ILightCollection::UpdateFlags mLightCollectionUpdateFlags = ILightCollection::UpdateFlags::None;
    };
}
