#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

#if defined(__METAL_IOS__) || defined(__METAL_TVOS__) || defined(__METAL_WATCHOS__) || defined(__METAL_MACOS__)

using namespace metal;

struct AtlasWriteUniforms {
    uint destX;
    uint destY;
    uint cellWidth;
    uint cellHeight;
};

struct FlowFieldUniforms {
    uint outputWidth;
    uint outputHeight;
    uint cellWidth;
    uint cellHeight;
    uint columns;
    uint rows;
    uint capacity;
    uint frameCount;
    uint frameZeroIndex;
    uint maxFrameOffset;
    float noiseScale;
    float flowSpeed;
    float time;
    float padding;
};

struct HeatmapFrameOffsetUniforms {
    uint outputWidth;
    uint outputHeight;
    uint cellWidth;
    uint cellHeight;
    uint columns;
    uint rows;
    uint capacity;
    uint frameCount;
    uint frameZeroIndex;
    uint maxFrameOffset;
    uint padding0;
    uint padding1;
    uint padding2;
};

struct TemporalFadeAtlasUniforms {
    uint outputWidth;
    uint outputHeight;
    uint cellWidth;
    uint cellHeight;
    uint columns;
    uint rows;
    uint capacity;
    uint frameCountInAtlas;
    uint frameZeroIndex;
    uint blendFrameCount;
    uint frameSpacing;
    uint padding0;
    uint padding1;
};

struct TemporalColorSplitAtlasUniforms {
    uint outputWidth;
    uint outputHeight;
    uint cellWidth;
    uint cellHeight;
    uint columns;
    uint rows;
    uint capacity;
    uint frameCountInAtlas;
    uint frameZeroIndex;
    uint blendFrameCount;
    uint frameSpacing;
    uint componentCount;
    uint padding0;
};

struct JFASplatUniforms {
    uint particleCount;
    uint padding0;
    uint padding1;
    uint padding2;
};

struct JFAJumpUniforms {
    uint width;
    uint height;
    uint step;
    uint padding;
};

struct JFAResolveUniforms {
    uint width;
    uint height;
    float blend;
    float edgeIntensity;
    float colorVariation;
    float padding;
};

inline float2 perlinFade2(float2 t) {
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453123f);
}

inline float2 perlinGrad2(float2 cell) {
    float angle = hash21(cell) * 6.283185307f;
    return float2(cos(angle), sin(angle));
}

inline float perlin2d(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    float2 g00 = perlinGrad2(i + float2(0.0f, 0.0f));
    float2 g10 = perlinGrad2(i + float2(1.0f, 0.0f));
    float2 g01 = perlinGrad2(i + float2(0.0f, 1.0f));
    float2 g11 = perlinGrad2(i + float2(1.0f, 1.0f));

    float n00 = dot(g00, f - float2(0.0f, 0.0f));
    float n10 = dot(g10, f - float2(1.0f, 0.0f));
    float n01 = dot(g01, f - float2(0.0f, 1.0f));
    float n11 = dot(g11, f - float2(1.0f, 1.0f));

    float2 u = perlinFade2(f);
    float nx0 = mix(n00, n10, u.x);
    float nx1 = mix(n01, n11, u.x);
    return mix(nx0, nx1, u.y);
}

inline float fbm2d(float2 p) {
    float sum = 0.0f;
    float amplitude = 0.5f;
    float amplitudeSum = 0.0f;
    float2 point = p;

    for (uint octave = 0; octave < 4; octave++) {
        sum += perlin2d(point) * amplitude;
        amplitudeSum += amplitude;
        point *= 2.0f;
        amplitude *= 0.5f;
    }

    return amplitudeSum > 0.0f ? (sum / amplitudeSum) : 0.0f;
}

inline float jfaHash11(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453123f);
}

