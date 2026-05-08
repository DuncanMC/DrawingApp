//
//  Shaders.metal
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//

#include <metal_stdlib>
using namespace metal;


struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};


struct Uniforms {
    float4 color;
    bool drawWithTexture;
    float texAspect;
    float4x4 orthoMatrix;
};


vertex VertexOut vertex_main(const device float2* position [[buffer(0)]],
                             constant Uniforms& uniforms [[buffer(1)]],
                             uint vid [[vertex_id]]) {
    VertexOut out;
    float2 pos = position[vid];
    out.position = uniforms.orthoMatrix * float4(pos, 0, 1);


    
    out.texCoord =  pos * 0.5 + 0.5; // basic mapping

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    if (uniforms.drawWithTexture) {
        float2 coord = in.texCoord;
        coord.x /= uniforms.texAspect;
        return tex.sample(s, coord);
    } else {
        return uniforms.color;
    }
}
