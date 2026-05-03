#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

// MARK: - Reference Constants
// BT.2408 diffuse white reference: 203 nits maps to EDR 1.0 on a correctly-calibrated display.
constant float PQ_REFERENCE_WHITE_NITS = 203.0;
// Luma coefficients for each color space (used for luma-preserved grading).
constant float3 kRec709Luma  = float3(0.2126,  0.7152,  0.0722);
constant float3 kRec2020Luma = float3(0.2627,  0.6780,  0.0593);
constant float3 kDisplayP3Luma = float3(0.2289, 0.6917, 0.0793);
// HDR: fixed contrast pivot (EDR scene space). SDR keeps per-pixel luma pivot (legacy accurate SDR).
constant float kHDRContrastPivot = 0.10;

// MARK: - Structures

struct ColorEnhancementUniforms {
    float saturation;
    float contrast;
    float warmth;
    float padding1;
};

// Shader-side HDR frame parameters — describes the incoming video signal.
// Swift side must match this layout exactly (field order + types + padding).
// The YUV conversion matrix and offsets are computed on the CPU once per format
// change and passed here, eliminating all branching in the fragment shader.
struct ShaderHDRParams {
    uint    isPQ;           // 1 = SMPTE ST.2084 PQ transfer function, 0 = SDR / extended
    uint    primariesType;  // 0 = BT.709/P3, 1 = BT.2020, 2 = SMPTE-C  (gamut map selector)
    uint    extendedScene;  // 1 = Moonlight HDR + non-PQ: extended desktop path in processFrame
    uint    reserved0;
    float   edrHeadroom;    // Tone map ceiling (fixed 2.0 on visionOS)
    float   pad;
    float2  alignPad;       // Pad to 32 bytes before optional HDR metadata
    // Sunshine ST 2086 sidecar (LiGetHdrMetadata): maxCLL / maxFALL in nits; 0 = ignore (legacy tone map).
    float   maxContentNits;
    float   maxFrameAvgNits;
    float2  padHdrMeta;     // Pad to 48 bytes before float3x3 (16-byte alignment)
    // Precomputed YUV → RGB conversion (column-major, CPU-selected per format).
    // Eliminates all if/else branching in the fragment shader.
    float3x3 yuvMatrix;     // Full YUV→RGB matrix (includes range scaling)
    float3   yuvOffset;     // Subtract before matrix multiply (Y black, UV center)
};

// User-facing HDR grading parameters.
struct FullHDRParams {
    float boost;        // Linear luminance multiplier (1.0 = neutral)
    float contrast;     // Luma-preserved contrast (1.0 = neutral)
    float saturation;   // Color saturation (1.0 = neutral)
    float brightness;   // Additive brightness offset (0.0 = neutral)
    float pqExposure;   // Global exposure trim (1.0 = neutral); applies to both HDR and SDR paths
    int   mode;         // UIKit / preset mode (unchanged)
    uint  hdrGradeFlags;// bit0 = Reference HDR: PQ + gamut + tone map only (no client grade / trims)
};

struct CopyVertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - SDR / TestFlight-only (8798705) — buffers for `copyFragmentShaderHDR_EDR` when HDR is OFF
// Declared before any HDR-unified code so SDR fragments never depend on ShaderHDRParams / processFrame.

constant float LEGACY_SDR_REFERENCE_WHITE_NITS = 200.0;

struct LegacySDRFrameParams {
    uint presetIndex;
    uint isPQ;
    uint isBT2020Matrix;
    uint isBT2020Primaries;
};

struct LegacySDRFullParams {
    float boost;
    float contrast;
    float saturation;
    float brightness;
    int   mode;
};

inline float legacy_sdr_pq_inv(float p) {
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;
    p = clamp(p, 0.0, 1.0);
    float n   = pow(p, 1.0 / m2);
    float num = max(n - c1, 0.0);
    float den = max(c2 - c3 * n, 1e-4);
    return pow(num / den, 1.0 / m1) * 10000.0;
}

inline float3 legacy_sdr_pq_inv(float3 p) {
    return float3(legacy_sdr_pq_inv(p.r), legacy_sdr_pq_inv(p.g), legacy_sdr_pq_inv(p.b));
}

inline float legacy_sdr_expand_y(float y) {
    return clamp((y - 0.06256) * 1.16780, 0.0, 1.0);
}

inline float2 legacy_sdr_expand_uv(float2 uv) {
    return (uv - float2(0.5, 0.5)) * 1.14170;
}

inline float3 legacy_sdr_apply_vision_pro_grading(float3 color, ColorEnhancementUniforms params) {
    if (abs(params.saturation - 1.0) < 0.001 &&
        abs(params.contrast   - 1.0) < 0.001 &&
        abs(params.warmth)    < 0.001) {
        return clamp(color, 0.0, 1.0);
    }
    float luma = dot(color, kRec709Luma);
    float3 saturated = mix(float3(luma), color, params.saturation);
    float3 contrasted = (saturated - 0.5) * params.contrast + 0.5;
    float3 warmed = contrasted;
    if (abs(params.warmth) > 0.001) {
        warmed.r = contrasted.r * (1.0 + params.warmth * 0.5);
        warmed.b = contrasted.b * (1.0 - params.warmth * 0.5);
        warmed = clamp(warmed, 0.0, 1.0);
    }
    return clamp(warmed, 0.0, 1.0);
}