inline float3 hsvToRgb(float3 hsv) {
    float3 rgb = clamp(abs(fmod(hsv.x * 6.0f + float3(0.0f, 4.0f, 2.0f), 6.0f) - 3.0f) - 1.0f, 0.0f, 1.0f);
    rgb = rgb * rgb * (3.0f - 2.0f * rgb);
    return hsv.z * mix(float3(1.0f), rgb, hsv.y);
}

inline float3 jfaSeedTint(float2 seedUV) {
    float r = jfaHash11(seedUV + float2(0.0f, 1.3f));
    float g = jfaHash11(seedUV + float2(4.7f, 2.1f));
    float b = jfaHash11(seedUV + float2(9.2f, 7.9f));
    return 0.82f + 0.36f * float3(r, g, b);
}

extern "C" {
    namespace coreimage {
        inline float2 voronoiHash22(float2 p) {
            float x = sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453123f;
            float y = sin(dot(p, float2(269.5f, 183.3f))) * 43758.5453123f;
            return fract(float2(x, y));
        }

        float4 voronoiEffect(
            sampler src,
            float cellSize,
            float jitter,
            float intensity,
            float edgeWidth,
            float edgeIntensity,
            float colorVariation,
            float driftSpeed,
            float time,
            destination dest
        ) {
            float2 coord = dest.coord();
            float safeCellSize = max(cellSize, 1.0f);

            float2 p = coord / safeCellSize;
            float2 cell = floor(p);

            float nearest = 1e9f;
            float secondNearest = 1e9f;
            float2 bestSeed = p;

            float jitterAmount = clamp(jitter, 0.0f, 1.0f);
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    float2 neighbor = float2(float(x), float(y));
                    float2 cellID = cell + neighbor;
                    float2 random = voronoiHash22(cellID);
                    float driftPhase = dot(cellID, float2(0.37f, 0.79f)) * 6.283185307f + time * driftSpeed;
                    float2 drift = float2(cos(driftPhase), sin(driftPhase)) * 0.35f;
                    float2 offset = 0.5f + ((random - 0.5f) + drift) * jitterAmount;
                    float2 seed = cell + neighbor + offset;
                    float2 delta = seed - p;
                    float distanceSquared = dot(delta, delta);

                    if (distanceSquared < nearest) {
                        secondNearest = nearest;
                        nearest = distanceSquared;
                        bestSeed = seed;
                    } else if (distanceSquared < secondNearest) {
                        secondNearest = distanceSquared;
                    }
                }
            }

            float2 sampleCoord = bestSeed * safeCellSize;

            float4 sourceColor = src.sample(src.transform(coord));
            float4 voronoiColor = src.sample(src.transform(sampleCoord));

            // Per-cell color variation.
            float2 tintHash = voronoiHash22(floor(bestSeed));
            float3 tint = 0.82f + 0.36f * float3(tintHash.x, tintHash.y, 1.0f - tintHash.x * 0.7f);
            float tintAmount = clamp(colorVariation, 0.0f, 1.0f);
            voronoiColor.rgb = mix(voronoiColor.rgb, voronoiColor.rgb * tint, tintAmount);

            // F2-F1 edge shaping for distinct Voronoi boundaries.
            float borderMetric = max(secondNearest - nearest, 0.0f);
            float safeEdgeWidth = max(0.001f, edgeWidth);
            float border = 1.0f - smoothstep(0.0f, safeEdgeWidth, borderMetric);
            border = pow(clamp(border, 0.0f, 1.0f), 0.65f);
            float borderAmount = clamp(edgeIntensity, 0.0f, 1.0f);
            voronoiColor.rgb *= (1.0f - border * borderAmount);

            float blend = clamp(intensity, 0.0f, 1.0f);
            return mix(sourceColor, voronoiColor, blend);
        }

        inline void kuwaharaRegionStats(
            sampler src,
            float2 centerCoord,
            int xStart,
            int xEnd,
            int yStart,
            int yEnd,
            thread float3& meanOut,
            thread float& varianceOut
        ) {
            float3 sum = float3(0.0f);
            float3 sumSquared = float3(0.0f);
            float count = 0.0f;

            for (int y = yStart; y <= yEnd; y++) {
                for (int x = xStart; x <= xEnd; x++) {
                    float2 sampleCoord = centerCoord + float2(float(x), float(y));
                    float3 color = src.sample(src.transform(sampleCoord)).rgb;
                    sum += color;
                    sumSquared += color * color;
                    count += 1.0f;
                }
            }

            float invCount = count > 0.0f ? (1.0f / count) : 0.0f;
            meanOut = sum * invCount;
            float3 varianceRGB = max(sumSquared * invCount - meanOut * meanOut, float3(0.0f));
            varianceOut = varianceRGB.r + varianceRGB.g + varianceRGB.b;
        }

        float4 kuwaharaEffect(sampler src, float radius, float intensity, destination dest) {
            float2 coord = dest.coord();
            float4 sourceColor = src.sample(src.transform(coord));

            int radiusInt = int(floor(clamp(radius, 1.0f, 24.0f) + 0.5f));
            radiusInt = max(1, radiusInt);

            float3 mean0;
            float3 mean1;
            float3 mean2;
            float3 mean3;
            float variance0;
            float variance1;
            float variance2;
            float variance3;

            // Four overlapping quadrants around the current pixel.
            kuwaharaRegionStats(
                src,
                coord,
                -radiusInt,
                0,
                -radiusInt,
                0,
                mean0,
                variance0
            );
            kuwaharaRegionStats(
                src,
                coord,
                0,
                radiusInt,
                -radiusInt,
                0,
                mean1,
                variance1
            );
            kuwaharaRegionStats(
                src,
                coord,
                -radiusInt,
                0,
                0,
                radiusInt,
                mean2,
                variance2
            );
            kuwaharaRegionStats(
                src,
                coord,
                0,
                radiusInt,
                0,
                radiusInt,
                mean3,
                variance3
            );

            float3 bestMean = mean0;
            float bestVariance = variance0;
            if (variance1 < bestVariance) {
                bestVariance = variance1;
                bestMean = mean1;
            }
            if (variance2 < bestVariance) {
                bestVariance = variance2;
                bestMean = mean2;
            }
            if (variance3 < bestVariance) {
                bestMean = mean3;
            }

            float blend = clamp(intensity, 0.0f, 1.0f);
            float3 outputRGB = mix(sourceColor.rgb, bestMean, blend);
            return float4(outputRGB, sourceColor.a);
        }

        float4 glitchEffect(sampler src, float intensity, float time, destination dest) {
            float2 coord = dest.coord();
            float glitchAmount = clamp(intensity, 0.0f, 10.0f);
            float t = time * (1.2f + glitchAmount * 0.35f);

            float bandHeight = max(4.0f, 18.0f - glitchAmount);
            float bandIndex = floor(coord.y / bandHeight);
            float coarsePhase = floor(t * (5.0f + glitchAmount * 1.8f));
            float bandNoise = hash21(float2(bandIndex, coarsePhase));
            float tearMask = step(0.42f, bandNoise);

            float sineDrift = sin(coord.y * 0.045f + t * 11.0f) * (2.0f + glitchAmount * 1.8f);
            float rowTear = (bandNoise - 0.5f) * (18.0f + glitchAmount * 7.0f) * tearMask;

            float blockWidth = 14.0f + glitchAmount * 3.5f;
            float blockIndex = floor((coord.x + rowTear) / blockWidth);
            float blockNoise = hash21(float2(blockIndex + coarsePhase * 0.17f, bandIndex * 1.31f));
            float blockJitter = (blockNoise - 0.5f) * (8.0f + glitchAmount * 5.0f) * tearMask;

            float2 baseCoord = coord + float2(sineDrift + rowTear + blockJitter, 0.0f);

            float channelSplit = (1.5f + glitchAmount * 2.6f) * (0.55f + 0.45f * tearMask);
            float verticalJitter = (hash21(float2(bandIndex * 0.37f, coarsePhase * 0.73f)) - 0.5f) * (1.0f + glitchAmount * 0.9f);

            float2 redCoord = baseCoord + float2(channelSplit * 1.25f, verticalJitter);
            float2 greenCoord = baseCoord + float2((blockNoise - 0.5f) * channelSplit * 0.55f, -verticalJitter * 0.4f);
            float2 blueCoord = baseCoord - float2(channelSplit, verticalJitter * 1.1f);

            float4 baseSample = src.sample(src.transform(baseCoord));
            float4 redSample = src.sample(src.transform(redCoord));
            float4 greenSample = src.sample(src.transform(greenCoord));
            float4 blueSample = src.sample(src.transform(blueCoord));

            float3 splitRGB = float3(redSample.r, greenSample.g, blueSample.b);
            float splitMix = clamp(0.45f + glitchAmount * 0.08f, 0.0f, 1.0f);
            float3 rgb = mix(baseSample.rgb, splitRGB, splitMix);

            float dropoutBand = hash21(float2(floor(coord.y / (10.0f + glitchAmount * 2.0f)), floor(t * 9.0f)));
            float dropoutAmount = step(0.84f - glitchAmount * 0.025f, dropoutBand) * (0.18f + 0.62f * hash21(float2(bandIndex + 9.1f, coarsePhase + 3.7f)));
            float scanline = 0.92f + 0.08f * sin(coord.y * 1.7f + t * 22.0f);
            float whiteNoise = hash21(coord * 0.17f + float2(t * 2.3f, -t * 1.7f)) - 0.5f;

            rgb += whiteNoise * (0.03f + glitchAmount * 0.01f);
            rgb *= scanline;
            rgb *= 1.0f - dropoutAmount;

            float flashSwap = step(0.965f, hash21(float2(coarsePhase, bandIndex * 0.19f)));
            if (flashSwap > 0.0f) {
                rgb = rgb.bgr;
            }

            rgb = clamp(rgb, 0.0f, 1.0f);
            return float4(rgb, baseSample.a);
        }

        float4 mirrorEffect(
            sampler src,
            float2 point,
            float angle,
            float keepSign,
            destination dest
        ) {
            float2 coord = dest.coord();
            float sine = sin(angle);
            float cosine = cos(angle);
            float2 normal = float2(-sine, cosine);
            float preservedSide = keepSign < 0.0f ? -1.0f : 1.0f;
            float signedDistance = dot(coord - point, normal);

            float2 sampleCoord = coord;
            if (signedDistance * preservedSide < 0.0f) {
                sampleCoord = coord - (2.0f * signedDistance * normal);
            }

            return src.sample(src.transform(sampleCoord));
        }
    }
}

