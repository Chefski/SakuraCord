#include <metal_stdlib>
using namespace metal;

struct SakuraRibbonField {
    half3 light;
    float glow;
    float crests;
};

// Shared geometry keeps the backdrop and loading controls in the same motion
// language: three broad folds with fine crests and no procedural noise field.
static SakuraRibbonField sakuraRibbons(float2 p, float t, half3 first, half3 middle, half3 last, bool softCrests) {
    float warp = sin(p.x * 2.6 + t) * 0.13 + sin(p.x * 4.1 - t * 0.7) * 0.055;
    float y = p.y + warp;
    SakuraRibbonField field = {};
    for (int i = 0; i < 3; ++i) {
        float phase = float(i) * 1.7;
        float ridge = y - (sin(p.x * 1.7 + t + phase) * 0.19 + float(i - 1) * 0.29);
        float veil = exp(-ridge * ridge * 19.0);
        float crest = softCrests
            ? exp(-ridge * ridge * 85.0)
            : exp(-abs(ridge) * 115.0);
        float breathing = 0.72 + 0.18 * sin(p.x * 2.0 - t + phase);
        float strength = (veil * 0.12 + crest * 0.075) * breathing;
        half3 hue = i == 0 ? first : (i == 1 ? middle : last);
        field.light += hue * half(strength);
        field.glow += strength;
        field.crests += crest * breathing;
    }
    return field;
}

// Broad, slowly folding ribbons with fine luminous crests. Analytic waves avoid
// texture allocations and keep the full-window effect to a single color pass.
[[ stitchable ]] half4 sakuraSignInLight(
    float2 position, half4 source, float4 bounds, float time,
    half4 first, half4 middle, half4 last, float dark
) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    float2 p = (uv - 0.5) * float2(bounds.z / max(bounds.w, 1.0), 1.0);
    float t = time * 0.075;
    SakuraRibbonField ribbons = sakuraRibbons(p, t, first.rgb, middle.rgb, last.rgb, false);
    half3 light = ribbons.light;
    float glow = ribbons.glow;
    float edge = smoothstep(0.05, 0.72, length(uv - 0.5));
    half3 color = source.rgb;
    if (dark > 0.5) {
        color += light * half(0.85 + edge * 0.65);
    } else {
        // Pale surfaces need pigmented folds rather than additive light. Keep
        // the same ribbon geometry, with enough depth to expose its crests.
        half3 pigment = light / half(max(glow, 0.001)) * half(0.9);
        half coverage = half(min(glow * (2.8 + edge * 0.7), 0.72));
        color = mix(color, pigment, coverage);
    }
    // Stationary subpixel grain prevents banding without temporal noise.
    float grain = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    color += half(grain / 700.0);
    return half4(color, source.a);
}

// The backdrop's folding ribbons with soft, broad crests and faster movement.
// Width normalization keeps the same flowing folds legible on a shallow button.
[[ stitchable ]] half4 sakuraAuthenticationLoading(
    float2 position, half4 source, float4 bounds, float time,
    half4 first, half4 last, float intensity
) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    float aspect = clamp(bounds.z / max(bounds.w, 1.0), 1.0, 2.2);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    SakuraRibbonField ribbons = sakuraRibbons(
        p, time * 1.25, first.rgb, mix(first.rgb, last.rgb, half(0.5)), last.rgb, true
    );
    half3 hue = ribbons.light / half(max(ribbons.glow, 0.001));
    hue = mix(hue, half3(1.0), half(min(ribbons.crests * 0.45, 0.4)));
    half alpha = source.a * half(min(ribbons.glow * intensity * 1.8, 0.68));
    return half4(hue * alpha, alpha);
}