inline float3 legacy_sdr_apply_vision_pro_grading(float3 color, constant ColorEnhancementUniforms& paramsConst) {
    ColorEnhancementUniforms local = paramsConst;
    return legacy_sdr_apply_vision_pro_grading(color, local);
}

// MARK: - Gamut Conversion Matrices
// Column-major, linear light, D65 white point. Derived from ICC chromaticity coordinates.

// BT.709 linear → Display P3 linear
constant float3x3 BT709_TO_DISPLAYP3 = float3x3(
    float3(0.82246,  0.03319,  0.01708),
    float3(0.17754,  0.96681,  0.07240),
    float3(0.00000,  0.00000,  0.91052)
);

// BT.2020 linear → Display P3 linear
constant float3x3 BT2020_TO_DISPLAYP3 = float3x3(
    float3( 1.22494, -0.04206, -0.01964),
    float3(-0.22494,  1.04206, -0.07864),
    float3( 0.00000,  0.00000,  1.09827)
);

// SMPTE-C (BT.601) linear → BT.709 linear
constant float3x3 SMPTEC_TO_BT709 = float3x3(
    float3( 1.0654, -0.0196,  0.0016),
    float3(-0.0554,  1.0364, -0.0044),
    float3(-0.0010, -0.0167,  1.0028)
);

// MARK: - SDR Transfer Function
// Windows PCs and PC games are mastered for gamma 2.2 / BT.1886.
// Using 2.2 here matches how content actually looks on the source monitor,
// giving correct mid-tone punch vs the source PC display.
// (Apple's own 1.961 is only correct for Rec.709 content in QuickTime/Safari.)
inline float3 sdrToLinear(float3 c) {
    return pow(clamp(c, 0.0, 1.0), float3(2.2));
}

// MARK: - YUV Decode
// The conversion matrix and offset were precomputed on the Swift CPU side
// (selecting the right ITU matrix + range scaling for this frame's format).
// Zero branching here — one multiply-add covers all six format combinations.
inline float3 decodeYUV(float y, float2 uv, constant ShaderHDRParams& p) {
    float3 yuv = float3(y, uv.x, uv.y) - p.yuvOffset;
    return p.yuvMatrix * yuv;
}

// MARK: - PQ Inverse Transfer Function (SMPTE ST.2084)
// Returns absolute luminance in nits (0–10000).
inline float pqToNits(float p) {
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;
    p = clamp(p, 0.0, 1.0);
    float n   = pow(p, 1.0 / m2);
    float num = max(n - c1, 0.0);
    float den = max(c2 - c3 * n, 1e-4);
    return pow(num / den, 1.0 / m1) * 10000.0;
}

inline float3 pqToNits(float3 p) {
    return float3(pqToNits(p.r), pqToNits(p.g), pqToNits(p.b));
}

// MARK: - Gamut Mapping for SDR Content
// Maps SDR primaries to linear Display P3 for the rgba16Float drawable.
inline float3 sdrPrimariesToDisplayP3(float3 linearColor, constant ShaderHDRParams& p) {
    if (p.primariesType == 1u) {
        return max(BT2020_TO_DISPLAYP3 * linearColor, float3(0.0));
    } else if (p.primariesType == 2u) {
        float3 as709 = max(SMPTEC_TO_BT709 * linearColor, float3(0.0));
        return max(BT709_TO_DISPLAYP3 * as709, float3(0.0));
    }
    return max(BT709_TO_DISPLAYP3 * linearColor, float3(0.0));
}

// MARK: - Uchimura Tone Mapping Operator
// From Hajime Uchimura, "HDR Theory and Practice" (CEDEC 2018 / GDC 2018).
// Designed specifically for game content; smooth shoulder, no ACES hue rotation.
// P  = max display brightness (in EDR units relative to SDR white)
// a  = contrast in the linear section
// m  = start of the linear section
// l  = length of the linear section
// c  = black tightness (toe)
// b  = black pedestal
inline float uchimura(float x, float P, float a, float m, float l, float c, float b) {
    float l0 = ((P - m) * l) / a;
    float L0 = m - m / a;
    float L1 = m + (1.0 - m) / a;
    float S0 = m + l0;
    float S1 = m + a * l0;
    float C2 = (a * P) / (P - S1);
    float CP = -C2 / P;

    float w0 = 1.0 - smoothstep(0.0, m, x);
    float w2 = step(m + l0, x);
    float w1 = 1.0 - w0 - w2;

    float T = m * pow(x / m, c) + b;
    float S = P - (P - S1) * exp(CP * (x - S0));
    float L = m + a * (x - m);

    return T * w0 + L * w1 + S * w2;
}