kernel void atlasWriteKernel(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture2d<float, access::write> atlasTexture [[texture(1)]],
    constant AtlasWriteUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.cellWidth || gid.y >= uniforms.cellHeight) {
        return;
    }

    float4 color = sourceTexture.read(gid);
    uint2 destCoord = uint2(uniforms.destX + gid.x, uniforms.destY + gid.y);
    atlasTexture.write(color, destCoord);
}

kernel void perlinFlowFieldAtlasKernel(
    texture2d<float, access::read> atlasTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant FlowFieldUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.outputWidth || gid.y >= uniforms.outputHeight) {
        return;
    }

    if (uniforms.frameCount == 0 || uniforms.columns == 0 || uniforms.rows == 0) {
        outputTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
        return;
    }

    float2 outSize = float2(float(uniforms.outputWidth), float(uniforms.outputHeight));
    float2 uv = (float2(gid) + 0.5f) / outSize;

    float2 flow = float2(uniforms.time * uniforms.flowSpeed, uniforms.time * uniforms.flowSpeed * 0.73f);
    float noise = fbm2d(uv * uniforms.noiseScale + flow);
    float normalized = clamp(noise * 0.5f + 0.5f, 0.0f, 1.0f);
    float biased = normalized * normalized;

    uint availableMax = uniforms.frameCount > 0 ? uniforms.frameCount - 1 : 0;
    uint clampedMaxOffset = min(uniforms.maxFrameOffset, availableMax);
    float offsetFloat = biased * float(clampedMaxOffset);
    uint offsetLow = uint(floor(offsetFloat));
    uint offsetHigh = min(offsetLow + 1, clampedMaxOffset);
    float offsetBlend = fract(offsetFloat);

    uint wrappedLow = uniforms.capacity > 0 ? (offsetLow % uniforms.capacity) : 0;
    uint absoluteIndexLow = (uniforms.frameZeroIndex + uniforms.capacity - wrappedLow) % uniforms.capacity;
    uint colLow = absoluteIndexLow % uniforms.columns;
    uint rowLow = absoluteIndexLow / uniforms.columns;

    uint cellX = min(uint(floor(uv.x * float(uniforms.cellWidth))), uniforms.cellWidth - 1);
    uint cellY = min(uint(floor(uv.y * float(uniforms.cellHeight))), uniforms.cellHeight - 1);

    uint atlasXLow = colLow * uniforms.cellWidth + cellX;
    uint atlasYLow = rowLow * uniforms.cellHeight + cellY;
    float4 colorLow = atlasTexture.read(uint2(atlasXLow, atlasYLow));

    if (offsetHigh == offsetLow) {
        outputTexture.write(colorLow, gid);
        return;
    }

    uint wrappedHigh = uniforms.capacity > 0 ? (offsetHigh % uniforms.capacity) : 0;
    uint absoluteIndexHigh = (uniforms.frameZeroIndex + uniforms.capacity - wrappedHigh) % uniforms.capacity;
    uint colHigh = absoluteIndexHigh % uniforms.columns;
    uint rowHigh = absoluteIndexHigh / uniforms.columns;
    uint atlasXHigh = colHigh * uniforms.cellWidth + cellX;
    uint atlasYHigh = rowHigh * uniforms.cellHeight + cellY;
    float4 colorHigh = atlasTexture.read(uint2(atlasXHigh, atlasYHigh));

    outputTexture.write(mix(colorLow, colorHigh, offsetBlend), gid);
}

