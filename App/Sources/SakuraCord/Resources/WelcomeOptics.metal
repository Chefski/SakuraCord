#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A continuous refractive front brings the complete glyphs into focus. All
// sampling offsets and masks are smooth; the settled alpha is the source text.
[[ stitchable ]] half4 sakuraWelcomeWordmark(
    float2 position, SwiftUI::Layer layer, float4 bounds, float progress,
    half4 first, half4 last, half4 ink
) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    float t = progress * 5.2;
    float arrival = smoothstep(0.1, 2.6, t);
    float distance = abs(uv.x - 0.5) * 1.25;
    float focus = smoothstep(distance, distance + 0.38, arrival);
    float refraction = 1.0 - focus;
    float wave = sin(uv.x * 10.0 - t * 1.6 + uv.y * 3.0);
    float2 offset = float2(wave * 16.0, sin(uv.x * 7.0 + t) * 12.0) * refraction;
    float2 samplePosition = position + offset;
    float blur = refraction * 12.0;
    half alpha = layer.sample(samplePosition).a * half(0.4);
    alpha += layer.sample(samplePosition + float2(blur, blur * 0.3)).a * half(0.15);
    alpha += layer.sample(samplePosition - float2(blur, blur * 0.3)).a * half(0.15);
    alpha += layer.sample(samplePosition + float2(blur * 0.45, -blur * 0.45)).a * half(0.15);
    alpha += layer.sample(samplePosition - float2(blur * 0.45, -blur * 0.45)).a * half(0.15);
    alpha *= half(focus);

    half3 tint = mix(first.rgb, last.rgb, half(uv.x));
    half3 color = mix(tint, ink.rgb, half(smoothstep(0.0, 0.9, focus)));
    // A broad satin reflection with a narrow luminous edge travels diagonally
    // over the letters after the reveal, then leaves clean, solid typography.
    float sweepPosition = (t - 2.2) * 0.72;
    float reflection = uv.x + uv.y * 0.24 - sweepPosition;
    float sheen = exp(-reflection * reflection * 70.0);
    float edge = exp(-pow((reflection + 0.09) * 48.0, 2.0));
    float sweepEnvelope = smoothstep(2.1, 2.5, t) * (1.0 - smoothstep(3.8, 4.2, t));
    color = mix(color, mix(tint, half3(1.0), half(0.6)), half(sheen * sweepEnvelope * 0.45));
    color = mix(color, half3(1.0), half(edge * sweepEnvelope * 0.8));
    return half4(color * alpha, alpha);
}
