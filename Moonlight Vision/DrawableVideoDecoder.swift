//
//  DrawableVideoDecoder.swift
//  Moonlight
//
//  Created by tht7 on 30/12/2024. Updated 12/09/2025 by NeoVector X
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal
import MetalKit
import QuartzCore
import RealityKit
import SwiftUI
import UIKit
import VideoToolbox
import CoreFoundation
import simd

// Add these constants after your existing constants
let kCVPixelBufferYCbCrMatrixKey = "YCbCrMatrix" as CFString
let kCVPixelBufferColorPrimariesKey = "ColorPrimaries" as CFString
let kCVPixelBufferTransferFunctionKey = "TransferFunction" as CFString

struct HDRParams {
    var boost: Float
    var contrast: Float
    var saturation: Float
    var brightness: Float
    var pqExposure: Float  // PQ-only exposure trim; 1.0 = neutral
    var mode: Int32
    /// Bit 0 (`1`): Reference HDR — minimal client grading (PQ + gamut + tone map only). See `Shaders.metal` `FullHDRParams.hdrGradeFlags`.
    var hdrGradeFlags: UInt32 = 0
}

/// ChromaHalo / Chromosphere: halo drawable / RealityKit texture size is full frame `>> mipShift`.
/// Rim pass samples **mip 0**; a **separable 13-tap blur** on the halo buffer spreads that into a smooth wash (GPU-heavy, quality-first).
enum ChromaHaloDownsample {
    /// `1` → half resolution per axis (vs stream). Pairs with separable blur for Hue-like gradients.
    static let mipShift: Int = 1
}

private let chromaHaloSourceMipLevel = 0

/// Multiplies halo texel step in separable blur (wider bleed ≈ Ambilight wall wash).
private let chromaHaloAmbilightBlurSpread: Float = 1.45

private struct ColorEnhancementUniforms {
    var saturation: Float
    var contrast: Float
    var warmth: Float
    var padding1: Float
}

// Must match ShaderHDRParams in Shaders.metal exactly (field order + alignment).
// Metal float3x3 is stored as 3 × float4 columns (48 bytes); float3 is 16 bytes (padded).
private struct ShaderHDRParams {
    var isPQ:           UInt32         // 1 = PQ/HDR path, 0 = SDR / extended
    var primariesType: UInt32         // 0=709/P3, 1=2020, 2=SMPTE-C (gamut selector)
    var extendedScene: UInt32        // 1 = Moonlight HDR + non-PQ (matches `Shaders.metal` ShaderHDRParams.extendedScene)
    var reserved0:      UInt32 = 0
    var edrHeadroom:    Float          // Tone map ceiling (2.0 on visionOS)
    var pad:            Float = 0
    var alignPad:       SIMD2<Float> = .zero
    /// Sunshine maxCLL / maxFALL (nits); 0 = omit CLL-driven shoulder (see `Shaders.metal` hdrUchimuraShoulderP).
    var maxContentNits: Float = 0
    var maxFrameAvgNits: Float = 0
    var padHdrMeta:     SIMD2<Float> = .zero
    var yuvMatrix:      simd_float3x3  // Precomputed YUV→RGB matrix (CPU-selected)
    var yuvOffset:      simd_float3    // Subtract before matrix multiply
}

// Build the YUV→RGB matrix and offset for the given format on the CPU.
// Shared by DrawableVideoDecoder (RealityKit path) and MetalVideoDecoderRenderer (UIKit path).
// Eliminates all if/else branching in the fragment shader.
// Coefficients from ITU-R BT.709-6, BT.2020-2, BT.601-7.
func buildYUVMatrix(matrixType: UInt32, isFullRange: Bool, is10Bit: Bool) -> (simd_float3x3, simd_float3) {
    let yBlack:  Float = isFullRange ? 0.0        : (is10Bit ? 64.0  / 1023.0 : 16.0  / 255.0)
    let uvCenter: Float =               is10Bit ? 512.0 / 1023.0 : 128.0 / 255.0
    let yScale:  Float = isFullRange ? 1.0        : (is10Bit ? 1023.0 / 876.0  : 255.0 / 219.0)

    let offset = simd_float3(yBlack, uvCenter, uvCenter)

    let m: simd_float3x3
    switch matrixType {
    case 1: // BT.2020
        if isFullRange {
            m = simd_float3x3(columns: (
                simd_float3( 1.0,      1.0,      1.0     ),
                simd_float3( 0.0,     -0.164553, 1.8814  ),
                simd_float3( 1.4746,  -0.571353, 0.0     )
            ))
        } else {
            let s = yScale
            m = simd_float3x3(columns: (
                simd_float3( s,        s,        s       ),
                simd_float3( 0.0,     -0.18732610 * s, 2.14177232 * s ),
                simd_float3( 1.67867411 * s, -0.65042432 * s, 0.0 )
            ))
        }
    case 2: // BT.601 / SMPTE-C
        if isFullRange {
            m = simd_float3x3(columns: (
                simd_float3( 1.0,      1.0,      1.0     ),
                simd_float3( 0.0,     -0.344136, 1.77200 ),
                simd_float3( 1.40200, -0.714136, 0.0     )
            ))
        } else {
            let s = yScale
            m = simd_float3x3(columns: (
                simd_float3( s,        s,        s       ),
                simd_float3( 0.0,     -0.391762 * s, 2.017232 * s ),
                simd_float3( 1.596027 * s, -0.812968 * s, 0.0 )
            ))
        }
    default: // BT.709
        if isFullRange {
            m = simd_float3x3(columns: (
                simd_float3( 1.0,      1.0,      1.0     ),
                simd_float3( 0.0,     -0.187324, 1.8556  ),
                simd_float3( 1.5748,  -0.468124, 0.0     )
            ))
        } else {
            let s = yScale
            m = simd_float3x3(columns: (
                simd_float3( s,        s,        s       ),
                simd_float3( 0.0,     -0.21324861 * s, 2.11240179 * s ),
                simd_float3( 1.79274107 * s, -0.53290933 * s, 0.0 )
            ))
        }
    }
    return (m, offset)
}

// Must match FullHDRParams in Shaders.metal exactly.
private struct ShaderFullHDRParams {
    var boost:       Float
    var contrast:    Float
    var saturation:  Float
    var brightness:  Float
    var pqExposure:  Float
    var mode:        Int32
    var hdrGradeFlags: UInt32
}

/// Buffer 0 for TestFlight SDR fragments (`copyFragmentShaderHDR_EDR` / `_HEVC_EDR`) — matches `LegacySDRFrameParams` in Shaders.metal.
private struct LegacySDRFrameParams {
    var presetIndex: UInt32 = 0
    var isPQ: UInt32
    var isBT2020Matrix: UInt32
    var isBT2020Primaries: UInt32
}

/// Buffer 1 for legacy SDR fragments — matches `LegacySDRFullParams` in Shaders.metal (no pqExposure).
private struct LegacySDRFullParams {
    var boost: Float
    var contrast: Float
    var saturation: Float
    var brightness: Float
    var mode: Int32
}

let kCVImageBufferYCbCrMatrix_ITU_R_2020 = "ITU_R_2020" as CFString
let kCVImageBufferColorPrimaries_ITU_R_2020 = "ITU_R_2020" as CFString
let kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ = "SMPTE_ST_2084_PQ" as CFString

let kCVImageBufferColorPrimaries_ITU_R_709_2 = "ITU_R_709_2" as CFString
let kCVImageBufferYCbCrMatrix_ITU_R_709_2 = "ITU_R_709_2" as CFString

// MARK: - VideoDecoderRenderer

@objc
class DrawableVideoDecoder: NSObject, AnyVideoDecoderRenderer {
    // MARK: - Properties

    private var callbacks: ConnectionCallbacks
    private var streamAspectRatio: Float

    let callbackToRender: @MainActor (TextureResource.DrawableQueue, TextureResource.DrawableQueue?, (Int, Int)?) -> Void
    private var hdrSettingsProvider: (() -> HDRParams)? = nil

    /// Format and frame info
    private var videoFormat: Int32 = 0
    private var frameRate: Int32 = 0
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    private var metalFormat: MTLPixelFormat
    private var decodingFormat: OSType

    /// If true, we'll do pacing logic in displayLink
    private var framePacing: Bool = false

    /// Store parameter set data for H.264 / HEVC
    private var parameterSetBuffers: [[UInt8]] = []