kernel void heatmapFrameOffsetAtlasKernel(
    texture2d<float, access::read> atlasTexture [[texture(0)]],
    texture2d<float, access::read> heatmapTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant HeatmapFrameOffsetUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.outputWidth || gid.y >= uniforms.outputHeight) {
        return;
    }

    if (uniforms.frameCount == 0 || uniforms.columns == 0 || uniforms.rows == 0) {
        outputTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
        return;
    }

    float2 outSize = float2(float(uniforms.outputWidth), float(uniforms.outputHeight));
    float2 uv = (float2(gid) + 0.5f) / outSize;

    uint heatmapWidth = heatmapTexture.get_width();
    uint heatmapHeight = heatmapTexture.get_height();
    uint heatX = min(uint(floor(uv.x * float(heatmapWidth))), heatmapWidth - 1);
    uint heatY = min(uint(floor(uv.y * float(heatmapHeight))), heatmapHeight - 1);
    float4 heatColor = heatmapTexture.read(uint2(heatX, heatY));

    float normalized = clamp(heatColor.r, 0.0f, 1.0f);
    uint availableMax = uniforms.frameCount > 0 ? uniforms.frameCount - 1 : 0;
    uint clampedMaxOffset = min(uniforms.maxFrameOffset, availableMax);
    float offsetFloat = normalized * float(clampedMaxOffset);
    uint offsetLow = uint(floor(offsetFloat));
    uint offsetHigh = min(offsetLow + 1, clampedMaxOffset);
    float offsetBlend = fract(offsetFloat);

    uint wrappedLow = uniforms.capacity > 0 ? (offsetLow % uniforms.capacity) : 0;
    uint absoluteIndexLow = (uniforms.frameZeroIndex + uniforms.capacity - wrappedLow) % uniforms.capacity;
    uint colLow = absoluteIndexLow % uniforms.columns;
    uint rowLow = absoluteIndexLow / uniforms.columns;

    uint cellX = min(uint(floor(uv.x * float(uniforms.cellWidth))), uniforms.cellWidth - 1);
    uint cellY = min(uint(floor(uv.y * float(uniforms.cellHeight))), uniforms.cellHeight - 1);

    uint atlasXLow = colLow * uniforms.cellWidth + cellX;
    uint atlasYLow = rowLow * uniforms.cellHeight + cellY;
    float4 colorLow = atlasTexture.read(uint2(atlasXLow, atlasYLow));

    if (offsetHigh == offsetLow) {
        outputTexture.write(colorLow, gid);
        return;
    }

    uint wrappedHigh = uniforms.capacity > 0 ? (offsetHigh % uniforms.capacity) : 0;
    uint absoluteIndexHigh = (uniforms.frameZeroIndex + uniforms.capacity - wrappedHigh) % uniforms.capacity;
    uint colHigh = absoluteIndexHigh % uniforms.columns;
    uint rowHigh = absoluteIndexHigh / uniforms.columns;
    uint atlasXHigh = colHigh * uniforms.cellWidth + cellX;
    uint atlasYHigh = rowHigh * uniforms.cellHeight + cellY;
    float4 colorHigh = atlasTexture.read(uint2(atlasXHigh, atlasYHigh));

    outputTexture.write(mix(colorLow, colorHigh, offsetBlend), gid);
}

