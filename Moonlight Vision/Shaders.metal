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

// MARK: - Structures

struct ColorEnhancementUniforms {
    float saturation;
    float contrast;
    float warmth;
    float padding1;
};

// Shader-side HDR frame parameters — describes the incoming video signal.
// Swift side must match this layout exactly (all uint/float, no Bool).
struct ShaderHDRParams {
    uint  is10Bit;          // 1 = 10-bit source, 0 = 8-bit
    uint  isFullRange;      // 1 = full range (0-255/0-1023), 0 = limited (16-235/64-940)
    uint  isPQ;             // 1 = SMPTE ST.2084 PQ transfer function
    uint  matrixType;       // 0 = BT.709, 1 = BT.2020, 2 = BT.601/SMPTE-C
    uint  primariesType;    // 0 = BT.709, 1 = BT.2020, 2 = SMPTE-C
    float edrHeadroom;      // Live UIScreen.currentEDRHeadroom — tone map ceiling
};

// User-facing HDR grading parameters.
struct FullHDRParams {
    float boost;        // Linear luminance multiplier (1.0 = neutral)
    float contrast;     // Luma-preserved contrast (1.0 = neutral)
    float saturation;   // Color saturation (1.0 = neutral)
    float brightness;   // Additive brightness offset (0.0 = neutral)
    float pqExposure;   // PQ-only exposure trim (1.0 = neutral); ignored for SDR
    int   mode;         // Reserved for future use
};

struct CopyVertexOut {
    float4 position [[position]];
    float2 uv;
};

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
// Apple's display pipeline applies a 1.961 gamma for Rec.709 video to match
// AVSampleBufferDisplayLayer behavior. Using this exact value ensures SDR streams
// look identical to what Apple's own system player would render on Vision Pro.
inline float3 sdrToLinear(float3 c) {
    return pow(clamp(c, 0.0, 1.0), float3(1.961));
}

// MARK: - YUV Decode Functions
// Six variants covering all combinations of (BT.709 / BT.2020 / BT.601) × (limited / full range).
// 10-bit and 8-bit are handled by the is10Bit flag — scale factors differ.
// Coefficients derived from ITU-R BT.709-6, BT.2020-2, and BT.601-7.

inline float3 decode709VideoRange(float y, float2 uv, bool is10Bit) {
    float yOff   = is10Bit ? (64.0  / 1023.0) : (16.0  / 255.0);
    float uvCtr  = is10Bit ? (512.0 / 1023.0) : (128.0 / 255.0);
    float yScale = is10Bit ? (1023.0 / 876.0) : (255.0 / 219.0);
    float luma = max(y - yOff, 0.0) * yScale;
    float cb = uv.x - uvCtr;
    float cr = uv.y - uvCtr;
    return float3(
        luma + 1.79274107 * cr,
        luma - 0.21324861 * cb - 0.53290933 * cr,
        luma + 2.11240179 * cb
    );
}

inline float3 decode709FullRange(float y, float2 uv, bool is10Bit) {
    float uvCtr = is10Bit ? (512.0 / 1023.0) : (128.0 / 255.0);
    float luma  = clamp(y, 0.0, 1.0);
    float cb = uv.x - uvCtr;
    float cr = uv.y - uvCtr;
    return float3(
        luma + 1.5748   * cr,
        luma - 0.187324 * cb - 0.468124 * cr,
        luma + 1.8556   * cb
    );
}

inline float3 decode2020VideoRange(float y, float2 uv, bool is10Bit) {
    float yOff   = is10Bit ? (64.0  / 1023.0) : (16.0  / 255.0);
    float uvCtr  = is10Bit ? (512.0 / 1023.0) : (128.0 / 255.0);
    float yScale = is10Bit ? (1023.0 / 876.0) : (255.0 / 219.0);
    float luma = max(y - yOff, 0.0) * yScale;
    float cb = uv.x - uvCtr;
    float cr = uv.y - uvCtr;
    return float3(
        luma + 1.67867411 * cr,
        luma - 0.18732610 * cb - 0.65042432 * cr,
        luma + 2.14177232 * cb
    );
}

