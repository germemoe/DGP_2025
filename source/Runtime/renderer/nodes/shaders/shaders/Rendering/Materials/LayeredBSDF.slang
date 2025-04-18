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
#include "utils/Math/MathConstants.slangh"

__exported import Rendering.Materials.IMaterialInstance;
__exported import Rendering.Materials.IBSDF;
import Rendering.Materials.Fresnel;
import Rendering.Volumes.PhaseFunction;
import Utils.Color.ColorHelpers;
import Utils.Debug.PixelDebug;

/** This class implements a layered material based on
    "Position-Free Monte Carlo Simulation for Arbitrary Layered BSDFs" by Guo et al.

    The model allows for a layerying of two arbitrary BSDFs, where the positive hemisphere
    of the top BSDF is exposed if wi.z>0, and the negative hemisphere of the bottom
    hemisphere is exposed for wi.z<0. The space inbetween the BSDFs can be filled
    with a medium with arbitrary extinction, albedo and mean scattering cosine.
    The thickness of the medium is fixed to be 1.

    Evaluation and sampling are done via a Monte Carlo random walk between the top
    and bottom interface. Hence eval is probabilistic, and the PDF of the sampling
    routine is not known exactly (currently we only return a crude approximation,
    for sampling purposes).
*/
struct LayeredBSDF : IBSDF
{
    IBSDF top;
    IBSDF bottom;
    float sigmaT;
    float g;
    float3 albedo;
    int maxDepth;

    __init(IBSDF top, IBSDF bottom, float sigmaT = 0.0f, float g = 0.0f, float3 albedo = float3(0.0f), int maxDepth = 64)
    {
        this.top = top;
        this.bottom = bottom;
        this.sigmaT = sigmaT;
        this.g = g;
        this.albedo = albedo;
        this.maxDepth = maxDepth;
    }

    BSDFContext initBSDFContext(
        const bool scatterTop,
        const float3 wi,
        const float iors[2],
        const float iorOutside,
    )
    {
        BSDFContext bc;
        if (wi.z >= 0.f)
        {
            if (scatterTop)
            {
                bc.iorI = iorOutside;
                bc.iorT = iors[0];
            }
            else
            {
                bc.iorI = iors[0];
                bc.iorT = iors[1];
            }
        }
        else
        {
            if (scatterTop)
            {
                bc.iorI = iors[0];
                bc.iorT = iorOutside;
            }
            else
            {
                bc.iorI = iors[1];
                bc.iorT = iors[0];
            }
        }

        return bc;
    }

    float3 evalTopOrBottom<S : ISampleGenerator>(bool evalTop, float3 wi, float3 wo, inout S sg, BSDFContext bc)
    {
        if (evalTop)
        {
            return top.eval(wi, wo, sg, bc);
        }
        else
        {
            return bottom.eval(wi, wo, sg, bc);
        }
    }

    bool sampleTopOrBottom<S : ISampleGenerator>(bool sampleTop, float3 wi, out BSDFSample bs, inout S sg, BSDFContext bc)
    {
        if (sampleTop)
        {
            return top.sample(wi, bs.wo, bs.pdf, bs.weight, bs.lobeType, sg, bc);
        }
        else
        {
            return bottom.sample(wi, bs.wo, bs.pdf, bs.weight, bs.lobeType, sg, bc);
        }
    }

    float evalPdfTopOrBottom(bool evalTop, float3 wi, float3 wo, BSDFContext bc)
    {
        if (evalTop)
        {
            return top.evalPdf(wi, wo, bc);
        }
        else
        {
            return bottom.evalPdf(wi, wo, bc);
        }
    }

    float3 eval<S : ISampleGenerator>(const float3 wi, const float3 wo, inout S sg, BSDFContext bc)
    {
        bool enterTop = wi.z > 0.0f;
        bool exitTop = wo.z > 0.0f;

        float3 result = float3(0.0f);
        float z = enterTop ? 1.0f : 0.0f;
        float exitZ = exitTop ? 1.0f : 0.0f;

        float iors[2];
        iors[0] = reflectanceToIOR(top.getIorAsReflectance());
        iors[1] = reflectanceToIOR(bottom.getIorAsReflectance());
        const float iorOutside = bc.iorI;

        BSDFContext bcLocal = BSDFContext(bc.iorI, bc.iorT);

        if (z == exitZ) result += evalTopOrBottom(exitTop, wi, wo, sg, bcLocal);

        BSDFSample bs;
        if (!sampleTopOrBottom(enterTop, wi, bs, sg, bcLocal)) return result;
        if (bs.isLobe(LobeType::Reflection)) return result;

        float3 w = bs.wo;
        float3 weight = bs.weight;
        HenyeyGreensteinPhaseFunction phase = {g};

        for (int depth = 0; depth < maxDepth; ++depth)
        {
            float sigma = sigmaT / abs(w.z);
            if (any(albedo > 0.0f))
            {
                float dz = -log(1.0f - sampleNext1D(sg)) / sigma;
                float zp = w.z > 0.0f ? (z + dz) : (z - dz);
                if (0.0f < zp && zp < 1.0f)
                {
                    float3 phaseW;
                    float phasePDF;
                    float3 phaseWeight;
                    if (!phase.sample(-w, phaseW, phasePDF, phaseWeight, sg)) return false;
                    weight *= albedo * phaseWeight;
                    w = phaseW;
                    z = zp;

                    continue;
                }
                z = clamp(zp, 0.0f, 1.0f);
            }
            else
            {
                z = (z == 1.0f) ? 0.0f : 1.0f;
                weight *= exp(-sigma);
            }
            bool scatterTop = z == 1.0f;

            bcLocal = initBSDFContext(scatterTop, -w, iors, iorOutside);
            if (z == exitZ) result += weight * evalTopOrBottom(exitTop, -w, wo, sg, bcLocal);
            if (!sampleTopOrBottom(scatterTop, -w, bs, sg, bcLocal)) return result;
            weight *= bs.weight;
            w = bs.wo;

            if (bs.isLobe(LobeType::Transmission)) return result;

            float rr = min(luminance(weight), 1.0f);
            if (depth > 3 && rr < 0.25f)
            {
                if (sampleNext1D(sg) >= rr) return false;
                weight /= rr;
            }
        }
        return result;
    }

