//
//  Shaders.metal
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

#include <metal_stdlib>
#include "MetalStructs.h"
using namespace metal;

struct VertexIn {
    float2 position;
    float alpha;
};

struct VertexOut {
    float4 position [[position]];
    float alpha;
    float2 texCoord;
};


struct Uniforms {
    float4 color;
    bool drawWithTexture;
    float4x4 orthoMatrix;
    float hardness;
    float scale;
    float2 textureOffset;
};

// ---- Vertex shader
vertex VertexOut vertex_main(const device VertexIn* vert [[buffer(0)]],
                             constant Uniforms& uniforms [[buffer(1)]],
                             uint vid [[vertex_id]]) {
    VertexOut out;
    float2 pos = vert[vid].position;
    out.position = uniforms.orthoMatrix * float4(pos, 0, 1);
    out.alpha = vert[vid].alpha;
    out.texCoord =  pos * 0.5 + 0.5; // basic mapping

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    if (uniforms.drawWithTexture) {
        constexpr sampler s(s_address::repeat, t_address::repeat, filter::nearest);
        float2 texSize = float2(tex.get_width(), tex.get_height());
        float2 coord = (in.position.xy + uniforms.textureOffset) / (texSize * uniforms.scale);
        return tex.sample(s, coord);
    } else {
        constexpr sampler s(s_address::repeat, t_address::repeat, filter::linear);
        float4 color = uniforms.color;
        color[3] = pow((in.alpha * 1.2), uniforms.hardness);
        return color;
    }
}