kernel void temporalFadeAtlasKernel(
    texture2d<float, access::read> atlasTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant TemporalFadeAtlasUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.outputWidth || gid.y >= uniforms.outputHeight) {
        return;
    }

    if (uniforms.frameCountInAtlas == 0 || uniforms.columns == 0 || uniforms.rows == 0) {
        outputTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
        return;
    }

    uint safeSpacing = max(uniforms.frameSpacing, 1u);
    uint availableMax = uniforms.frameCountInAtlas > 0 ? uniforms.frameCountInAtlas - 1 : 0;
    uint availableSamples = availableMax / safeSpacing + 1;
    uint sampleCount = min(max(uniforms.blendFrameCount, 1u), max(availableSamples, 1u));

    float2 outSize = float2(float(uniforms.outputWidth), float(uniforms.outputHeight));
    float2 uv = (float2(gid) + 0.5f) / outSize;
    uint cellX = min(uint(floor(uv.x * float(uniforms.cellWidth))), uniforms.cellWidth - 1);
    uint cellY = min(uint(floor(uv.y * float(uniforms.cellHeight))), uniforms.cellHeight - 1);

    float4 sum = float4(0.0f);
    for (uint sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
        uint offset = min(sampleIndex * safeSpacing, availableMax);
        uint wrappedOffset = uniforms.capacity > 0 ? (offset % uniforms.capacity) : 0;
        uint absoluteIndex = (uniforms.frameZeroIndex + uniforms.capacity - wrappedOffset) % uniforms.capacity;
        uint col = absoluteIndex % uniforms.columns;
        uint row = absoluteIndex / uniforms.columns;
        uint atlasX = col * uniforms.cellWidth + cellX;
        uint atlasY = row * uniforms.cellHeight + cellY;
        sum += atlasTexture.read(uint2(atlasX, atlasY));
    }

    float alpha = 1.0f / float(sampleCount);
    outputTexture.write(sum * alpha, gid);
}