    bool sample<S : ISampleGenerator>(const float3 wi, out float3 wo, out float pdfOut, out float3 weightOut, out uint lobeType, inout S sg, BSDFContext bc)
    {
        wo = {};
        pdfOut = {};
        weightOut = {};
        lobeType = {};

        bool enterTop = wi.z > 0.0f;

        float iors[2];
        iors[0] = reflectanceToIOR(top.getIorAsReflectance());
        iors[1] = reflectanceToIOR(bottom.getIorAsReflectance());
        const float iorOutside = bc.iorI;

        BSDFContext bcLocal = BSDFContext(bc.iorI, bc.iorT);

        BSDFSample bs;
        if (!sampleTopOrBottom(enterTop, wi, bs, sg, bcLocal)) return false;
        if (bs.isLobe(LobeType::Reflection))
        {
            wo = bs.wo;
            pdfOut = bs.pdf;
            weightOut = bs.weight;
            lobeType = bs.lobeType;
            return true;
        }

        float3 w = bs.wo;
        float3 weight = bs.weight;
        float pdf = bs.pdf;
        float z = enterTop ? 1.0f : 0.0f;
        HenyeyGreensteinPhaseFunction phase = {g};

        for (int depth = 0; depth < maxDepth; ++depth)
        {
            float sigma = sigmaT / abs(w.z);
            if (any(albedo > 0.0f))
            {
                float dz = -log(1.0f - sampleNext1D(sg)) / sigma;
                float zp = w.z > 0.0f ? (z + dz) : (z - dz);
                if (0.0f < zp && zp < 1.0f)
                {
                    float3 phaseW;
                    float phasePDF;
                    float3 phaseWeight;
                    if (!phase.sample(-w, phaseW, phasePDF, phaseWeight, sg)) return false;
                    pdf *= phasePDF;
                    weight *= albedo * phaseWeight;
                    w = phaseW;
                    z = zp;

                    continue;
                }
                z = clamp(zp, 0.0f, 1.0f);
            }
            else
            {
                z = (z == 1.0f) ? 0.0f : 1.0f;
                weight *= exp(-sigma);
            }
            bool scatterTop = z == 1.0f;
            bcLocal = initBSDFContext(scatterTop, -w, iors, iorOutside);
            if (!sampleTopOrBottom(scatterTop, -w, bs, sg, bcLocal)) return false;
            weight *= bs.weight;
            w = bs.wo;
            pdf *= bs.pdf;

            if (bs.isLobe(LobeType::Transmission))
            {
                wo = w;
                pdfOut = evalPdf(wi, w, bc);
                weightOut = weight;
                lobeType =
                    (uint)(w.z*wi.z > 0.0f ? LobeType::Reflection : LobeType::Transmission) &
                    (uint)(bs.isLobe(LobeType::Delta) ? LobeType::Delta : LobeType::Specular);

                return true;
            }

            float rr = min(luminance(weight), 1.0f);
            if (depth > 3 && rr < 0.25f)
            {
                if (sampleNext1D(sg) >= rr) return false;
                weight /= rr;
                pdf *= rr;
            }
        }
        return false;
    }

    /** TODO: This is a relatively crude approximation to the sampling PDF.
        It only evaluates the reflection lobe from the interface facing the ray.
        A better strategy would be to evaluate also the TT/TRT lobes. However, this
        would require transmitting through the closest interface, which we can't
        do without invoking the sampling routine. We don't have sg available here,
        and a stochastic PDF could cause problems with MIS.
    */
    float evalPdf(const float3 wi, const float3 wo, BSDFContext bc)
    {
        bool enterTop = wi.z > 0.0f;
        bool exitTop = wo.z > 0.0f;

        float iors[2];
        iors[0] = reflectanceToIOR(top.getIorAsReflectance());
        iors[1] = reflectanceToIOR(bottom.getIorAsReflectance());
        const float iorOutside = bc.iorI;

        BSDFContext bcLocal = BSDFContext(bc.iorI, bc.iorT);

        float pdfCos = abs(wi.z) * M_1_PI;
        float pdfSingle = 0.0f;
        if (enterTop == exitTop) pdfSingle = evalPdfTopOrBottom(exitTop, wi, wo, bcLocal);

        return lerp(pdfSingle, pdfCos, 0.5f);
    }

    AlbedoContributions evalAlbedo(const float3 wi, const LobeType lobetype)
    {
        // TODO: This would need a closed-form version.
        return AlbedoContributions(1.f, 0.f, 0.f, 0.f);
    }

    float3 getIorAsReflectance()
    {
        return float3(1.f);
    }

    RoughnessInformation getRoughnessInformation(const float3 wi)
    {
        // Return the roughness information for the top or bottom BSDF
        // depending on which we hit first, ignoring transmission for now.
        bool enterTop = wi.z > 0.0f;
        if (enterTop)
            return top.getRoughnessInformation(wi);
        else
            return bottom.getRoughnessInformation(wi);
    }
};