// Widen Uchimura shoulder P when Sunshine reports modest maxCLL / low maxFALL (typical Windows HDR desktop)
// so mids/highlights are not flattened; 0 maxContentNits leaves base P unchanged.
inline float hdrUchimuraShoulderP(float baseP, float maxContentNits, float maxFrameAvgNits) {
    float P = clamp(baseP, 1.2, 6.0);
    if (maxContentNits > 1.0) {
        float peakEdr = clamp(maxContentNits / PQ_REFERENCE_WHITE_NITS, 1.05, 40.0);
        float target = peakEdr * 1.08;
        if (maxFrameAvgNits > 1.0) {
            float fallEdr = clamp(maxFrameAvgNits / PQ_REFERENCE_WHITE_NITS, 0.15, peakEdr);
            target = max(target, fallEdr * 2.2);
        }
        P = clamp(max(P, target), 1.2, 6.0);
    }
    return P;
}

// Apply Uchimura per luma channel to preserve chromaticity (avoids hue twist).
// edrCeiling is the live display EDR headroom passed from Swift each frame.
inline float3 uchimuraToneMap(float3 colorP3, float edrCeiling, float maxContentNits, float maxFrameAvgNits) {
    float P = hdrUchimuraShoulderP(clamp(edrCeiling, 1.2, 6.0), maxContentNits, maxFrameAvgNits);
    // Tuned for Vision Pro's ~100-nit effective eye output with micro-OLED infinite black.
    float a = 1.0;   // Linear section contrast
    float m = 0.22;  // Linear section start (matches Reinhard mid-gray)
    float l = 0.40;  // Linear section length
    float c = 1.33;  // Toe (black tightness)
    float b = 0.0;   // Black pedestal

    float luma = max(dot(colorP3, kDisplayP3Luma), 1e-6);
    float mappedLuma = uchimura(luma, P, a, m, l, c, b);
    return colorP3 * (mappedLuma / luma);
}

/// Reference HDR: same Uchimura family but slightly **higher shoulder P** and gentler **toe** so
/// mids/highlights are not rolled off as aggressively (Enhanced path used to add boost/sat *before* TM).
/// A small **chroma recovery** after TM offsets perceived desaturation from luma-only scaling.
inline float3 uchimuraToneMapReference(float3 colorP3, float edrCeiling, float maxContentNits, float maxFrameAvgNits) {
    float baseP = clamp(max(edrCeiling * 1.18, 2.55), 1.35, 6.0);
    float P = hdrUchimuraShoulderP(baseP, maxContentNits, maxFrameAvgNits);
    float a = 1.0;
    float m = 0.22;
    float l = 0.42;
    float c = 1.18;
    float b = 0.0;

    float luma = max(dot(colorP3, kDisplayP3Luma), 1e-6);
    float mappedLuma = uchimura(luma, P, a, m, l, c, b);
    float3 tm = colorP3 * (mappedLuma / luma);

    float L = max(dot(tm, kDisplayP3Luma), 1e-4);
    const float kRefChromaRecover = 1.065;
    return max(mix(float3(L), tm, kRefChromaRecover), float3(0.0));
}

// MARK: - Luma-Preserved Color Grading
// Original per-pixel luma pivot (for SDR; matches pre-overhaul behavior exactly).
inline float3 lumaPreservedGrading(float3 color, float saturation, float contrast, float warmth, float3 lumaWeights) {
    float luma = dot(color, lumaWeights);

    // Saturation: mix toward luma-only
    float3 saturated = mix(float3(luma), color, saturation);

    // Contrast: scale chroma around luma (not around 0.5)
    float3 contrasted = (saturated - float3(luma)) * contrast + float3(luma);

    // Warmth: slight red lift / blue reduction
    float3 warmed = contrasted;
    if (abs(warmth) > 0.001) {
        warmed.r = contrasted.r * (1.0 + warmth * 0.5);
        warmed.b = contrasted.b * (1.0 - warmth * 0.5);
    }

    return max(warmed, float3(0.0));
}

// HDR: per-pixel luma pivot for contrast to avoid crushing shadows and black-level drift.
inline float3 lumaPreservedGradingHDR(float3 color, float saturation, float contrast, float warmth, float3 lumaWeights) {
    float luma = dot(color, lumaWeights);

    // Saturation: mix toward luma-only
    float3 saturated = mix(float3(luma), color, saturation);

    // Contrast: scale chroma around luma (not around a fixed pivot)
    float3 contrasted = (saturated - float3(luma)) * contrast + float3(luma);

    // Warmth: slight red lift / blue reduction
    float3 warmed = contrasted;
    if (abs(warmth) > 0.001) {
        warmed.r = contrasted.r * (1.0 + warmth * 0.5);
        warmed.b = contrasted.b * (1.0 - warmth * 0.5);
    }

    return max(warmed, float3(0.0));
}

