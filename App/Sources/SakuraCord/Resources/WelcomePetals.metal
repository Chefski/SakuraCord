#include <metal_stdlib>
using namespace metal;

struct SakuraPetal {
    float4 placement;
    float4 variation;
};

struct SakuraPetalUniforms {
    float4 viewport; // point size, progress, wordmark scale
    float4 atlas; // mask point size, tile size, dark appearance
    float4 first;
    float4 last;
    float4 ink;
};

struct SakuraPetalVertex {
    float4 position [[position]];
    float2 local;
    float2 maskUV;
    float4 material; // fusion, face lighting, color variation, opacity
};

float2 sakuraRotate(float2 point, float angle) {
    float sine = sin(angle), cosine = cos(angle);
    return float2(cosine * point.x - sine * point.y, sine * point.x + cosine * point.y);
}

vertex SakuraPetalVertex sakuraPetalVertex(
    uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
    const device SakuraPetal *petals [[buffer(0)]],
    constant SakuraPetalUniforms &uniforms [[buffer(1)]]
) {
    const float2 corners[] = {float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)};
    SakuraPetal petal = petals[instanceID];
    float2 local = corners[vertexID];
    float progress = uniforms.viewport.z;
    float4 variation = petal.variation;
    float phase = variation.y * 6.2831853;
    float delay = variation.x * 0.09;
    float travel = smoothstep(0.08 + delay, 0.66 + delay, progress);
    float remaining = 1.0 - travel;
    float fusion = smoothstep(0.64 + delay * 0.45, 0.97, progress);
    float scale = uniforms.viewport.w;
    float2 center = uniforms.viewport.xy * 0.5;
    float2 target = (petal.placement.xy - uniforms.atlas.xy * 0.5) * scale;

    // A disk larger than the window diagonal has no visible rectangular
    // boundary. Offscreen petals spiral into view with the rest of the field.
    float azimuth = petal.placement.z * 6.2831853;
    float radius = sqrt(petal.placement.w) * length(uniforms.viewport.xy) * 0.60;
    float2 scatter = float2(cos(azimuth), sin(azimuth)) * radius;
    scatter = sakuraRotate(scatter, travel * (3.4 + variation.z));
    float flutter = sin(progress * 8.0 + phase) - sin(phase);
    float2 drift = float2(flutter * 20.0, sin(progress * 6.0 + phase) * 14.0) * remaining;
    float2 position = center + mix(scatter, target, travel) + drift;
    // Advance through complete turns instead of reversing the spin to align
    // with the text. All petals end flat before their tiles close together.
    float turns = 2.0 + floor(variation.z * 2.0);
    float spin = smoothstep(0.02, 0.89, progress);
    float angle = mix(phase, turns * 6.2831853, spin);
    float tilt = mix(0.26 + 0.74 * abs(cos(phase + progress * 18.0)), 1.0, fusion);
    float looseSize = (3.0 + variation.w * 4.5) * max(scale, 0.75);
    float tileSize = uniforms.atlas.z * scale;
    float2 extent = mix(float2(looseSize * tilt, looseSize * 1.35), float2(tileSize * 1.5), smoothstep(0.0, 0.5, fusion));
    extent = mix(extent, float2(tileSize), smoothstep(0.5, 1.0, fusion));
    // Adjacent tiles touch exactly at fusion; the glyph mask supplies all
    // final edge antialiasing instead of a second, crossfaded text layer.
    float2 offset = sakuraRotate(local * extent * 0.5, angle);
    float2 clip = (position + offset) / uniforms.viewport.xy * 2.0 - 1.0;
    SakuraPetalVertex output;
    output.position = float4(clip.x, -clip.y, 0, 1);
    output.local = local;
    output.maskUV = ((position + offset - center) / scale + uniforms.atlas.xy * 0.5) / uniforms.atlas.xy;
    float face = 0.5 + 0.5 * cos(phase + progress * 18.0);
    float opacity = smoothstep(0.0, 0.06 + variation.z * 0.035, progress);
    output.material = float4(fusion, face, variation.w, opacity);
    return output;
}

fragment half4 sakuraPetalFragment(
    SakuraPetalVertex input [[stage_in]],
    constant SakuraPetalUniforms &uniforms [[buffer(1)]],
    texture2d<float> mask [[texture(0)]]
) {
    constexpr sampler maskSampler(coord::normalized, address::clamp_to_zero, filter::linear);
    float2 local = input.local;
    float fusion = input.material.x;
    // A tapered, asymmetric petal with the small cleft of a cherry blossom.
    float width = 0.73 * sqrt(max(0.0, 1.0 - local.y * local.y)) * (1.0 + local.y * 0.24);
    float side = abs(local.x + 0.12 * (1.0 - local.y * local.y)) - width;
    float cleft = local.y - (0.86 + 0.5 * abs(local.x));
    float distance = max(side, cleft);
    float feather = max(fwidth(distance), 0.025);
    float petalAlpha = 1.0 - smoothstep(-feather, feather, distance - fusion * 1.6);
    float glyphAlpha = mask.sample(maskSampler, input.maskUV).r;
    float alpha = petalAlpha * mix(1.0, glyphAlpha, smoothstep(0.28, 0.94, fusion)) * input.material.w;

    float3 tint = mix(uniforms.first.rgb, uniforms.last.rgb, input.material.z * 0.65);
    float dark = uniforms.atlas.w;
    float3 petalColor = mix(tint * 0.76, mix(tint, float3(1), 0.65), input.material.y);
    petalColor = mix(petalColor * 0.76, petalColor, dark);
    float vein = exp(-abs(local.x + local.y * 0.08) * 18.0) * 0.12;
    petalColor += vein * input.material.y;
    float3 color = mix(petalColor, uniforms.ink.rgb, smoothstep(0.02, 1.0, fusion));
    return half4(half3(color * alpha), half(alpha));
}