    /// HDR metadata
    private var masteringDisplayColorVolume: Data?
    private var contentLightLevelInfo: Data?

    /// Video format description, used when creating sample buffers
    private var formatDesc: CMVideoFormatDescription?

    /// Display link for pacing decode submissions
    private var displayLink: CADisplayLink?

    private let texture: TextureResource
    private var outTexture: MTLTexture?
    private var region = MTLRegionMake2D(0, 0, 1000, 1000)
    var textureCache: CVMetalTextureCache?
    var drawableQueue: TextureResource.DrawableQueue?

    var session: VTDecompressionSession?
    var decoderCallback: VTDecompressionOutputCallbackRecord

    // Limits GPU command buffer depth to 3 in-flight frames.
    // Prevents memory pressure and watchdog kills when the decoder runs faster than the GPU.
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    lazy var mtlDevice: MTLDevice = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError()
        }
        return device
    }()

    private lazy var commandQueue: MTLCommandQueue? = mtlDevice.makeCommandQueue()

    private var imagePlaneVertexBuffer: MTLBuffer?

    private var hdrEnabled: Bool
    private var hdrMetadata: SS_HDR_METADATA = SS_HDR_METADATA()

    private var enhancementsProvider: (() -> (Float, Float, Float))? = nil

    private var copyPipelineState: MTLRenderPipelineState?
    private var copyPipelineFormat: MTLPixelFormat?
    private var copyPipelineStateYUV: MTLRenderPipelineState?
    private var lastCopyFragment: String?

    // ChromaHalo: downsampled drawable queue for the edge bloom layer
    var chromaHaloQueue: TextureResource.DrawableQueue?
    private var chromaHaloRimPipelineState: MTLRenderPipelineState?
    private var chromaHaloBlurHPipelineState: MTLRenderPipelineState?
    private var chromaHaloBlurVPipelineState: MTLRenderPipelineState?
    /// Ping-pong scratch: rim → A, horizontal blur → B, vertical blur (+ temporal) → drawable.
    private var chromaHaloScratchA: MTLTexture?
    private var chromaHaloScratchB: MTLTexture?
    private var prevChromaHaloTexture: MTLTexture?

    private var firstFrameEmitted = false

    private static let ambientEngine: AmbientLightEngine? = AmbientLightEngine()

    // Flag to control whether we spawn the ambient analysis task (zone colors for dome modes)
    var isReactiveDimmingEnabled: Bool = false
    // ChromaHalo intensity for edge bloom (0.0 = off, 1.0 = normal)
    var chromaHaloIntensity: Float = 0.0
    // ChromaHalo scale (how much larger than video the halo mesh is)
    /// Geometric margin for bloom vs display — keep equal to `_CurvedDisplayStreamView.chromosphereDiameterScale`.
    var chromaHaloScale: Float = 1.55

    // MARK: - Initialization

    init(
        texture: TextureResource,
        callbacks: ConnectionCallbacks,
        aspectRatio: Float,
        useFramePacing: Bool,
        enableHDR: Bool = false,
        hdrSettingsProvider: (() -> HDRParams)? = nil,
        enhancementsProvider: (() -> (Float, Float, Float))? = nil,
        callbackToRender: @MainActor @escaping (TextureResource.DrawableQueue, TextureResource.DrawableQueue?, (Int, Int)?) -> Void
    ) {
        metalFormat = enableHDR ? .rgba16Float : .bgra8Unorm_srgb

        // Format setup based on HDR
        decodingFormat = enableHDR ?
            kCVPixelFormatType_64RGBAHalf :
            kCVPixelFormatType_Lossless_32BGRA

        self.texture = texture
        self.callbacks = callbacks
        streamAspectRatio = aspectRatio
        framePacing = useFramePacing
        hdrEnabled = enableHDR
        self.hdrSettingsProvider = hdrSettingsProvider
        self.enhancementsProvider = enhancementsProvider
        self.callbackToRender = callbackToRender

        decoderCallback = VTDecompressionOutputCallbackRecord()
        decoderCallback.decompressionOutputCallback = { decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
            let mySelf = Unmanaged<DrawableVideoDecoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
            mySelf.decompressionOutputCallback(
                decompressionOutputRefCon: decompressionOutputRefCon,
                sourceFrameRefCon: sourceFrameRefCon,
                status: status,
                infoFlags: infoFlags,
                imageBuffer: imageBuffer,
                presentationTimeStamp: presentationTimeStamp,
                presentationDuration: presentationDuration
            )
        }

        super.init()
        decoderCallback.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()
    }

    func decompressionOutputCallback(
        decompressionOutputRefCon _: UnsafeMutableRawPointer?,
        sourceFrameRefCon _: UnsafeMutableRawPointer?,
        status _: OSStatus,
        infoFlags _: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp _: CMTime,
        presentationDuration _: CMTime?
    ) {
        guard let imageBuffer = imageBuffer else { return }

        // Back-pressure: drop the frame silently if 3 frames are already queued on the GPU.
        if inflightSemaphore.wait(timeout: .now()) != .success { return }

        autoreleasepool {
            renderFrame(imageBuffer: imageBuffer)
        }
    }

    private func renderFrame(imageBuffer: CVImageBuffer) {
        guard
            let commandBuffer = commandQueue?.makeCommandBuffer(),
            let textureCache  = textureCache
        else {
            inflightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        let pf         = CVPixelBufferGetPixelFormatType(imageBuffer)
        let planeCount = CVPixelBufferGetPlaneCount(imageBuffer)

        // --- PQ detection (ST.2084) ---
        // 1) Prefer attachment on the decoded pixel buffer.
        // 2) Else use transfer from CMVideoFormatDescription (must match AV1 sequence header — see AV1Parser tcMap).
        //    VideoToolbox often omits kCVImageBufferTransferFunctionKey on the buffer even when the format desc is correct.
        var isPQ = false
        if let tfVal = CVBufferGetAttachment(imageBuffer, kCVImageBufferTransferFunctionKey, nil)?.takeUnretainedValue(),
           CFGetTypeID(tfVal) == CFStringGetTypeID() {
            isPQ = CFEqual(tfVal as! CFString, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)
        }
        if !isPQ, let fd = formatDesc,
           let tfAny = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction) {
            if CFGetTypeID(tfAny) == CFStringGetTypeID() {
                isPQ = CFEqual(tfAny as! CFString, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)
            }
        }

        // --- Primaries Detection ---
        var primariesFromAttachment = false
        var primariesType: UInt32 = 0  // 0=709, 1=2020, 2=SMPTE-C
        if let primVal = CVBufferGetAttachment(imageBuffer, kCVImageBufferColorPrimariesKey, nil)?.takeUnretainedValue(),
           CFGetTypeID(primVal) == CFStringGetTypeID() {
            primariesFromAttachment = true
            let prim = primVal as! CFString
            if      CFEqual(prim, kCVImageBufferColorPrimaries_ITU_R_2020)  { primariesType = 1 }
            else if CFEqual(prim, "SMPTE_C" as CFString)                    { primariesType = 2 }
            // else stays 0 (BT.709)
        } else {
            // Infer BT.2020 only for PQ HDR without tags; 10‑bit SDR without primaries stays 709 (avoids green cast).
            primariesType = (hdrEnabled && pixelFormatIs10Bit(pf) && isPQ) ? 1 : 0
        }

        // --- Matrix Detection ---
        var matrixFromAttachment = false
        var matrixType: UInt32 = 0  // 0=709, 1=2020, 2=601
        if let mtxVal = CVBufferGetAttachment(imageBuffer, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue(),
           CFGetTypeID(mtxVal) == CFStringGetTypeID() {
            matrixFromAttachment = true
            let mtx = mtxVal as! CFString
            if      CFEqual(mtx, kCVImageBufferYCbCrMatrix_ITU_R_2020)  { matrixType = 1 }
            else if CFEqual(mtx, "ITU_R_601_4" as CFString)             { matrixType = 2 }
            // else stays 0 (BT.709)
        } else {
            matrixType = (hdrEnabled && pixelFormatIs10Bit(pf) && isPQ) ? 1 : 0
        }

        // PQ tag but no colorimetry attachments is common for Windows HDR desktop in Moonlight — treat as non-PQ.
        if isPQ && hdrEnabled && !matrixFromAttachment && !primariesFromAttachment {
            isPQ = false
            matrixType = 0
            primariesType = 0
        }
        // PQ with explicit BT.709 primaries + 709 matrix is usually SDR-in-HDR container, not PQ code values.
        if isPQ && primariesFromAttachment && matrixFromAttachment && primariesType == 0 && matrixType == 0 {
            isPQ = false
        }

        let is10Bit    = pixelFormatIs10Bit(pf)    ? UInt32(1) : 0
        let isFullRange = pixelFormatIsFullRange(pf) ? UInt32(1) : 0

        if hdrEnabled { updateHDRMetadata() }

        // --- Texture Format Selection ---
        // When HDR is off, use the same CV→Metal mapping as pre–HDR-overhaul builds (and as
        // MetalVideoDecoderRenderer): 10-bit SDR stays on r16/rg16 (or packed YCbCr), not r8/rg8.
        var isBiPlanar  = false
        var yFormat:    MTLPixelFormat = .invalid
        var cbcrFormat: MTLPixelFormat = .invalid

        if planeCount >= 2 {
            let srcMetalFormats = CVMetalHelpers.getTextureTypesForFormat(pf)
            if srcMetalFormats.count > 0 { yFormat = srcMetalFormats[0] }
            if srcMetalFormats.count > 1 { cbcrFormat = srcMetalFormats[1] }
            isBiPlanar = (cbcrFormat != .invalid)

            if hdrEnabled {
                yFormat = .r16Unorm
                cbcrFormat = .rg16Unorm
                isBiPlanar = true
            }
        }

        if !firstFrameEmitted {
            let fmtStr = CVMetalHelpers.coreVideoPixelFormatToStr[pf] ?? "\(pf)"
            let tfDesc: String = {
                guard let fd = formatDesc,
                      let tfAny = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction)
                else { return "-" }
                if let s = tfAny as? String { return s }
                if CFGetTypeID(tfAny) == CFStringGetTypeID() { return (tfAny as! CFString) as String }
                return "-"
            }()
            let cllLog = hdrEnabled ? " maxCLL=\(hdrMetadata.maxContentLightLevel) maxFALL=\(hdrMetadata.maxFrameAverageLightLevel)" : ""
            print("[DrawableVideoDecoder] PF=\(fmtStr), planes=\(planeCount), hdr=\(hdrEnabled), isPQ=\(isPQ), tfDesc=\(tfDesc), fullRange=\(isFullRange==1), 10bit=\(is10Bit==1), matrix=\(matrixType), primaries=\(primariesType)\(cllLog)")
        }

        guard let drawable = try? drawableQueue?.nextDrawable() else {
            commandBuffer.commit()
            return
        }

        // SDR uses default TestFlight entry points; HDR uses separate Metal symbols (never shares SDR shader body).
        let fragment: String = {
            if hdrEnabled {
                return isBiPlanar ? "copyFragmentShaderHDR_HDRUnified" : "copyFragmentShaderHEVC_HDRUnified"
            }
            return isBiPlanar ? "copyFragmentShaderHDR_EDR" : "copyFragmentShaderHEVC_EDR"
        }()

        if isBiPlanar {
            if copyPipelineStateYUV == nil || lastCopyFragment != fragment {
                copyPipelineStateYUV = buildCopyPipeline(fragment: fragment)
                lastCopyFragment = fragment
                guard copyPipelineStateYUV != nil else {
                    print("DrawableVideoDecoder: Failed to build YUV pipeline")
                    commandBuffer.commit()
                    return
                }
            }
        } else {
            if copyPipelineState == nil || lastCopyFragment != fragment {
                copyPipelineState = buildCopyPipeline(fragment: fragment)
                lastCopyFragment = fragment
                guard copyPipelineState != nil else {
                    print("DrawableVideoDecoder: Failed to build single-plane pipeline")
                    commandBuffer.commit()
                    return
                }
            }
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture    = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction  = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            return
        }

        if isBiPlanar {
            let w0 = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
            let h0 = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
            let w1 = CVPixelBufferGetWidthOfPlane(imageBuffer, 1)
            let h1 = CVPixelBufferGetHeightOfPlane(imageBuffer, 1)

            var yRef:    CVMetalTexture?
            var cbcrRef: CVMetalTexture?
            let r0 = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, nil, yFormat,    w0, h0, 0, &yRef)
            let r1 = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, nil, cbcrFormat, w1, h1, 1, &cbcrRef)
            guard r0 == 0, r1 == 0,
                  let yTex   = yRef.flatMap(CVMetalTextureGetTexture),
                  let uvTex  = cbcrRef.flatMap(CVMetalTextureGetTexture) else {
                renderEncoder.endEncoding()
                commandBuffer.commit()
                return
            }
            renderEncoder.setRenderPipelineState(copyPipelineStateYUV!)
            renderEncoder.setFragmentTexture(yTex,  index: 0)
            renderEncoder.setFragmentTexture(uvTex, index: 1)
        } else {
            var imgRef: CVMetalTexture?
            let w = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
            let h = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
            let srcFmt = CVMetalHelpers.getTextureTypesForFormat(pf)[0]
            let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, nil, srcFmt, w, h, 0, &imgRef)
            guard result == 0, let srcTex = imgRef.flatMap(CVMetalTextureGetTexture) else {
                renderEncoder.endEncoding()
                commandBuffer.commit()
                return
            }
            renderEncoder.setRenderPipelineState(copyPipelineState!)
            renderEncoder.setFragmentTexture(srcTex, index: 0)
        }

        // Buffer 0: ShaderHDRParams — frame signal description
        // visionOS has fixed EDR headroom (Vision Pro's micro-OLED peak capability).
        // On other platforms, query UIScreen dynamically.
        // Only use HDR slider values when HDR is actually enabled.
        let userParams: HDRParams = hdrEnabled
            ? (hdrSettingsProvider?() ?? HDRParams(boost: 1.0, contrast: 1.0, saturation: 1.0, brightness: 0.0, pqExposure: 1.0, mode: 0))
            : HDRParams(boost: 1.0, contrast: 1.0, saturation: 1.0, brightness: 0.0, pqExposure: 1.0, mode: 0)

        // Always compute once so first-frame logging (and HDR shader params) share the same binding.
        let edrHeadroom: Float = {
            #if os(visionOS)
            return 2.0
            #else
            let raw = UIScreen.main.currentEDRHeadroom
            return Float(raw > 1.0 ? raw : UIScreen.main.potentialEDRHeadroom)
            #endif
        }()

        if hdrEnabled {
            let is10BitBool = is10Bit == 1
            let isFullRangeBool = isFullRange == 1
            let (yuvMatrix, yuvOffset) = buildYUVMatrix(matrixType: matrixType, isFullRange: isFullRangeBool, is10Bit: is10BitBool)
            let extendedScene: UInt32 = (hdrEnabled && !isPQ) ? 1 : 0
            var shaderHDR = ShaderHDRParams(
                isPQ:              isPQ ? 1 : 0,
                primariesType:     primariesType,
                extendedScene:     extendedScene,
                reserved0:         0,
                edrHeadroom:       edrHeadroom,
                pad:               0,
                alignPad:          .zero,
                maxContentNits:    Float(hdrMetadata.maxContentLightLevel),
                maxFrameAvgNits:   Float(hdrMetadata.maxFrameAverageLightLevel),
                padHdrMeta:        .zero,
                yuvMatrix:         yuvMatrix,
                yuvOffset:         yuvOffset
            )
            renderEncoder.setFragmentBytes(&shaderHDR, length: MemoryLayout<ShaderHDRParams>.size, index: 0)

            var fullParams = ShaderFullHDRParams(
                boost:      userParams.boost,
                contrast:   userParams.contrast,
                saturation: userParams.saturation,
                brightness: userParams.brightness,
                pqExposure: userParams.pqExposure,
                mode:       userParams.mode,
                hdrGradeFlags: userParams.hdrGradeFlags
            )
            renderEncoder.setFragmentBytes(&fullParams, length: MemoryLayout<ShaderFullHDRParams>.size, index: 1)
        } else {
            var legacyFrame = LegacySDRFrameParams(
                presetIndex: 0,
                isPQ: isPQ ? 1 : 0,
                isBT2020Matrix: matrixType == 1 ? 1 : 0,
                isBT2020Primaries: primariesType == 1 ? 1 : 0
            )
            renderEncoder.setFragmentBytes(&legacyFrame, length: MemoryLayout<LegacySDRFrameParams>.size, index: 0)

            var legacyFull = LegacySDRFullParams(
                boost: userParams.boost,
                contrast: userParams.contrast,
                saturation: userParams.saturation,
                brightness: userParams.brightness,
                mode: userParams.mode
            )
            renderEncoder.setFragmentBytes(&legacyFull, length: MemoryLayout<LegacySDRFullParams>.size, index: 1)
        }

        // Buffer 2: ColorEnhancementUniforms — warmth / per-renderer adjustments
        let satConWarm = enhancementsProvider?() ?? (1.0, 1.0, 0.0)
        var enh = ColorEnhancementUniforms(saturation: satConWarm.0, contrast: satConWarm.1, warmth: satConWarm.2, padding1: 0)
        renderEncoder.setFragmentBytes(&enh, length: MemoryLayout<ColorEnhancementUniforms>.size, index: 2)

        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        // Mipmap generation — used by both ChromaHalo bloom and ambient zone sampling
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.generateMipmaps(for: drawable.texture)
            blitEncoder.endEncoding()
        }

        // ChromaHalo: rim (mip 0) → two rounds separable blur (Ambilight diffusion) → temporal on final V-pass.
        if chromaHaloIntensity > 0.0,
           let haloQueue = chromaHaloQueue,
           let haloDrawable = try? haloQueue.nextDrawable() {

            let sampleMip = min(chromaHaloSourceMipLevel, drawable.texture.mipmapLevelCount - 1)

            if chromaHaloRimPipelineState == nil {
                chromaHaloRimPipelineState = buildCopyPipeline(fragment: "chromaHaloRimFragment")
            }
            if chromaHaloBlurHPipelineState == nil {
                chromaHaloBlurHPipelineState = buildCopyPipeline(fragment: "chromaHaloBlurHFragment")
            }
            if chromaHaloBlurVPipelineState == nil {
                chromaHaloBlurVPipelineState = buildCopyPipeline(fragment: "chromaHaloBlurVFragment")
            }

            var didAllocatePrevChroma = false
            if prevChromaHaloTexture == nil
                || prevChromaHaloTexture!.width != haloDrawable.texture.width
                || prevChromaHaloTexture!.height != haloDrawable.texture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: haloDrawable.texture.pixelFormat,
                    width: haloDrawable.texture.width,
                    height: haloDrawable.texture.height,
                    mipmapped: false)
                desc.usage = [.shaderRead, .renderTarget]
                prevChromaHaloTexture = mtlDevice.makeTexture(descriptor: desc)
                didAllocatePrevChroma = prevChromaHaloTexture != nil
            }

            if didAllocatePrevChroma, let freshPrev = prevChromaHaloTexture {
                let clearDesc = MTLRenderPassDescriptor()
                clearDesc.colorAttachments[0].texture = freshPrev
                clearDesc.colorAttachments[0].loadAction = .clear
                clearDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                clearDesc.colorAttachments[0].storeAction = .store
                if let clearEnc = commandBuffer.makeRenderCommandEncoder(descriptor: clearDesc) {
                    clearEnc.endEncoding()
                }
            }

            ensureChromaHaloBlurScratchMatches(haloDrawable.texture)

            if let mipView = drawable.texture.makeTextureView(
                pixelFormat: drawable.texture.pixelFormat,
                textureType: .type2D,
                levels: sampleMip..<(sampleMip + 1),
                slices: 0..<1),
               let rimPS = chromaHaloRimPipelineState,
               let blurHPS = chromaHaloBlurHPipelineState,
               let blurVPS = chromaHaloBlurVPipelineState,
               let scratchA = chromaHaloScratchA,
               let scratchB = chromaHaloScratchB,
               let prevTex = prevChromaHaloTexture {

                let w = Float(scratchA.width)
                let h = Float(scratchA.height)
                var texelUV = simd_float2(
                    chromaHaloAmbilightBlurSpread / max(w, 1),
                    chromaHaloAmbilightBlurSpread / max(h, 1))

                // Pass 1 — rim → scratch A
                let passRim = MTLRenderPassDescriptor()
                passRim.colorAttachments[0].texture = scratchA
                passRim.colorAttachments[0].loadAction = .clear
                passRim.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                passRim.colorAttachments[0].storeAction = .store
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passRim) {
                    enc.setRenderPipelineState(rimPS)
                    enc.setFragmentTexture(mipView, index: 0)
                    var scale = chromaHaloScale
                    var intensity = chromaHaloIntensity
                    enc.setFragmentBytes(&scale, length: MemoryLayout<Float>.size, index: 1)
                    enc.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 2)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }

                // Pass 2 — horizontal blur A → B
                let passH = MTLRenderPassDescriptor()
                passH.colorAttachments[0].texture = scratchB
                passH.colorAttachments[0].loadAction = .clear
                passH.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                passH.colorAttachments[0].storeAction = .store
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passH) {
                    enc.setRenderPipelineState(blurHPS)
                    enc.setFragmentTexture(scratchA, index: 0)
                    enc.setFragmentBytes(&texelUV, length: MemoryLayout<simd_float2>.size, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }

                // Pass 3 — first vertical blur → scratch A (Ambilight diffusion pass 2/4)
                let passV1 = MTLRenderPassDescriptor()
                passV1.colorAttachments[0].texture = scratchA
                passV1.colorAttachments[0].loadAction = .clear
                passV1.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                passV1.colorAttachments[0].storeAction = .store
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passV1) {
                    enc.setRenderPipelineState(blurVPS)
                    enc.setFragmentTexture(scratchB, index: 0)
                    enc.setFragmentTexture(prevTex, index: 1)
                    enc.setFragmentBytes(&texelUV, length: MemoryLayout<simd_float2>.size, index: 0)
                    var vTemporalOff: UInt32 = 0
                    enc.setFragmentBytes(&vTemporalOff, length: MemoryLayout<UInt32>.size, index: 1)
                    var mixPlaceholder: Float = 0
                    enc.setFragmentBytes(&mixPlaceholder, length: MemoryLayout<Float>.size, index: 2)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }

                // Pass 4 — horizontal blur scratch A → B
                let passH2 = MTLRenderPassDescriptor()
                passH2.colorAttachments[0].texture = scratchB
                passH2.colorAttachments[0].loadAction = .clear
                passH2.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                passH2.colorAttachments[0].storeAction = .store
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passH2) {
                    enc.setRenderPipelineState(blurHPS)
                    enc.setFragmentTexture(scratchA, index: 0)
                    enc.setFragmentBytes(&texelUV, length: MemoryLayout<simd_float2>.size, index: 0)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }

                // Pass 5 — vertical blur + temporal → halo drawable
                let passV2 = MTLRenderPassDescriptor()
                passV2.colorAttachments[0].texture = haloDrawable.texture
                passV2.colorAttachments[0].loadAction = .clear
                passV2.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
                passV2.colorAttachments[0].storeAction = .store
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passV2) {
                    enc.setRenderPipelineState(blurVPS)
                    enc.setFragmentTexture(scratchB, index: 0)
                    enc.setFragmentTexture(prevTex, index: 1)
                    enc.setFragmentBytes(&texelUV, length: MemoryLayout<simd_float2>.size, index: 0)
                    var vTemporalOn: UInt32 = 1
                    enc.setFragmentBytes(&vTemporalOn, length: MemoryLayout<UInt32>.size, index: 1)
                    var mix = chromaHaloTemporalFrameMix()
                    enc.setFragmentBytes(&mix, length: MemoryLayout<Float>.size, index: 2)
                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()
                }

                if let blitEnc = commandBuffer.makeBlitCommandEncoder() {
                    blitEnc.copy(from: haloDrawable.texture, to: prevTex)
                    blitEnc.endEncoding()
                }
            }

            haloDrawable.present()
        }

        let outTextureForAmbient = drawable.texture

        commandBuffer.addCompletedHandler { _ in
            drawable.present()
        }
        commandBuffer.commit()

        if isReactiveDimmingEnabled, let engine = Self.ambientEngine {
            Task.detached {
                await engine.analyze(texture: outTextureForAmbient)
            }
        }

        if !firstFrameEmitted {
            firstFrameEmitted = true
            DispatchQueue.main.async {
                self.callbacks.videoContentShown()
                print("DrawableVideoDecoder: First frame presented (PQ=\(isPQ), primaries=\(primariesType), matrix=\(matrixType), edrHeadroom=\(edrHeadroom))")
            }
        }
    }

    // MARK: - Pixel Format Helpers

    private func pixelFormatIs10Bit(_ pf: OSType) -> Bool {
        switch pf {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10PackedBiPlanarFullRange:
            return true
        default:
            return false
        }
    }

    private func pixelFormatIsFullRange(_ pf: OSType) -> Bool {
        switch pf {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_444YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10PackedBiPlanarFullRange:
            return true
        // Studio (limited) range is fixed by the OSType. Some streams incorrectly set FullRangeVideo on the
        // CMFormatDescription; trusting that here used full-range YUV offsets on limited buffers → lifted blacks
        // and the milky HDR desktop look (PQ path and extended path both start from the same decode).
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_Lossy_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossy_422YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_422YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr10PackedBiPlanarVideoRange:
            return false
        default:
            // Match MetalVideoDecoderRenderer: unknown layouts default to studio (limited) range.
            // Relying on CMFormatDescription FullRangeVideo has produced false positives for Moonlight HDR
            // (washed desktop); only OSTypes in the explicit `true` branch above are treated as full range.
            return false
        }
    }

    func setupLowLevelTexture() {
        DispatchQueue.main.sync {
            if videoWidth == 0 || videoHeight == 0 {
                print("Tried to set up client texture without defined dimensions (\(videoWidth), \(videoHeight)) - skipping")
                return
            }

            self.drawableQueue = {
                let descriptor = TextureResource.DrawableQueue.Descriptor(
                    pixelFormat: metalFormat,
                    width: Int(videoWidth),
                    height: Int(videoHeight),
                    usage: [.renderTarget, .shaderRead],
                    // FIX: Must allocate mipmaps for them to be generated later
                    mipmapsMode: .allocateAll
                )
                do {
                    let queue = try TextureResource.DrawableQueue(descriptor)
                    queue.allowsNextDrawableTimeout = true
                    return queue
                } catch {
                    fatalError("Could not create DrawableQueue: \(error)")
                }
            }()

            // ChromaHalo: downsampled queue (see `ChromaHaloDownsample.mipShift`)
            self.chromaHaloQueue = {
                let mipShift = ChromaHaloDownsample.mipShift
                let cw = max(1, videoWidth  >> mipShift)
                let ch = max(1, videoHeight >> mipShift)
                let descriptor = TextureResource.DrawableQueue.Descriptor(
                    pixelFormat: metalFormat,
                    width: cw,
                    height: ch,
                    usage: [.renderTarget, .shaderWrite, .shaderRead],
                    mipmapsMode: .none
                )
                do {
                    let q = try TextureResource.DrawableQueue(descriptor)
                    q.allowsNextDrawableTimeout = true
                    return q
                } catch {
                    print("DrawableVideoDecoder: Could not create ChromaHalo queue: \(error)")
                    return nil
                }
            }()

            self.chromaHaloScratchA = nil
            self.chromaHaloScratchB = nil

            region = MTLRegionMake2D(0, 0, videoWidth, videoHeight)

            self.callbackToRender(self.drawableQueue!, self.chromaHaloQueue, (videoWidth, videoHeight))
        }
    }

    /// Basic setup for the decoder
    func setup(withVideoFormat videoFormat: Int32, width videoWidth: Int32, height videoHeight: Int32, frameRate: Int32) {
        self.videoFormat = videoFormat
        self.frameRate = frameRate
        self.videoWidth = Int(videoWidth)
        self.videoHeight = Int(videoHeight)
        print("DrawableVideoDecoder: setup format=\(videoFormat) \(videoWidth)x\(videoHeight)@\(frameRate)")

        // Configure cache attributes with HDR support if enabled
        let cacheAttributes: [String: Any] = [
            kCVMetalTextureCacheMaximumTextureAgeKey as String: 1,
        ]

        let textureAttributes: [String: Any] = {
            var attrs: [String: Any] = [
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight,
            ]
            if hdrEnabled {
                attrs[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            } else {
                attrs[kCVPixelBufferPixelFormatTypeKey as String] = decodingFormat
            }
            return attrs
        }()

        let res = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            cacheAttributes as CFDictionary,
            mtlDevice,
            textureAttributes as CFDictionary,
            &textureCache
        )

        if res != kCVReturnSuccess {
            print("Creating texture cache failed \(res)")
        }

        setupLowLevelTexture()
    }

    /// Start the rendering loop (via CADisplayLink)
    func start() {
        print("DrawableVideoDecoder: start() display link")
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback(_:)))
        if #available(iOS 15.0, tvOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(frameRate),
                maximum: Float(frameRate),
                preferred: Float(frameRate)
            )
        } else {
            displayLink?.preferredFramesPerSecond = Int(frameRate)
        }

        displayLink?.add(to: .main, forMode: .default)
    }

    /// Stop the rendering loop
    func stop() {
        print("DrawableVideoDecoder: stop()")
        displayLink?.invalidate()
        displayLink = nil
        
        // Invalidate VTDecompressionSession
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        
        // Clear all decoder state
        formatDesc = nil
        parameterSetBuffers.removeAll()
        masteringDisplayColorVolume = nil
        contentLightLevelInfo = nil
        
        // Clear texture cache
        textureCache = nil
        copyPipelineState = nil
        copyPipelineFormat = nil
        chromaHaloRimPipelineState = nil
        chromaHaloBlurHPipelineState = nil
        chromaHaloBlurVPipelineState = nil
        chromaHaloScratchA = nil
        chromaHaloScratchB = nil
        prevChromaHaloTexture = nil

        print("DrawableVideoDecoder: Stopped and cleaned up all state")
    }

    // MARK: - Rendering Loop

    @objc private func displayLinkCallback(_ sender: CADisplayLink) {
        var handle: VIDEO_FRAME_HANDLE?
        var du: PDECODE_UNIT?

        while LiPollNextVideoFrame(&handle, &du) {
            // Once I a new frame from the network/stream, submit it
            guard let handle = handle, let du = du else {
                continue
            }

            // (Implementation detail) DrSubmitDecodeUnit is presumably your custom decode function
            let result = DrSubmitDecodeUnit(du)
            LiCompleteVideoFrame(handle, result)

            // Frame pacing logic
            if framePacing {
                let displayRefreshRate = 1.0 / (sender.targetTimestamp - sender.timestamp)
                if displayRefreshRate >= Double(frameRate) * 0.9 {
                    // Keep one pending frame to smooth out network jitter
                    if LiGetPendingVideoFrames() == 1 {
                        break
                    }
                }
            }
        }
    }

    // MARK: - Decoding & Sample Buffer Handling

    /**
     *  Replaces the old `AVSampleBufferDisplayLayer` usage.
     *  Instead of enqueuing to a display layer, we create a `CMSampleBuffer`
     *  and forward it to your own rendering path (e.g., a Metal texture queue).
     */
    @discardableResult
    @objc(submitDecodeBuffer:length:bufferType:decodeUnit:)
    func submitDecodeBuffer(
        _ dataPtr: UnsafeMutablePointer<UInt8>!,
        length: Int32,
        bufferType: Int32,
        decode decodeUnit: PDECODE_UNIT!
    ) -> Int32 {
        if decodeUnit.pointee.frameType == FRAME_TYPE_IDR {
            if bufferType != BUFFER_TYPE_PICDATA {
                if bufferType == BUFFER_TYPE_VPS
                    || bufferType == BUFFER_TYPE_SPS
                    || bufferType == BUFFER_TYPE_PPS
                {
                    let startLen = (dataPtr[2] == 0x01) ? 3 : 4
                    let newData = Data(bytes: dataPtr + startLen, count: Int(length) - startLen)
                    parameterSetBuffers.append([UInt8](newData))
                }
                return DR_OK
            }

            if let formatDesc = recreateFormatDescriptionForIDR(
                dataPtr: dataPtr, length: length
            ) {
                self.formatDesc = formatDesc
                let decoderConfiguration: [String: Any] = [
                    kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
                ]
                
                // HDR: request 10-bit bi-planar YUV. AV1 HDR: also tag the decoder pixel pool (original fork parity).
                var attributes: [CFString: Any] = [
                    kCVPixelBufferMetalCompatibilityKey: true,
                    kCVPixelBufferPoolMinimumBufferCountKey: 3
                ]
                if hdrEnabled {
                    attributes[kCVPixelBufferPixelFormatTypeKey] = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                } else {
                    if (self.videoFormat & VIDEO_FORMAT_MASK_AV1) != 0 {
                        attributes[kCVPixelBufferPixelFormatTypeKey] = kCVPixelFormatType_Lossless_32BGRA
                    } else {
                        attributes[kCVPixelBufferPixelFormatTypeKey] = decodingFormat
                    }
                }
                
                VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formatDesc, decoderSpecification: decoderConfiguration as CFDictionary, imageBufferAttributes: attributes as CFDictionary, outputCallback: &decoderCallback, decompressionSessionOut: &session)

                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            } else {
                return DR_NEED_IDR
            }
        }

        guard let formatDesc = formatDesc else {
            return DR_NEED_IDR
        }

        guard let session = session else {
            free(dataPtr)
            return DR_NEED_IDR
        }

        guard let sampleBuffer = createSampleBuffer(
            dataPtr: dataPtr,
            length: Int(length),
            formatDesc: formatDesc,
            decodeUnit: decodeUnit
        ) else {
            free(dataPtr)
            return DR_NEED_IDR
        }

        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [._EnableAsynchronousDecompression], frameRefcon: nil, infoFlagsOut: nil)

        if decodeUnit.pointee.frameType == FRAME_TYPE_IDR {
            callbacks.videoContentShown()
        }

        return DR_OK
    }

    // MARK: - Helper: Recreate Format Description for IDR

    private func recreateFormatDescriptionForIDR(
        dataPtr: UnsafeMutablePointer<UInt8>,
        length: Int32
    ) -> CMVideoFormatDescription? {
        // Freed old formatDesc
        if let old = formatDesc {
            // CFRelease(old)
            formatDesc = nil
        }

        // If's H.264 or HEVC, gather parameter sets
        if (videoFormat & VIDEO_FORMAT_MASK_H264) != 0 {
            return createH264FormatDescription()
        } else if (videoFormat & VIDEO_FORMAT_MASK_H265) != 0 {
            return createHEVCFormatDescription()
        } else if (videoFormat & VIDEO_FORMAT_MASK_AV1) != 0 {
            // For AV1, parse IDR frame to create a format desc
            let frameData = Data(bytesNoCopy: dataPtr, count: Int(length), deallocator: .none)
            return createAV1FormatDescriptionForIDRFrame(frameData)
        } else {
            // Unsupported video format - return nil to request IDR
            return nil
        }
    }

    /// Creates an H.264 `CMVideoFormatDescription` from the stored `parameterSetBuffers`.
    private func createH264FormatDescription() -> CMVideoFormatDescription? {
        let parameterSetCount = parameterSetBuffers.count
        var paramPtrs: [UnsafePointer<UInt8>] = []
        var paramSizes: [Int] = []

        for (index, ps) in parameterSetBuffers.enumerated() {
            paramPtrs.append(UnsafePointer<UInt8>(parameterSetBuffers[index]))
            paramSizes.append(ps.count)
        }

        var fromatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: parameterSetCount,
            parameterSetPointers: paramPtrs,
            parameterSetSizes: paramSizes,
            nalUnitHeaderLength: Int32(NAL_LENGTH_PREFIX_SIZE),
            formatDescriptionOut: &fromatDesc
        )

        if status != noErr {
            print("Failed to create H264 format description: \(status)")
            return nil
        }
        return fromatDesc
    }

    /// Creates an HEVC `CMVideoFormatDescription` from the stored `parameterSetBuffers`.
    private func createHEVCFormatDescription() -> CMVideoFormatDescription? {
        let parameterSetCount = parameterSetBuffers.count
        var paramPtrs: [UnsafePointer<UInt8>] = []
        var paramSizes: [Int] = []

        for ps in parameterSetBuffers {
            paramPtrs.append(UnsafePointer<UInt8>(ps))
            paramSizes.append(ps.count)
        }

        // Prepare metadata dictionary
        var videoFormatParams = NSMutableDictionary()

        if let contentLightLevelInfo = contentLightLevelInfo {
            videoFormatParams.setObject(contentLightLevelInfo, forKey: kCMFormatDescriptionExtension_ContentLightLevelInfo as NSString)
        }
        if let masteringDisplayColorVolume = masteringDisplayColorVolume {
            videoFormatParams.setObject(masteringDisplayColorVolume, forKey: kCMFormatDescriptionExtension_MasteringDisplayColorVolume as NSString)
        }

        var formatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: parameterSetCount,
            parameterSetPointers: paramPtrs,
            parameterSetSizes: paramSizes,
            nalUnitHeaderLength: Int32(NAL_LENGTH_PREFIX_SIZE),
            extensions: videoFormatParams as CFDictionary,
            formatDescriptionOut: &formatDesc
        )

        if status != noErr {
            print("Failed to create HEVC format description: \(status)")
            return nil
        }
        return formatDesc
    }

    /// Creates an AV1 `CMVideoFormatDescription` from the data for an IDR frame.
    private func createAV1FormatDescriptionForIDRFrame(_ frameData: Data) -> CMVideoFormatDescription? {
        do {
            return try frameData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> CMVideoFormatDescription in
                var mutableBuffer = UnsafeMutableBufferPointer<UInt8>(mutating: buffer.bindMemory(to: UInt8.self))
                let fd = try CMVideoFormatDescriptionCreateFromAV1SequenceHeaderOBUWithAV1C(
                    mutableBuffer,
                    masteringDisplayColorVolume: masteringDisplayColorVolume,
                    contentLightLevelInfo: contentLightLevelInfo
                )
                return fd as CMVideoFormatDescription
            }
        } catch {
            print("AV1 format description creation failed: \(error)")
            return nil
        }
    }

    // MARK: - Creating a Sample Buffer

    private func createSampleBuffer(
        dataPtr: UnsafeMutablePointer<UInt8>,
        length: Int,
        formatDesc: CMVideoFormatDescription,
        decodeUnit: PDECODE_UNIT!
    ) -> CMSampleBuffer? {
        // Create an empty container block for rewriting AnnexB to length-delimited if needed
        var frameBlockBuffer: CMBlockBuffer?

        // If H.264/HEVC, rewrite from AnnexB to length-delimited
        if (videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) != 0 {
            // dataPtr is either tied to the resulting BB, or is copied and freed immediately.
            // dataPtr is also freed even if the result is nil.
            let nals = UnsafeMutableBufferPointer<UInt8>(start: UnsafeMutablePointer(mutating: dataPtr), count: length)
            frameBlockBuffer = annexBBufferToCMSampleBuffer(buffer: nals, videoFormat: formatDesc)
        } else {
            // AV1 or other codecs that don't need rewriting
            let statusDataBlock = CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: dataPtr,
                blockLength: length,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: length,
                flags: 0,
                blockBufferOut: &frameBlockBuffer
            )
            if statusDataBlock != kCMBlockBufferNoErr {
                print("CMBlockBufferCreateWithMemoryBlock failed: \(statusDataBlock)")
                return nil
            }
            // Now the CMBlockBuffer controls freeing `dataPtr`
        }

        // Build the sample buffer
        var sampleBuffer: CMSampleBuffer?
        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTimeMake(value: Int64(decodeUnit.pointee.presentationTimeMs), timescale: 1000),
            decodeTimeStamp: CMTime.invalid
        )
        let statusSample = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: frameBlockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        if statusSample != noErr {
            print("CMSampleBufferCreate failed: \(statusSample)")
            return nil
        }

        return sampleBuffer
    }

    // Based on https://webrtc.googlesource.com/src/+/refs/heads/main/common_video/h264/h264_common.cc
    private func findNaluIndices(bufferBounded: UnsafeMutableBufferPointer<UInt8>) -> ([NaluIndex], Bool) {
        var elgibleForModifyInPlace = true
        guard bufferBounded.count >= /* kNaluShortStartSequenceSize */ 3 else {
            return ([], false)
        }

        var sequences = [NaluIndex]()

        let end = bufferBounded.count - /* kNaluShortStartSequenceSize */ 3
        var i = 0
        let buffer = Data(bytesNoCopy: bufferBounded.baseAddress!, count: bufferBounded.count, deallocator: .none) // ?? why is this faster
        while i < end {
            if buffer[i + 2] > 1 {
                i += 3
            } else if buffer[i + 2] == 1 {
                if buffer[i + 1] == 0 && buffer[i] == 0 {
                    var index = NaluIndex(startOffset: i, payloadStartOffset: i + 3, payloadSize: 0, threeByteHeader: true)
                    if index.startOffset > 0 && buffer[index.startOffset - 1] == 0 {
                        index.startOffset -= 1
                        index.threeByteHeader = false
                    } else {
                        elgibleForModifyInPlace = false
                    }

                    if !sequences.isEmpty {
                        sequences[sequences.count - 1].payloadSize = index.startOffset - sequences.last!.payloadStartOffset
                    }

                    sequences.append(index)
                }

                i += 3
            } else {
                i += 1
            }
        }

        if !sequences.isEmpty {
            sequences[sequences.count - 1].payloadSize = bufferBounded.count - sequences.last!.payloadStartOffset
        }

        return (sequences, elgibleForModifyInPlace)
    }

    private struct NaluIndex {
        var startOffset: Int
        var payloadStartOffset: Int
        var payloadSize: Int
        var threeByteHeader: Bool
    }

    // Based on https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/objc/components/video_codec/nalu_rewriter.cc
    private func annexBBufferToCMSampleBuffer(buffer: UnsafeMutableBufferPointer<UInt8>, videoFormat: CMFormatDescription) -> CMBlockBuffer? {
        let (naluIndices, elgibleForModifyInPlace) = findNaluIndices(bufferBounded: buffer)

        if elgibleForModifyInPlace {
            return annexBBufferToCMSampleBufferModifyInPlace(buffer: buffer, videoFormat: videoFormat, naluIndices: naluIndices)
        } else {
            return annexBBufferToCMSampleBufferWithCopy(buffer: buffer, videoFormat: videoFormat, naluIndices: naluIndices)
        }
    }

    private func annexBBufferToCMSampleBufferWithCopy(buffer: UnsafeMutableBufferPointer<UInt8>, videoFormat _: CMFormatDescription, naluIndices: [NaluIndex]) -> CMBlockBuffer? {
        var err: OSStatus = 0
        defer { buffer.deallocate() }

        // replacing the 3/4 nalu headers with a 4 byte length, so add an extra byte on top of the original length for each 3-byte nalu header
        let blockBufferLength = buffer.count + naluIndices.filter(\.threeByteHeader).count
        
        // Safe allocation with graceful frame dropping on OOM
        guard let blockBuffer = try? CMBlockBuffer(length: blockBufferLength, flags: .assureMemoryNow) else {
            print("⚠️ Failed to allocate CMBlockBuffer (\(blockBufferLength) bytes) - dropping frame due to memory pressure")
            return nil
        }

        var contiguousBuffer: CMBlockBuffer!
        if !CMBlockBufferIsRangeContiguous(blockBuffer, atOffset: 0, length: 0) {
            err = CMBlockBufferCreateContiguous(allocator: nil, sourceBuffer: blockBuffer, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 0, flags: 0, blockBufferOut: &contiguousBuffer)
            if err != 0 {
                print("CMBlockBufferCreateContiguous error")
                return nil
            }
        } else {
            contiguousBuffer = blockBuffer
        }

        var blockBufferSize = 0
        var dataPtr: UnsafeMutablePointer<Int8>!
        err = CMBlockBufferGetDataPointer(contiguousBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &blockBufferSize, dataPointerOut: &dataPtr)
        if err != 0 {
            print("CMBlockBufferGetDataPointer error")
            return nil
        }

        let pointer = UnsafeMutablePointer<UInt8>(OpaquePointer(dataPtr))!
        var offset = 0

        buffer.withUnsafeBytes { unsafeBytes in
            let bytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!

            for index in naluIndices {
                pointer.advanced(by: offset).pointee = UInt8((index.payloadSize >> 24) & 0xFF)
                pointer.advanced(by: offset + 1).pointee = UInt8((index.payloadSize >> 16) & 0xFF)
                pointer.advanced(by: offset + 2).pointee = UInt8((index.payloadSize >> 8) & 0xFF)
                pointer.advanced(by: offset + 3).pointee = UInt8((index.payloadSize) & 0xFF)
                offset += 4

                pointer.advanced(by: offset).update(from: bytes.advanced(by: index.payloadStartOffset), count: blockBufferSize - offset)
                offset += index.payloadSize
            }
        }

        return contiguousBuffer
    }

    private func annexBBufferToCMSampleBufferModifyInPlace(buffer: UnsafeMutableBufferPointer<UInt8>, videoFormat _: CMFormatDescription, naluIndices: [NaluIndex]) -> CMBlockBuffer? {
        var offset = 0

        let umrbp = UnsafeMutableRawBufferPointer(start: buffer.baseAddress, count: buffer.count)
        
        // Safe allocation with graceful frame dropping on OOM
        guard let bb = try? CMBlockBuffer(buffer: umrbp, deallocator: { _, _ in buffer.deallocate() }, flags: .assureMemoryNow) else {
            print("⚠️ Failed to create CMBlockBuffer from buffer (\(buffer.count) bytes) - dropping frame due to memory pressure")
            buffer.deallocate()
            return nil
        }

        let pointer = UnsafeMutablePointer<UInt8>(OpaquePointer(buffer.baseAddress!))!
        for index in naluIndices {
            pointer.advanced(by: offset + 0).pointee = UInt8((index.payloadSize >> 24) & 0xFF)
            pointer.advanced(by: offset + 1).pointee = UInt8((index.payloadSize >> 16) & 0xFF)
            pointer.advanced(by: offset + 2).pointee = UInt8((index.payloadSize >> 8) & 0xFF)
            pointer.advanced(by: offset + 3).pointee = UInt8((index.payloadSize) & 0xFF)
            offset += 4

            offset += index.payloadSize
        }

        return bb
    }

    // MARK: - Rendering to the Drawable

    /**
     * Instead of using AVSampleBufferDisplayLayer, hand the sample buffer off
     * to your rendering pipeline. For example:
     * 1) Create a CVPixelBuffer from the sample buffer
     * 2) Wrap it in a Metal texture (using `CVMetalTextureCacheCreateTextureFromImage`)
     * 3) Enqueue the texture in a command buffer or store in a GPU queue
     *
     * This is a placeholder function for demonstration.
     */
    private func renderSampleBufferToDrawable(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription: CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        let mediaType: CMMediaType = CMFormatDescriptionGetMediaType(formatDescription)

        if mediaType == kCMMediaType_Audio {
            print("this was an audio sample....")
            return
        }

        // Example: Convert to CVPixelBuffer
        guard var imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let drawable = try! drawableQueue!.nextDrawable()
        drawable.texture.replace(region: .init(), mipmapLevel: 0, withBytes: &imageBuffer, bytesPerRow: CVPixelBufferGetBytesPerRow(imageBuffer))

        drawable.present()
        print("Render sample buffer to custom drawable pipeline")
    }

    // MARK: - HDR Mode

    func setHdrMode(_ enabled: Bool) {
        var metadataChanged = false

        // Mastering display color volume check
        let displayMetadata = HDRParsingUtils.parseHDRDisplayMetadata(enabled)

        if let displayMetadata = displayMetadata,
           masteringDisplayColorVolume == nil ||
           masteringDisplayColorVolume != displayMetadata
        {
            masteringDisplayColorVolume = displayMetadata
            metadataChanged = true
        } else if masteringDisplayColorVolume != nil {
            masteringDisplayColorVolume = nil
            metadataChanged = true
        }

        // Content light level info check
        let lightMetadata = HDRParsingUtils.parseHDRLightMetadata(enabled)
        if let lightMetadata = lightMetadata,
           contentLightLevelInfo == nil ||
           contentLightLevelInfo != lightMetadata
        {
            contentLightLevelInfo = lightMetadata
            metadataChanged = true
        } else if contentLightLevelInfo != nil {
            contentLightLevelInfo = nil
            metadataChanged = true
        }

        if metadataChanged {
            updateHDRMetadata()
            LiRequestIdrFrame()
        }
    }

    /// Sync constants with `Shaders.metal` `chromaHaloRimFragment` / `Reactive1ChromosphereReach`.
    private func chromaHaloTemporalFrameMix() -> Float {
        let kBase: Float = 1.55
        let kSpan: Float = 1.93
        let reachT = min(1, max(0, (chromaHaloScale - kBase) / max(kSpan, 1e-4)))
        return 0.27 + reachT * 0.055
    }

    private func ensureChromaHaloBlurScratchMatches(_ haloTex: MTLTexture) {
        let w = haloTex.width
        let h = haloTex.height
        let pf = haloTex.pixelFormat
        if let a = chromaHaloScratchA,
           a.width == w, a.height == h, a.pixelFormat == pf,
           let b = chromaHaloScratchB,
           b.width == w, b.height == h, b.pixelFormat == pf {
            return
        }
        chromaHaloScratchA = nil
        chromaHaloScratchB = nil
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pf, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        chromaHaloScratchA = mtlDevice.makeTexture(descriptor: desc)
        chromaHaloScratchB = mtlDevice.makeTexture(descriptor: desc)
    }

    // Builds a simple copy pipeline with no input buffers, just
    // draw 4 vertices to copy the input texture to the output
    private func buildCopyPipeline(fragment: String) -> MTLRenderPipelineState? {
        guard
            let library = mtlDevice.makeDefaultLibrary()
        else {
            return nil
        }
        
        let vertexFunction = library.makeFunction(name: "copyVertexShader")
        
        // We always request single-plane RGBA output from VT (RGBA16F for HDR, BGRA8 for SDR),
        // so always use the HDR copy fragment (no YUV conversion).
        let fragmentFunction = library.makeFunction(name: fragment)
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "CopyBlitPipeline:\(fragment)"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        pipelineDescriptor.maxVertexAmplificationCount = 1

        return try? mtlDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    // Convert big endian UInt16 to host Float
    private func convertBigEndianUInt16ToFloat(_ value: UInt16) -> Float {
        let hostValue = CFSwapInt16BigToHost(value)
        return Float(hostValue)
    }

    // Create parameter buffers for HDR metadata
    private func createHDRParameterBuffers() -> (MTLBuffer?, MTLBuffer?) {
        var hdrParams = hdrSettingsProvider?() ?? HDRParams(
            boost: 1.0,
            contrast: 1.0,
            saturation: 1.0,
            brightness: 0.0,
            pqExposure: 1.0,
            mode: 0
        )

        // In HDR, allow Filmic/ACES mapping and gentle enhancement,
        // but clamp to safe ranges and force additive brightness to 0.0.
        if hdrEnabled {
            hdrParams.brightness = 0.0
            // Remove clamps for HDR to allow true neutral defaults and wild presets
            // hdrParams.boost = max(0.85, min(hdrParams.boost, 1.25))
            // hdrParams.contrast = max(0.90, min(hdrParams.contrast, 1.20))
            // hdrParams.saturation = max(0.90, min(hdrParams.saturation, 1.25))
            // If no mode set, prefer ACES filmic in HDR
            if hdrParams.mode == 0 {
                hdrParams.mode = 1
            }
        }

        // Enable enhancements in HDR (for ACES tone mapping),
        // keep the toggle for SDR tied to mode != 0.
        let applyEnhancements: Bool = hdrEnabled ? true : (hdrParams.mode != 0)

        var enabled = applyEnhancements
        let enabledBuffer = mtlDevice.makeBuffer(
            bytes: &enabled,
            length: MemoryLayout<Bool>.size,
            options: .storageModeShared
        )

        let paramsBuffer = mtlDevice.makeBuffer(
            bytes: &hdrParams,
            length: MemoryLayout<HDRParams>.size,
            options: .storageModeShared
        )

        return (enabledBuffer, paramsBuffer)
    }

    // MARK: - METAL

    private let planeVertexData: [Float] = [
        -1, -1, 0, 1,
        1, -1, 1, 1,
        -1, 1, 0, 0,
        1, 1, 1, 0,
    ]

    // Add new method to update HDR metadata
    private func updateHDRMetadata() {
        // Get HDR metadata from Moonlight
        if !LiGetHdrMetadata(&hdrMetadata) {
            print("Failed to fetch HDR metadata from Moonlight")
        }
    }
    
    // Parse SMPTE ST 2086 mastering display color volume metadata
    private func parseMasteringDisplayColorVolume(_ data: Data) {
        // Data should be 24 bytes
        guard data.count == 24 else {
            print("Invalid metadata length: \(data.count)")
            return
        }

        // Extract values (stored as normalized 16-bit unsigned integers)
        let displayPrimariesX = [
            Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self) })) / 50000.0,
            Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self) })) / 50000.0,
            Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt16.self) })) / 50000.0
        ]
        
        let displayPrimariesY = [
            Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self) })) / 50000.0,
            Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 6, as: UInt16.self) })) / 50000.0,
            Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt16.self) })) / 50000.0
        ]
        
        let whitePointX = Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt16.self) })) / 50000.0
        let whitePointY = Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt16.self) })) / 50000.0
        
        let maxDisplayLuminance = Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt16.self) }))
        let minDisplayLuminance = Float(CFSwapInt16BigToHost(data.withUnsafeBytes { $0.load(fromByteOffset: 18, as: UInt16.self) })) / 10000.0

        print("\nHDR Display Metadata:")
        print("Display Primaries (x,y):")
        print("Red:    (\(displayPrimariesX[0]), \(displayPrimariesY[0]))")
        print("Green: (\(displayPrimariesX[1]), \(displayPrimariesY[1]))")
        print("Blue:  (\(displayPrimariesX[2]), \(displayPrimariesY[2]))")
        print("White Point: (\(whitePointX), \(whitePointY))")
        print("Max Display Luminance: \(maxDisplayLuminance) nits")
        print("Min Display Luminance: \(minDisplayLuminance) nits")
    }
}

