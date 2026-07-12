#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Full-screen NameDrop wash: an expanding ring of light radiating from `origin`
// across the whole display. colorEffect over a transparent layer — returns glow
// only at the wavefront, clear everywhere else, so it overlays the live desktop.
[[ stitchable ]] half4 ScreenRipple(
    float2 position,
    half4 color,
    float2 size,
    float2 origin,
    float time,
    float duration
) {
    float maxDim = max(size.x, size.y);
    float d = distance(position, origin) / maxDim;   // 0..~1 normalized radius
    float wave = time / duration;                    // wavefront progress 0..1

    float thickness = 0.055;
    float ring  = 1.0 - smoothstep(0.0, thickness, abs(d - wave));
    float trail = (1.0 - smoothstep(0.0, thickness * 5.0, abs(d - wave))) * 0.22;

    float birth = smoothstep(0.0, 0.05, wave);       // ease in
    float death = 1.0 - smoothstep(0.75, 1.0, wave); // fade out
    float intensity = saturate(ring + trail) * birth * death;

    half3 glow = half3(0.62h, 0.82h, 1.0h);          // cool white-blue
    half a = half(intensity) * 0.85h;
    return half4(glow * a, a);                        // premultiplied
}