kernel void temporalColorSplitAtlasKernel(
    texture2d<float, access::read> atlasTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant TemporalColorSplitAtlasUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.outputWidth || gid.y >= uniforms.outputHeight) {
        return;
    }

    if (uniforms.frameCountInAtlas == 0 || uniforms.columns == 0 || uniforms.rows == 0) {
        outputTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
        return;
    }

    uint safeSpacing = max(uniforms.frameSpacing, 1u);
    uint safeComponents = max(uniforms.componentCount, 1u);
    uint availableMax = uniforms.frameCountInAtlas > 0 ? uniforms.frameCountInAtlas - 1 : 0;
    uint availableSamples = availableMax / safeSpacing + 1;
    uint sampleCount = min(max(uniforms.blendFrameCount, 1u), max(availableSamples, 1u));

    float2 outSize = float2(float(uniforms.outputWidth), float(uniforms.outputHeight));
    float2 uv = (float2(gid) + 0.5f) / outSize;
    uint cellX = min(uint(floor(uv.x * float(uniforms.cellWidth))), uniforms.cellWidth - 1);
    uint cellY = min(uint(floor(uv.y * float(uniforms.cellHeight))), uniforms.cellHeight - 1);

    float3 sumRGB = float3(0.0f);
    float sumAlpha = 0.0f;
    for (uint sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
        uint offset = min(sampleIndex * safeSpacing, availableMax);
        uint wrappedOffset = uniforms.capacity > 0 ? (offset % uniforms.capacity) : 0;
        uint absoluteIndex = (uniforms.frameZeroIndex + uniforms.capacity - wrappedOffset) % uniforms.capacity;
        uint col = absoluteIndex % uniforms.columns;
        uint row = absoluteIndex / uniforms.columns;
        uint atlasX = col * uniforms.cellWidth + cellX;
        uint atlasY = row * uniforms.cellHeight + cellY;
        float4 sampleColor = atlasTexture.read(uint2(atlasX, atlasY));

        uint paletteIndex = sampleIndex % safeComponents;
        float hue = float(paletteIndex) / float(safeComponents);
        float3 tint = hsvToRgb(float3(hue, 1.0f, 1.0f));

        sumRGB += sampleColor.rgb * tint;
        sumAlpha += sampleColor.a;
    }

    float normalization = 1.0f / float(sampleCount);
    outputTexture.write(float4(sumRGB * normalization, sumAlpha * normalization), gid);
}