inline float3 decode2020FullRange(float y, float2 uv, bool is10Bit) {
    float uvCtr = is10Bit ? (512.0 / 1023.0) : (128.0 / 255.0);
    float luma  = clamp(y, 0.0, 1.0);
    float cb = uv.x - uvCtr;
    float cr = uv.y - uvCtr;
    return float3(
        luma + 1.4746    * cr,
        luma - 0.164553  * cb - 0.571353  * cr,
        luma + 1.8814    * cb
    );
}

inline float3 decode601VideoRange(float y, float2 uv, bool is10Bit) {
    float yOff   = is10Bit ? (64.0  / 1023.0) : (16.0  / 255.0);
    float uvCtr  = is10Bit ? (512.0 / 1023.0) : (128.0 / 255.0);
    float yScale = is10Bit ? (1023.0 / 876.0) : (255.0 / 219.0);
    float luma = max(y - yOff, 0.0) * yScale;
    float cb = uv.x - uvCtr;
    float cr = uv.y - uvCtr;
    return float3(
        luma + 1.596027  * cr,
        luma - 0.391762  * cb - 0.812968  * cr,
        luma + 2.017232  * cb
    );
}

inline float3 decode601FullRange(float y, float2 uv, bool is10Bit) {
    float uvCtr = is10Bit ? (512.0 / 1023.0) : (128.0 / 255.0);
    float luma  = clamp(y, 0.0, 1.0);
    float cb = uv.x - uvCtr;
    float cr = uv.y - uvCtr;
    return float3(
        luma + 1.40200   * cr,
        luma - 0.344136  * cb - 0.714136  * cr,
        luma + 1.77200   * cb
    );
}