// MARK: - Constants Port

private let NALU_START_PREFIX_SIZE: Int = 3
private let NAL_LENGTH_PREFIX_SIZE: Int = 4

// Example: In Objective-C, had #define VIDEO_FORMAT_MASK_H264 ...
let VIDEO_FORMAT_H264: Int32 = 0x0001 // H.264 High Profile
let VIDEO_FORMAT_H265: Int32 = 0x0100 // HEVC Main Profile
let VIDEO_FORMAT_H265_MAIN10: Int32 = 0x0200 // HEVC Main10 Profile
let VIDEO_FORMAT_AV1_MAIN8: Int32 = 0x1000 // AV1 Main 8-bit profile
let VIDEO_FORMAT_AV1_MAIN10: Int32 = 0x2000 // AV1 Main 10-bit profile

// Masks for clients to use to match video codecs without profile-specific details.
let VIDEO_FORMAT_MASK_H264: Int32 = 0x000F
let VIDEO_FORMAT_MASK_H265: Int32 = 0x0F00
let VIDEO_FORMAT_MASK_AV1: Int32 = 0xF000
let VIDEO_FORMAT_MASK_10BIT: Int32 = 0x2200

// Example placeholders for decodeUnit
let FRAME_TYPE_IDR = 0x01
let BUFFER_TYPE_PICDATA = 0x00
let BUFFER_TYPE_VPS = 1
let BUFFER_TYPE_SPS = 2
let BUFFER_TYPE_PPS = 3

