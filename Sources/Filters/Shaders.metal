#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

#if defined(__METAL_IOS__) || defined(__METAL_TVOS__) || defined(__METAL_WATCHOS__)

using namespace metal;

extern "C" {
    namespace coreimage {
        float4 glitchEffect(sampler src, float intensity, destination dest) {
            float2 coord = dest.coord();
            float2 offset = float2(sin(coord.y * 0.1 + intensity * 10.0) * 10.0, 0.0);
            
            float4 baseColor = src.sample(coord + offset * intensity);
            float4 redSample = src.sample(coord + offset * intensity * 1.1);
            float4 blueSample = src.sample(coord + offset * intensity * 0.9);

            baseColor.r = redSample.r;
            baseColor.b = blueSample.b;
            
            return baseColor;
        }
    }
}

#endif