// Dispatch to the correct YUV decoder based on matrix and range flags.
inline float3 decodeYUV(float y, float2 uv, constant ShaderHDRParams& p) {
    bool b10  = (p.is10Bit    == 1u);
    bool full = (p.isFullRange == 1u);
    if (p.matrixType == 1u) {
        return full ? decode2020FullRange(y, uv, b10) : decode2020VideoRange(y, uv, b10);
    } else if (p.matrixType == 2u) {
        return full ? decode601FullRange(y, uv, b10)  : decode601VideoRange(y, uv, b10);
    } else {
        return full ? decode709FullRange(y, uv, b10)  : decode709VideoRange(y, uv, b10);
    }
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

// Apply Uchimura per luma channel to preserve chromaticity (avoids hue twist).
// edrCeiling is the live display EDR headroom passed from Swift each frame.
inline float3 uchimuraToneMap(float3 colorP3, float edrCeiling) {
    // Clamp ceiling to a reasonable range — headroom can spike on some displays.
    float P = clamp(edrCeiling, 1.2, 6.0);
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

// MARK: - OLED Toe Lift
// Micro-OLED displays achieve true black (zero emission), so lifting near-black values
// reveals shadow detail that would appear milky on an LCD.
// The lift is subtle: values above 0.05 are completely unaffected.
inline float3 oledToeLift(float3 color) {
    float3 lifted = color + 0.018 * (1.0 - smoothstep(0.0, 0.05, color));
    return max(lifted, float3(0.0));
}

// MARK: - Luma-Preserved Color Grading
// Contrast pivots around the current luma value (not a fixed 0.5) to avoid
// per-channel hue rotation and black-level drift in HDR content.
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

    if (p.isPQ == 1u) {
        // --- PQ / HDR path ---
        // 1. PQ decode → absolute nits
        float3 nits = pqToNits(clamp(rgb_raw, 0.0, 1.0));

        // 2. Scale to EDR units relative to 203-nit reference white (BT.2408)
        float3 edr = nits / PQ_REFERENCE_WHITE_NITS;

        // 3. Gamut: BT.2020 → Display P3 (or BT.709 → Display P3 if 709 primaries)
        bool use2020 = (p.primariesType == 1u) || (p.matrixType == 1u);
        float3 colorP3 = use2020
            ? max(BT2020_TO_DISPLAYP3 * edr, float3(0.0))
            : max(BT709_TO_DISPLAYP3  * edr, float3(0.0));

        // 4. User grading (luma-preserved, no hard clamp — preserves HDR headroom)
        float3 lumaW = use2020 ? kRec2020Luma : kDisplayP3Luma;
        float radialSat = radialSaturationScale(uv);
        float effectiveSat = enh.saturation * full.saturation * radialSat;
        colorP3 = lumaPreservedGrading(colorP3, effectiveSat, enh.contrast * full.contrast, enh.warmth, lumaW);

        // 5. User exposure trim (PQ only — does not affect SDR streams)
        colorP3 *= max(full.boost, 0.0);
        colorP3 += max(full.brightness, 0.0);
        colorP3 *= max(full.pqExposure, 0.0);

        // 6. Uchimura tone map against live EDR headroom
        colorP3 = uchimuraToneMap(colorP3, p.edrHeadroom);

        // 7. OLED toe lift — safe to do after tone mapping
        colorP3 = oledToeLift(colorP3);

        finalColor = colorP3;

    } else {
        // --- SDR path ---
        // 1. De-gamma using Apple's 1.961 curve (matches AVSampleBufferDisplayLayer)
        float3 linear = sdrToLinear(clamp(rgb_raw, 0.0, 1.0));

        // 2. Gamut map to Display P3 linear
        float3 colorP3 = sdrPrimariesToDisplayP3(linear, p);

        // 3. User grading (clamped — SDR must stay in [0, 1])
        float radialSat = radialSaturationScale(uv);
        float effectiveSat = enh.saturation * full.saturation * radialSat;
        colorP3 = lumaPreservedGradingSDR(colorP3, effectiveSat, enh.contrast * full.contrast, enh.warmth);

        colorP3 *= max(full.boost, 0.0);
        colorP3 += max(full.brightness, 0.0);

        finalColor = clamp(colorP3, 0.0, 1.0);
    }

    // Safety ceiling — prevents any runaway value from blowing out the display.
    return min(finalColor, float3(20.0));
}

// MARK: - RealityKit Fragment Shaders (Curved + Flat renderers)

fragment half4 copyFragmentShaderHDR_EDR(
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

fragment half4 copyFragmentShaderHEVC_EDR(
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

// MARK: - UIKit Fragment Shaders (Classic renderer — with shader-based rounded corners)

fragment half4 copyFragmentShaderHDR_EDR_UIKit(
    CopyVertexOut in [[stage_in]],
    texture2d<float> yTex   [[texture(0)]],
    texture2d<float> uvTex  [[texture(1)]],
    constant ShaderHDRParams         &params [[buffer(0)]],
    constant FullHDRParams           &full   [[buffer(1)]],
    constant ColorEnhancementUniforms &enh   [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    // Shader-based rounded corner clipping (UIKit renderer has no SwiftUI clipShape).
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

fragment half4 copyFragmentShaderHEVC_EDR_UIKit(
    CopyVertexOut in [[stage_in]],
    texture2d<half> rgbTex [[texture(0)]],
    constant ShaderHDRParams         &params [[buffer(0)]],
    constant FullHDRParams           &full   [[buffer(1)]],
    constant ColorEnhancementUniforms &enh   [[buffer(2)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    // Shader-based rounded corner clipping.
    float2 texSize = float2(rgbTex.get_width(), rgbTex.get_height());
    float2 pixPos  = in.uv * texSize;
    float2 center  = pixPos - (texSize * 0.5);
    float  dist    = roundedRectSDF(center, texSize * 0.5, 16.0);
    if (dist > 0.0) { discard_fragment(); }

    float3 rgb = float3(rgbTex.sample(s, in.uv).rgb);

    float3 finalColor = processFrame(rgb, in.uv, params, full, enh);
    return half4(half3(finalColor), 1.0h);
}
