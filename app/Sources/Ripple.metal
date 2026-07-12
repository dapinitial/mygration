#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// The iOS 17 NameDrop water-ripple, as a SwiftUI layerEffect distortion.
// A wave radiates from `origin`: pixels within the wavefront are displaced
// along the radial direction and brightened, so whatever is behind ripples
// like a drop hitting a pond. Adapted from Apple's WWDC23 ripple sample.
[[ stitchable ]] half4 Ripple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float time,
    float amplitude,
    float frequency,
    float decay,
    float speed
) {
    float distance = length(position - origin);
    float delay = distance / speed;

    float t = max(0.0, time - delay);
    float rippleAmount = amplitude * sin(frequency * t) * exp(-decay * t);

    float2 n = normalize(position - origin);
    float2 newPosition = position + rippleAmount * n;

    half4 color = layer.sample(newPosition);
    color.rgb += (rippleAmount / amplitude) * color.a * 0.30;   // crest highlight
    return color;
}