// SDR variant clamps output to [0, 1].
inline float3 lumaPreservedGradingSDR(float3 color, float saturation, float contrast, float warmth) {
    return clamp(lumaPreservedGrading(color, saturation, contrast, warmth, kRec709Luma), 0.0, 1.0);
}

// MARK: - Radial Saturation Falloff
// Vision Pro's pancake optics produce chromatic aberration toward the screen periphery.
// Reducing saturation slightly at the edges compensates and avoids harsh color fringing.
// The effect is intentionally subtle (max 12% reduction at corners).
inline float radialSaturationScale(float2 uv) {
    float edgeDist = length(uv - float2(0.5));
    return 1.0 - smoothstep(0.30, 0.70, edgeDist) * 0.12;
}

// MARK: - Rounded Rectangle SDF (UIKit renderer corner clipping)
inline float roundedRectSDF(float2 centerPos, float2 halfSize, float radius) {
    return length(max(abs(centerPos) - halfSize + radius, 0.0)) - radius;
}

// MARK: - Vertex Shader
vertex CopyVertexOut copyVertexShader(ushort vid [[vertex_id]]) {
    CopyVertexOut o;
    float2 uv = float2(float((vid << 1) & 2u), float(vid & 2u) * 0.5);
    o.position = float4((uv * float2(2.0, -2.0)) + float2(-1.0, 1.0), 0.0, 1.0);
    o.uv = uv;
    return o;
}

// MARK: - Shared Processing Core
// All four fragment shaders funnel their decoded RGB into this function.
// Keeps logic in one place so all renderers are always in sync.
inline float3 processFrame(
    float3 rgb_raw,
    float2 uv,
    constant ShaderHDRParams& p,
    constant FullHDRParams& full,
    constant ColorEnhancementUniforms& enh
) {
    float3 finalColor;
    const uint kHDRGradeReference = 1u;
    bool referenceHdr = (full.hdrGradeFlags & kHDRGradeReference) != 0u;

    if (p.isPQ == 1u) {
        // --- PQ / HDR path ---
        // 1. PQ decode → absolute nits
        float3 nits = pqToNits(clamp(rgb_raw, 0.0, 1.0));

        // 2. Scale to EDR units relative to 203-nit reference white (BT.2408)
        float3 edr = nits / PQ_REFERENCE_WHITE_NITS;

        // 3. Gamut: BT.2020 → Display P3 (or BT.709 → Display P3 if 709 primaries)
        bool use2020 = (p.primariesType == 1u);
        float3 colorP3 = use2020
            ? max(BT2020_TO_DISPLAYP3 * edr, float3(0.0))
            : max(BT709_TO_DISPLAYP3  * edr, float3(0.0));

        if (referenceHdr) {
            // Reference: PQ + gamut + dedicated tone map (no panel sliders). TM tuned slightly
            // punchier than the Enhanced default map + mild chroma recovery (see uchimuraToneMapReference).
            finalColor = uchimuraToneMapReference(colorP3, p.edrHeadroom, p.maxContentNits, p.maxFrameAvgNits);
        } else {
            // 4. User grading (luma-preserved, no hard clamp — preserves HDR headroom)
            float3 lumaW = use2020 ? kRec2020Luma : kDisplayP3Luma;
            float radialSat = radialSaturationScale(uv);
            float effectiveSat = enh.saturation * full.saturation * radialSat;
            colorP3 = lumaPreservedGradingHDR(colorP3, effectiveSat, enh.contrast * full.contrast, enh.warmth, lumaW);

            // 5. User level trims (HDR path — applied in linear light before tone mapping)
            colorP3 *= max(full.boost, 0.0);
            colorP3 += max(full.brightness, 0.0);
            colorP3 *= max(full.pqExposure, 0.0);

            // 6. Uchimura tone map against live EDR headroom (no display-specific black lift afterward).
            colorP3 = uchimuraToneMap(colorP3, p.edrHeadroom, p.maxContentNits, p.maxFrameAvgNits);

            finalColor = colorP3;
        }

    } else {
        // --- Non-PQ path (Moonlight HDR on: Windows Advanced Color desktop, scRGB-like, etc.) ---
        float3 colorSDR;
        if (p.extendedScene != 0u) {
            // Do not clamp to SDR [0,1] first — that crushes Windows HDR desktop into a milky veil.
            // Compress extended peaks with the same Uchimura family used for luma, then allow grading.
            colorSDR = max(rgb_raw, float3(0.0));
            float peak = max(max(colorSDR.r, colorSDR.g), colorSDR.b);
            peak = max(peak, 1e-5);
            float3 chromaDir = colorSDR / peak;
            float P = hdrUchimuraShoulderP(clamp(p.edrHeadroom, 1.25, 6.0), p.maxContentNits, p.maxFrameAvgNits);
            float mappedPeak = uchimura(peak, P, 1.0, 0.22, 0.42, 1.18, 0.0);
            colorSDR = chromaDir * mappedPeak;
            colorSDR = min(colorSDR, float3(1.0));
        } else {
            // True SDR: gamma-encoded RGB in [0,1] after decode.
            colorSDR = clamp(rgb_raw, 0.0, 1.0);
        }

        if (referenceHdr) {
            finalColor = colorSDR;
        } else {
            // User grading (gamma-space, matching baseline applyVisionProGrading behavior)
            float radialSat = radialSaturationScale(uv);
            float effectiveSat = enh.saturation * full.saturation * radialSat;
            colorSDR = lumaPreservedGradingSDR(colorSDR, effectiveSat, enh.contrast * full.contrast, enh.warmth);

            // User level trims (include exposure so the panel matches PQ and SDR-in-unified paths)
            colorSDR *= max(full.boost, 0.0);
            colorSDR += max(full.brightness, 0.0);
            colorSDR *= max(full.pqExposure, 0.0);

            finalColor = clamp(colorSDR, 0.0, 1.0);
        }
    }

    // Safety ceiling — prevents any runaway value from blowing out the display.
    return min(finalColor, float3(20.0));
}