kernel void jfaClearSeedKernel(
    texture2d<float, access::write> seedTexture [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= seedTexture.get_width() || gid.y >= seedTexture.get_height()) {
        return;
    }
    seedTexture.write(float4(-1.0f, -1.0f, 0.0f, 0.0f), gid);
}

kernel void jfaSplatParticlesKernel(
    const device float2* particles [[buffer(0)]],
    constant JFASplatUniforms& uniforms [[buffer(1)]],
    texture2d<float, access::read_write> seedTexture [[texture(0)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= uniforms.particleCount) {
        return;
    }

    float2 uv = clamp(particles[gid], float2(0.0f), float2(0.999999f));
    uint width = seedTexture.get_width();
    uint height = seedTexture.get_height();

    uint2 pixel = uint2(
        min(uint(uv.x * float(width)), max(0u, width - 1)),
        min(uint(uv.y * float(height)), max(0u, height - 1))
    );
    seedTexture.write(float4(uv, 1.0f, 1.0f), pixel);
}

kernel void jfaJumpFloodKernel(
    texture2d<float, access::read> sourceSeedTexture [[texture(0)]],
    texture2d<float, access::write> destinationSeedTexture [[texture(1)]],
    constant JFAJumpUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    float2 uv = (float2(gid) + 0.5f) / float2(float(uniforms.width), float(uniforms.height));
    float4 bestSeed = sourceSeedTexture.read(gid);
    float bestDistance = 1e20f;

    if (bestSeed.z > 0.5f) {
        float2 diff = bestSeed.xy - uv;
        bestDistance = dot(diff, diff);
    }

    int jump = max(1, int(uniforms.step));
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            int2 sampleCoord = int2(gid) + int2(ox, oy) * jump;
            if (
                sampleCoord.x < 0 || sampleCoord.y < 0 ||
                sampleCoord.x >= int(uniforms.width) || sampleCoord.y >= int(uniforms.height)
            ) {
                continue;
            }

            float4 candidate = sourceSeedTexture.read(uint2(sampleCoord));
            if (candidate.z < 0.5f) {
                continue;
            }

            float2 diff = candidate.xy - uv;
            float distanceSquared = dot(diff, diff);
            if (distanceSquared < bestDistance) {
                bestDistance = distanceSquared;
                bestSeed = candidate;
            }
        }
    }

    if (bestDistance >= 1e19f) {
        destinationSeedTexture.write(float4(-1.0f, -1.0f, 0.0f, 0.0f), gid);
    } else {
        destinationSeedTexture.write(bestSeed, gid);
    }
}

