#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
    namespace coreimage {
        float4 glitchEffect(sample_t image, float intensity, destination dest) {
            float2 coord = dest.coord();
            float2 offset = float2(sin(coord.y * 0.1 + intensity * 10.0) * 10.0, 0.0);
            float4 color = image.sample(coord + offset * intensity);
            color.r = image.sample(coord + offset * intensity * 1.1).r;
            color.b = image.sample(coord + offset * intensity * 0.9).b;
            return color;
        }
    }
} 