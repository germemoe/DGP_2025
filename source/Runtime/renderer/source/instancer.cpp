//
// Copyright 2016 Pixar
//
// Licensed under the Apache License, Version 2.0 (the "Apache License")
// with the following modification; you may not use this file except in
// compliance with the Apache License and the following modification to it:
// Section 6. Trademarks. is deleted and replaced with:
//
// 6. Trademarks. This License does not grant permission to use the trade
//    names, trademarks, service marks, or product names of the Licensor
//    and its affiliates, except as required to comply with Section 4(c) of
//    the License and to reproduce the content of the NOTICE file.
//
// You may obtain a copy of the Apache License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the Apache License with the above modification is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the Apache License for the specific
// language governing permissions and limitations under the Apache License.
//
#include "instancer.h"

#include "pxr/base/gf/matrix4d.h"
#include "pxr/base/gf/quaternion.h"
#include "pxr/base/gf/rotation.h"
#include "pxr/base/gf/vec3f.h"
#include "pxr/base/gf/vec4f.h"
#include "pxr/base/tf/staticTokens.h"
#include "pxr/imaging/hd/sceneDelegate.h"
#include "pxr/imaging/hd/tokens.h"
#include "sampler.h"

USTC_CG_NAMESPACE_OPEN_SCOPE
using namespace pxr;

Hd_USTC_CG_Instancer::Hd_USTC_CG_Instancer(HdSceneDelegate* delegate, SdfPath const& id)
    : HdInstancer(delegate, id)
{
}

Hd_USTC_CG_Instancer::~Hd_USTC_CG_Instancer()
{
    TF_FOR_ALL(it, _primvarMap)
    {
        delete it->second;
    }
    _primvarMap.clear();
}

void Hd_USTC_CG_Instancer::Sync(
    HdSceneDelegate* delegate,
    HdRenderParam* renderParam,
    HdDirtyBits* dirtyBits)
{
    _UpdateInstancer(delegate, dirtyBits);

    if (HdChangeTracker::IsAnyPrimvarDirty(*dirtyBits, GetId())) {
        _SyncPrimvars(delegate, *dirtyBits);
    }
}

void Hd_USTC_CG_Instancer::_SyncPrimvars(HdSceneDelegate* delegate, HdDirtyBits dirtyBits)
{
    HD_TRACE_FUNCTION();
    HF_MALLOC_TAG_FUNCTION();

    SdfPath const& id = GetId();

    HdPrimvarDescriptorVector primvars =
        delegate->GetPrimvarDescriptors(id, HdInterpolationInstance);

    for (HdPrimvarDescriptor const& pv : primvars) {
        if (HdChangeTracker::IsPrimvarDirty(dirtyBits, id, pv.name)) {
            VtValue value = delegate->Get(id, pv.name);
            if (!value.IsEmpty()) {
                if (_primvarMap.count(pv.name) > 0) {
                    delete _primvarMap[pv.name];
                }
                _primvarMap[pv.name] = new HdVtBufferSource(pv.name, value);
            }
        }
    }
}

VtMatrix4dArray Hd_USTC_CG_Instancer::ComputeInstanceTransforms(
    SdfPath const& prototypeId)
{
    HD_TRACE_FUNCTION();
    HF_MALLOC_TAG_FUNCTION();

    // The transforms for this level of instancer are computed by:
    // foreach(index : indices) {
    //     instancerTransform
    //     * hydra:instanceTranslations(index)
    //     * hydra:instanceRotations(index)
    //     * hydra:instanceScales(index)
    //     * hydra:instanceTransforms(index)
    // }
    // If any transform isn't provided, it's assumed to be the identity.

    GfMatrix4d instancerTransform = GetDelegate()->GetInstancerTransform(GetId());
    VtIntArray instanceIndices = GetDelegate()->GetInstanceIndices(GetId(), prototypeId);

    VtMatrix4dArray transforms(instanceIndices.size());
    for (size_t i = 0; i < instanceIndices.size(); ++i) {
        transforms[i] = instancerTransform;
    }

    // "hydra:instanceTranslations" holds a translation vector for each index.
    if (_primvarMap.count(HdInstancerTokens->instanceTranslations) > 0) {
        Hd_USTC_CGBufferSampler sampler(
            *_primvarMap[HdInstancerTokens->instanceTranslations]);
        for (size_t i = 0; i < instanceIndices.size(); ++i) {
            GfVec3f translate;
            if (sampler.Sample(instanceIndices[i], &translate)) {
                GfMatrix4d translateMat(1);
                translateMat.SetTranslate(GfVec3d(translate));
                transforms[i] = translateMat * transforms[i];
            }
        }
    }

    // "hydra:instanceRotations" holds a quaternion in <real, i, j, k>
    // format for each index.
    if (_primvarMap.count(HdInstancerTokens->instanceRotations) > 0) {
        Hd_USTC_CGBufferSampler sampler(
            *_primvarMap[HdInstancerTokens->instanceRotations]);
        for (size_t i = 0; i < instanceIndices.size(); ++i) {
            GfVec4f quat;
            if (sampler.Sample(instanceIndices[i], &quat)) {
                GfMatrix4d rotateMat(1);
                rotateMat.SetRotate(GfQuatd(quat[0], quat[1], quat[2], quat[3]));
                transforms[i] = rotateMat * transforms[i];
            }
        }
    }

    // "hydra:instanceScales" holds an axis-aligned scale vector for each index.
    if (_primvarMap.count(HdInstancerTokens->instanceScales) > 0) {
        Hd_USTC_CGBufferSampler sampler(*_primvarMap[HdInstancerTokens->instanceScales]);
        for (size_t i = 0; i < instanceIndices.size(); ++i) {
            GfVec3f scale;
            if (sampler.Sample(instanceIndices[i], &scale)) {
                GfMatrix4d scaleMat(1);
                scaleMat.SetScale(GfVec3d(scale));
                transforms[i] = scaleMat * transforms[i];
            }
        }
    }

    // "hydra:instanceTransforms" holds a 4x4 transform matrix for each index.
    if (_primvarMap.count(HdInstancerTokens->instanceTransforms) > 0) {
        Hd_USTC_CGBufferSampler sampler(
            *_primvarMap[HdInstancerTokens->instanceTransforms]);
        for (size_t i = 0; i < instanceIndices.size(); ++i) {
            GfMatrix4d instanceTransform;
            if (sampler.Sample(instanceIndices[i], &instanceTransform)) {
                transforms[i] = instanceTransform * transforms[i];
            }
        }
    }

    if (GetParentId().IsEmpty()) {
        return transforms;
    }

    HdInstancer* parentInstancer =
        GetDelegate()->GetRenderIndex().GetInstancer(GetParentId());
    if (!TF_VERIFY(parentInstancer)) {
        return transforms;
    }

    // The transforms taking nesting into account are computed by:
    // parentTransforms = parentInstancer->ComputeInstanceTransforms(GetId())
    // foreach (parentXf : parentTransforms, xf : transforms) {
    //     parentXf * xf
    // }
    VtMatrix4dArray parentTransforms = static_cast<Hd_USTC_CG_Instancer*>(parentInstancer)
                                           ->ComputeInstanceTransforms(GetId());

    VtMatrix4dArray final(parentTransforms.size() * transforms.size());
    for (size_t i = 0; i < parentTransforms.size(); ++i) {
        for (size_t j = 0; j < transforms.size(); ++j) {
            final[i * transforms.size() + j] = transforms[j] * parentTransforms[i];
        }
    }
    return final;
}
USTC_CG_NAMESPACE_CLOSE_SCOPE