kernel void jfaResolveVoronoiKernel(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture2d<float, access::read> resolvedSeedTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant JFAResolveUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    float4 sourceColor = sourceTexture.read(gid);
    float4 seed = resolvedSeedTexture.read(gid);
    if (seed.z < 0.5f) {
        outputTexture.write(sourceColor, gid);
        return;
    }

    uint maxX = max(0u, uniforms.width - 1);
    uint maxY = max(0u, uniforms.height - 1);
    uint2 seedPixel = uint2(
        min(uint(seed.x * float(uniforms.width)), maxX),
        min(uint(seed.y * float(uniforms.height)), maxY)
    );

    float4 voronoiColor = sourceTexture.read(seedPixel);

    float3 tint = jfaSeedTint(seed.xy);
    float tintAmount = clamp(uniforms.colorVariation, 0.0f, 1.0f);
    voronoiColor.rgb = mix(voronoiColor.rgb, voronoiColor.rgb * tint, tintAmount);

    float edgeVotes = 0.0f;
    float edgeTotal = 0.0f;
    float epsilon = 1e-7f;

    if (gid.x > 0) {
        float4 neighbor = resolvedSeedTexture.read(uint2(gid.x - 1, gid.y));
        edgeTotal += 1.0f;
        if (neighbor.z > 0.5f) {
            float2 delta = neighbor.xy - seed.xy;
            if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
        } else {
            edgeVotes += 1.0f;
        }
    }
    if (gid.x < maxX) {
        float4 neighbor = resolvedSeedTexture.read(uint2(gid.x + 1, gid.y));
        edgeTotal += 1.0f;
        if (neighbor.z > 0.5f) {
            float2 delta = neighbor.xy - seed.xy;
            if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
        } else {
            edgeVotes += 1.0f;
        }
    }
    if (gid.y > 0) {
        float4 neighbor = resolvedSeedTexture.read(uint2(gid.x, gid.y - 1));
        edgeTotal += 1.0f;
        if (neighbor.z > 0.5f) {
            float2 delta = neighbor.xy - seed.xy;
            if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
        } else {
            edgeVotes += 1.0f;
        }
    }
    if (gid.y < maxY) {
        float4 neighbor = resolvedSeedTexture.read(uint2(gid.x, gid.y + 1));
        edgeTotal += 1.0f;
        if (neighbor.z > 0.5f) {
            float2 delta = neighbor.xy - seed.xy;
            if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
        } else {
            edgeVotes += 1.0f;
        }
    }

    float edge = edgeTotal > 0.0f ? (edgeVotes / edgeTotal) : 0.0f;
    float edgeAmount = clamp(uniforms.edgeIntensity, 0.0f, 1.0f);
    voronoiColor.rgb *= (1.0f - edge * edgeAmount);

    float blend = clamp(uniforms.blend, 0.0f, 1.0f);
    outputTexture.write(mix(sourceColor, voronoiColor, blend), gid);
}

#endif