// MARK: - HDR-only unified path (app HDR ON — never bound for SDR)

fragment half4 copyFragmentShaderHDR_HDRUnified(
    CopyVertexOut in [[stage_in]],
    texture2d<float> yTex   [[texture(0)]],
    texture2d<float> uvTex  [[texture(1)]],
    constant ShaderHDRParams         &params [[buffer(0)]],
    constant FullHDRParams           &full   [[buffer(1)]],
    constant ColorEnhancementUniforms &enh   [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float  ySample  = yTex.sample(s, in.uv).r;
    float2 uvSample = uvTex.sample(s, in.uv).rg;

    float3 rgb = decodeYUV(ySample, uvSample, params);

    float3 finalColor = processFrame(rgb, in.uv, params, full, enh);
    return half4(half3(finalColor), 1.0h);
}

fragment half4 copyFragmentShaderHEVC_HDRUnified(
    CopyVertexOut in [[stage_in]],
    texture2d<half> rgbTex [[texture(0)]],
    constant ShaderHDRParams         &params [[buffer(0)]],
    constant FullHDRParams           &full   [[buffer(1)]],
    constant ColorEnhancementUniforms &enh   [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float3 rgb = float3(rgbTex.sample(s, in.uv).rgb);

    float3 finalColor = processFrame(rgb, in.uv, params, full, enh);
    return half4(half3(finalColor), 1.0h);
}

// MARK: - SDR / TestFlight RealityKit (`8798705` — no decodeYUV / processFrame)

fragment half4 copyFragmentShaderHDR_EDR(
    CopyVertexOut in [[stage_in]],
    texture2d<float> yTex   [[texture(0)]],
    texture2d<float> uvTex  [[texture(1)]],
    constant LegacySDRFrameParams      &params [[buffer(0)]],
    constant LegacySDRFullParams        &full   [[buffer(1)]],
    constant ColorEnhancementUniforms   &enhancements [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float  ySample  = yTex.sample(s, in.uv).r;
    float2 uvSample = uvTex.sample(s, in.uv).rg;

    float y  = legacy_sdr_expand_y(ySample);
    float2 uv = legacy_sdr_expand_uv(uvSample);
    float cb = uv.x;
    float cr = uv.y;

    float3 rgb_nl;
    if (params.isBT2020Matrix == 1u) {
        rgb_nl = float3(y + 1.4746 * cr, y - 0.16455 * cb - 0.57135 * cr, y + 1.8814 * cb);
    } else {
        rgb_nl = float3(y + 1.5748 * cr, y - 0.1873 * cb - 0.4681 * cr, y + 1.8556 * cb);
    }

    float3 finalColor;
    if (params.isPQ == 1u) {
        float3 linearNits = legacy_sdr_pq_inv(clamp(rgb_nl, 0.0, 1.0));
        finalColor = linearNits / LEGACY_SDR_REFERENCE_WHITE_NITS;
    } else {
        finalColor = rgb_nl;
    }

    finalColor *= max(full.boost, 0.0);
    finalColor += max(full.brightness, 0.0);

    ColorEnhancementUniforms eff = enhancements;
    eff.saturation = enhancements.saturation * full.saturation;
    eff.contrast   = enhancements.contrast   * full.contrast;

    finalColor = legacy_sdr_apply_vision_pro_grading(finalColor, eff);
    finalColor = (params.isPQ == 1u) ? min(finalColor, float3(20.0)) : clamp(finalColor, 0.0, 1.0);
    return half4(half3(finalColor), 1.0h);
}

fragment half4 copyFragmentShaderHEVC_EDR(
    CopyVertexOut in [[stage_in]],
    texture2d<half> rgbTex [[texture(0)]],
    constant LegacySDRFrameParams      &params [[buffer(0)]],
    constant LegacySDRFullParams        &full   [[buffer(1)]],
    constant ColorEnhancementUniforms   &enhancements [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float3 rgb_nl = float3(rgbTex.sample(s, in.uv).rgb);

    float3 finalColor;
    if (params.isPQ == 1u) {
        float3 linearNits = legacy_sdr_pq_inv(clamp(rgb_nl, 0.0, 1.0));
        finalColor = linearNits / LEGACY_SDR_REFERENCE_WHITE_NITS;
    } else {
        finalColor = rgb_nl;
    }

    finalColor *= max(full.boost, 0.0);
    finalColor += max(full.brightness, 0.0);

    ColorEnhancementUniforms eff = enhancements;
    eff.saturation = enhancements.saturation * full.saturation;
    eff.contrast   = enhancements.contrast   * full.contrast;

    finalColor = legacy_sdr_apply_vision_pro_grading(finalColor, eff);
    finalColor = (params.isPQ == 1u) ? min(finalColor, float3(20.0)) : clamp(finalColor, 0.0, 1.0);
    return half4(half3(finalColor), 1.0h);
}

// MARK: - UIKit (HDR unified vs TestFlight SDR)

fragment half4 copyFragmentShaderHDR_HDRUnified_UIKit(
    CopyVertexOut in [[stage_in]],
    texture2d<float> yTex   [[texture(0)]],
    texture2d<float> uvTex  [[texture(1)]],
    constant ShaderHDRParams         &params [[buffer(0)]],
    constant FullHDRParams           &full   [[buffer(1)]],
    constant ColorEnhancementUniforms &enh   [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 texSize  = float2(yTex.get_width(), yTex.get_height());
    float2 pixPos   = in.uv * texSize;
    float2 center   = pixPos - (texSize * 0.5);
    float  dist     = roundedRectSDF(center, texSize * 0.5, 16.0);
    if (dist > 0.0) { discard_fragment(); }

    float  ySample  = yTex.sample(s, in.uv).r;
    float2 uvSample = uvTex.sample(s, in.uv).rg;

    float3 rgb = decodeYUV(ySample, uvSample, params);

    float3 finalColor = processFrame(rgb, in.uv, params, full, enh);
    return half4(half3(finalColor), 1.0h);
}

fragment half4 copyFragmentShaderHEVC_HDRUnified_UIKit(
    CopyVertexOut in [[stage_in]],
    texture2d<half> rgbTex [[texture(0)]],
    constant ShaderHDRParams         &params [[buffer(0)]],
    constant FullHDRParams           &full   [[buffer(1)]],
    constant ColorEnhancementUniforms &enh   [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 texSize = float2(rgbTex.get_width(), rgbTex.get_height());
    float2 pixPos  = in.uv * texSize;
    float2 center  = pixPos - (texSize * 0.5);
    float  dist    = roundedRectSDF(center, texSize * 0.5, 16.0);
    if (dist > 0.0) { discard_fragment(); }

    float3 rgb = float3(rgbTex.sample(s, in.uv).rgb);

    float3 finalColor = processFrame(rgb, in.uv, params, full, enh);
    return half4(half3(finalColor), 1.0h);
}

fragment half4 copyFragmentShaderHDR_EDR_UIKit(
    CopyVertexOut in [[stage_in]],
    texture2d<float> yTex   [[texture(0)]],
    texture2d<float> uvTex  [[texture(1)]],
    constant LegacySDRFrameParams      &params [[buffer(0)]],
    constant LegacySDRFullParams        &full   [[buffer(1)]],
    constant ColorEnhancementUniforms   &enhancements [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 texSize   = float2(yTex.get_width(), yTex.get_height());
    float2 pixelPos  = in.uv * texSize;
    float2 centerPos = pixelPos - (texSize * 0.5);
    float  cornerRadius = 16.0;
    float  dist = roundedRectSDF(centerPos, texSize * 0.5, cornerRadius);
    float  alpha = 1.0 - smoothstep(-0.5, 0.5, dist);

    float  ySample  = yTex.sample(s, in.uv).r;
    float2 uvSample = uvTex.sample(s, in.uv).rg;

    float y  = legacy_sdr_expand_y(ySample);
    float2 uv = legacy_sdr_expand_uv(uvSample);
    float cb = uv.x;
    float cr = uv.y;

    float3 rgb_nl;
    if (params.isBT2020Matrix == 1u) {
        rgb_nl = float3(y + 1.4746 * cr, y - 0.16455 * cb - 0.57135 * cr, y + 1.8814 * cb);
    } else {
        rgb_nl = float3(y + 1.5748 * cr, y - 0.1873 * cb - 0.4681 * cr, y + 1.8556 * cb);
    }

    float3 finalColor;
    if (params.isPQ == 1u) {
        float3 linearNits = legacy_sdr_pq_inv(clamp(rgb_nl, 0.0, 1.0));
        finalColor = linearNits / LEGACY_SDR_REFERENCE_WHITE_NITS;
    } else {
        finalColor = rgb_nl;
    }

    finalColor *= max(full.boost, 0.0);
    finalColor += max(full.brightness, 0.0);

    ColorEnhancementUniforms eff = enhancements;
    eff.saturation = enhancements.saturation * full.saturation;
    eff.contrast   = enhancements.contrast   * full.contrast;

    finalColor = legacy_sdr_apply_vision_pro_grading(finalColor, eff);
    finalColor = (params.isPQ == 1u) ? min(finalColor, float3(20.0)) : clamp(finalColor, 0.0, 1.0);

    return half4(half3(finalColor), half(alpha));
}

fragment half4 copyFragmentShaderHEVC_EDR_UIKit(
    CopyVertexOut in [[stage_in]],
    texture2d<half> rgbTex [[texture(0)]],
    constant LegacySDRFrameParams      &params [[buffer(0)]],
    constant LegacySDRFullParams        &full   [[buffer(1)]],
    constant ColorEnhancementUniforms   &enhancements [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 texSize   = float2(rgbTex.get_width(), rgbTex.get_height());
    float2 pixelPos  = in.uv * texSize;
    float2 centerPos = pixelPos - (texSize * 0.5);
    float  cornerRadius = 16.0;
    float  dist = roundedRectSDF(centerPos, texSize * 0.5, cornerRadius);
    float  alpha = 1.0 - smoothstep(-0.5, 0.5, dist);

    float3 rgb_nl = float3(rgbTex.sample(s, in.uv).rgb);

    float3 finalColor;
    if (params.isPQ == 1u) {
        float3 linearNits = legacy_sdr_pq_inv(clamp(rgb_nl, 0.0, 1.0));
        finalColor = linearNits / LEGACY_SDR_REFERENCE_WHITE_NITS;
    } else {
        finalColor = rgb_nl;
    }

    finalColor *= max(full.boost, 0.0);
    finalColor += max(full.brightness, 0.0);

    ColorEnhancementUniforms eff = enhancements;
    eff.saturation = enhancements.saturation * full.saturation;
    eff.contrast   = enhancements.contrast   * full.contrast;

    finalColor = legacy_sdr_apply_vision_pro_grading(finalColor, eff);
    finalColor = (params.isPQ == 1u) ? min(finalColor, float3(20.0)) : clamp(finalColor, 0.0, 1.0);

    return half4(half3(finalColor), half(alpha));
}

// MARK: - ChromaHalo Edge Bloom Shader
//
// Renders the edge glow layer behind the main video mesh (Chromosphere).
// Halo mesh is haloScale× wider and taller in meters; videoScale is uniform on both
// axes so top/bottom pads match left/right in texture space (avoids “side-only” glow).
// Perimeter samples use an anisotropic blur: more spread along the edge direction.
//
// Inputs:
//   texture(0): sourceTex  — downsampled mip of the current video frame
//   texture(1): prevTex    — previous ChromaHalo output for temporal smoothing
//   buffer(1):  haloScale  — physical scale factor of the halo mesh vs screen (e.g. 1.55)
//   buffer(2):  intensity  — user-controlled brightness scalar (0.0–2.0)

fragment half4 chromaHaloFragment(
    CopyVertexOut in [[stage_in]],
    texture2d<half> sourceTex [[texture(0)]],
    texture2d<half> prevTex   [[texture(1)]],
    constant float  &haloScale [[buffer(1)]],
    constant float  &intensity [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float w      = max(float(sourceTex.get_width()),  1.0);
    float h      = max(float(sourceTex.get_height()), 1.0);
    float aspect = w / h;

    // Map halo render UV back to normalized video rectangle [0,1]^2 (both axes).
    // Physical halo mesh scales by haloScale in width AND height meters; asymmetric
    // Y scale here was starving top/bottom in texture space while sides looked rich.
    float2 videoScale = float2(haloScale);
    float2 videoUV    = (in.uv - 0.5) * videoScale + 0.5;

    // Distance from video edge: combine fractional x/y excursion with pixel aspect so
    // corners + top/bottom get similar physical falloff weights.
    float2 boundaryRaw = max(float2(0.0), abs(videoUV - 0.5) * 2.0 - 1.0);
    float bx = boundaryRaw.x;
    float by = boundaryRaw.y;
    float byScaled = by / aspect;
    // Euclidean reach for blur spread only — do NOT drive outer alpha (aspect shrinks dy and
    // leaves normalizedDist < 1 on top/bottom rims → visible “hard shelf” vs sides).
    float dist = sqrt(bx * bx + byScaled * byScaled);

    // Reactive V1 reach tiers > 1.55: slightly wider blur + softer temporal mix (reduces “muddy” rim at large scale).
    const float kChromaHaloScaleBase = 1.55f;
    const float kChromaHaloScaleSpan = 1.93f; // maxScale(3.48) − kChromaHaloScaleBase; sync with Reactive1ChromosphereReach haloScales.last
    float haloReachT = saturate((haloScale - kChromaHaloScaleBase) / max(kChromaHaloScaleSpan, 1e-4f));
    float blurReachMul   = 1.0f + haloReachT * 0.17f;
    float temporalReachB = haloReachT * 0.055f;

    // Hollow center — pixels under the video mesh are transparent.
    // Slight shrink (0.88) ensures the cutout fully hides behind the video's rounded corners.
    float2 hollowCheck = max(float2(0.0), abs(videoUV - 0.5) * 2.0 - 0.88);
    if (length(hollowCheck) <= 0.0) { return half4(0.0); }

    // Perimeter zone clamping — clamp to a ring of inset sample points.
    // 8% inset avoids hardware decoder border artifacts.
    float2 safeMin = float2(0.08);
    float2 safeMax = float2(0.92);
    float2 zoneClamped;
    zoneClamped.x = clamp(videoUV.x, safeMin.x, safeMax.x);
    zoneClamped.y = clamp(videoUV.y, safeMin.y, safeMax.y);

    // Dynamic sample spread: pixels further from the screen sample a wider area,
    // smoothly diffusing color outward without hard bands.
    float spread  = 1.0 + dist * 6.0;
    float blurRad = min(0.10 * spread * blurReachMul, 0.38 * blurReachMul);

    // Anisotropic blur: elongate blur along edges so top/bottom smear sideways and
    // left/right wings smear vertically — reads more like ambient light bleeding.
    float topBottomDominant = saturate(by - bx);
    float leftRightDominant = saturate(bx - by);
    float blurMux = 1.0 + topBottomDominant * 2.95;
    float blurMvy = 1.0 + leftRightDominant * 2.95;

    // 3x3 Gaussian-weighted color gather from source video mip.
    half4  color       = half4(0.0);
    float  totalWeight = 0.0;
    float  maxLuma     = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 offset    = blurRad * float2(float(dx) * blurMux, float(dy) * blurMvy);
            float2 sampleUV  = clamp(zoneClamped + offset, safeMin, safeMax);
            half4  sampleCol = sourceTex.sample(s, sampleUV);
            float  w_g       = exp(-float(dx*dx + dy*dy) * 0.5);
            color       += sampleCol * half(w_g);
            totalWeight += w_g;
            float luma   = dot(float3(sampleCol.rgb), float3(0.2126, 0.7152, 0.0722));
            maxLuma      = max(maxLuma, luma);
        }
    }
    color /= half(totalWeight);

    // Saturation boost — pushes chroma vs luma so the rim reads against passthrough (lower = truer dull sand/mud, less “orange crush”).
    float avgLuma  = dot(float3(color.rgb), float3(0.2126, 0.7152, 0.0722));
    float satBoost = 1.62f;
    color.rgb = mix(half3(avgLuma), color.rgb, half(satBoost));

    // Soft luminance cap — prevent blown-out whites from washing out the glow.
    float powerCap = 0.95;
    if (maxLuma > powerCap) { color.rgb *= half(powerCap / maxLuma); }

    // Emission scalar — controls raw brightness before fade.
    color.rgb *= half(intensity * 2.2);
    color.rgb  = max(color.rgb, half3(0.0));

    // Outer fade envelope: per-axis normalization so every rim reaches alpha 0 at the texture edge
    // (fixes top/bottom “hard shelf” vs smooth sides).
    float cap               = haloScale - 1.0;
    float capSafe           = max(cap, 0.001);
    // Left/right ribbons ~30% narrower than unified cap (1/0.7 ≈ 1.43). Top/bottom unchanged.
    const float sideTight   = 1.0f / 0.7f;
    float nxEff             = saturate(bx / max(capSafe / sideTight, 1e-4));
    // Narrower ribbon above/below screen than lateral wings (>1 ⇒ faster saturation).
    const float tbTight = 1.42f;
    float nyEff             = saturate(by / max(capSafe / tbTight, 1e-4));
    float normalizedDist    = max(nxEff, nyEff);
    float t                 = 1.0 - normalizedDist;
    t                       = t * t * (3.0 - 2.0 * t);
    // Slightly sharper falloff along top/bottom so the band looks thinner — sides stay softer.
    float gamma             = mix(2.05, 2.55, topBottomDominant);
    float fade              = pow(max(t, 0.0), gamma);

    // Premultiplied RGBA: avoids dark fringe when RealityKit composites (straight alpha glow smears RGB at low A).
    half  a                 = half(fade);
    half3 premul            = color.rgb * a;

    half4 currPM            = half4(premul, a);
    half4 prevPM            = prevTex.sample(s, in.uv);
    float frameMix          = 0.12f + temporalReachB;
    half4 blended           = mix(prevPM, currPM, half(frameMix));

    half softZero           = smoothstep(half(0.0), half(0.004), blended.a);
    return half4(blended.rgb * softZero, blended.a * softZero);
}