// Example decode results
let DR_OK: Int32 = 0
let DR_NEED_IDR: Int32 = -1

// Example placeholder for C struct
// struct DECODE_UNIT {
//    var frameType: Int32
//    var presentationTimeMs: Int64
// }

//// Example placeholder for C function
// @_silgen_name("DrSubmitDecodeUnit")
// func DrSubmitDecodeUnit(_ du: UnsafeMutablePointer<DECODE_UNIT>) -> Int32 {
//    // Replace with real logic
//    return 0
// }

// Example for HDR metadata
// struct SS_HDR_METADATA {
//    // Add fields, e.g.:
//    var displayPrimaries: (vector_ushort2, vector_ushort2, vector_ushort2) = (.zero, .zero, .zero)
//    var whitePoint: vector_ushort2 = .zero
//    var minDisplayLuminance: UInt32 = 0
//    var maxDisplayLuminance: UInt32 = 0
//    var maxContentLightLevel: UInt16 = 0
//    var maxFrameAverageLightLevel: UInt16 = 0
// }

//// Example bridging
// @_silgen_name("LiGetHdrMetadata")
// func LiGetHdrMetadata(_ hdr: UnsafeMutablePointer<SS_HDR_METADATA>) -> Bool {
//    // Stub, return false for now
//    return false
// }
