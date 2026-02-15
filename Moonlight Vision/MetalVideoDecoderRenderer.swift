//
//  MetalVideoDecoderRenderer.swift
//  Moonlight Vision
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import AVFoundation
import CoreFoundation
import CoreVideo
import Foundation
import Metal
import MetalKit
import QuartzCore
import UIKit
import VideoToolbox

// MARK: - Metal Video Decoder Renderer for UIKit (Enhanced HDR 2D Mode)

@objc(MetalVideoDecoderRenderer)
class MetalVideoDecoderRenderer: NSObject, AnyVideoDecoderRenderer {
    // MARK: - Properties
    
    private var callbacks: ConnectionCallbacks
    private var streamAspectRatio: Float
    private var metalView: MTKView
    private weak var parentView: UIView?
    
    /// Format and frame info
    private var videoFormat: Int32 = 0
    private var frameRate: Int32 = 0
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    
    private var metalFormat: MTLPixelFormat
    
    /// If true, we'll do pacing logic in displayLink
    private var framePacing: Bool = false
    
    /// Store parameter set data for H.264 / HEVC
    private var parameterSetBuffers: [[UInt8]] = []
    
    /// HDR metadata
    private var masteringDisplayColorVolume: Data?
    private var contentLightLevelInfo: Data?
    
    /// Our video format description, used when creating sample buffers
    private var formatDesc: CMVideoFormatDescription?
    
    /// Display link for pacing decode submissions
    private var displayLink: CADisplayLink?
    
    var textureCache: CVMetalTextureCache?
    var session: VTDecompressionSession?
    var decoderCallback: VTDecompressionOutputCallbackRecord
    
    lazy var mtlDevice: MTLDevice = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }
        return device
    }()
    
    private lazy var commandQueue: MTLCommandQueue? = mtlDevice.makeCommandQueue()
    
    private var hdrEnabled: Bool
    private var hdrMetadata: SS_HDR_METADATA = SS_HDR_METADATA()
    
    private var copyPipelineState: MTLRenderPipelineState?
    private var copyPipelineFormat: MTLPixelFormat?
    private var copyPipelineStateYUV: MTLRenderPipelineState?
    private var lastCopyFragment: String?
    
    // Current frame storage
    private var currentPixelBuffer: CVPixelBuffer?
    private let textureLock = NSLock()
    
    // HDR enhancement parameters - Expose to Objective-C with @objc dynamic
    @objc dynamic public var hdrBrightness: Float = 1.35 {
        didSet {
            print("MetalVideoDecoderRenderer: hdrBrightness changed to \(hdrBrightness)")
        }
    }
    @objc dynamic public var hdrSaturation: Float = 1.4 {
        didSet {
            print("MetalVideoDecoderRenderer: hdrSaturation changed to \(hdrSaturation)")
        }
    }
    @objc dynamic public var hdrContrast: Float = 1.15 {
        didSet {
            print("MetalVideoDecoderRenderer: hdrContrast changed to \(hdrContrast)")
        }
    }
    @objc dynamic public var hdrLuminosity: Float = 1.0
    @objc dynamic public var hdrGamma: Float = 1.0
    @objc dynamic public var presetActive: Bool = false
    @objc dynamic public var presetMode: Int32 = 0 // 0=Power Curve, 1=ACES, 2=ACES+Vibrance
    
    private var logCounter: Int = 0
    
    // HDR enhancement parameters struct for passing to shader
    private struct ShaderHDRParams {
        var boost: Float        // luminosity
        var contrast: Float     // gamma/contrast
        var saturation: Float
        var brightness: Float
        var mode: Int32         // 0,1,2
    }
    
    // MARK: - Initialization
    
    @objc(initWithView:callbacks:streamAspectRatio:useFramePacing:enableHDR:)
    init(
        view: UIView,
        callbacks: ConnectionCallbacks,
        streamAspectRatio: Float,
        useFramePacing: Bool,
        enableHDR: Bool
    ) {
        self.parentView = view
        
        // Setup Metal view - use exact bounds
        self.metalView = MTKView(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
        self.metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // CRITICAL FIX: Let the system manage scaling and drawable size
        // DO NOT force contentScaleFactor - this causes softness
        self.metalView.autoResizeDrawable = true
        
        if enableHDR {
            metalFormat = .bgra10_xr
            metalView.colorPixelFormat = .bgra10_xr
            
            if let metalLayer = metalView.layer as? CAMetalLayer {
                metalLayer.wantsExtendedDynamicRangeContent = true
                metalLayer.pixelFormat = .bgra10_xr
                
                // CRITICAL: Disable all implicit filtering for maximum sharpness
                metalLayer.magnificationFilter = .nearest
                metalLayer.minificationFilter = .nearest
                metalLayer.allowsEdgeAntialiasing = false
                metalLayer.framebufferOnly = true
                
                if let extendedColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) {
                    metalLayer.colorspace = extendedColorSpace
                    print("MetalVideoDecoderRenderer: Set extended color space (EDR XR)")
                } else {
                    print("MetalVideoDecoderRenderer: Failed to create extended color space")
                }
            }
        } else {
            metalFormat = .bgra8Unorm_srgb
            metalView.colorPixelFormat = .bgra8Unorm_srgb
            
            // CRITICAL: Disable all implicit filtering for SDR too
            if let metalLayer = metalView.layer as? CAMetalLayer {
                metalLayer.magnificationFilter = .nearest
                metalLayer.minificationFilter = .nearest
                metalLayer.allowsEdgeAntialiasing = false
                metalLayer.framebufferOnly = true
            }
        }
        
        // CRITICAL: Keep layer OPAQUE for maximum sharpness (no compositor blur)
        self.metalView.isHidden = false
        self.metalView.alpha = 1.0
        self.metalView.backgroundColor = .black
        self.metalView.isOpaque = true
        self.metalView.layer.isOpaque = true
        self.metalView.clearsContextBeforeDrawing = false
        
        // CRITICAL: NO corner radius, NO masking - keep completely raw
        // Let SwiftUI overlay handle the visual rounding
        
        self.callbacks = callbacks
        self.streamAspectRatio = streamAspectRatio
        self.framePacing = useFramePacing
        self.hdrEnabled = enableHDR
        
        decoderCallback = VTDecompressionOutputCallbackRecord()
        decoderCallback.decompressionOutputCallback = { decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
            let mySelf = Unmanaged<MetalVideoDecoderRenderer>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
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
        
        // self.applyRoundedCornerMask(to: self.metalView)
        
        decoderCallback.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleForceStop), name: .forceStopRendering, object: nil)
        
        // Add Metal view as subview and bring to back (behind overlays but visible)
        view.addSubview(metalView)
        view.sendSubviewToBack(metalView)
        
        // Setup MTKView delegate
        metalView.delegate = self
        metalView.isPaused = false           // Auto-draw enabled
        metalView.enableSetNeedsDisplay = false  // Use continuous drawing
        
        print("MetalVideoDecoderRenderer: Initialized (Enhanced HDR 2D Mode)")
        print("MetalVideoDecoderRenderer: HDR enabled: \(enableHDR)")
        print("MetalVideoDecoderRenderer: Pixel format: \(metalFormat)")
        print("MetalVideoDecoderRenderer: Metal view frame: \(metalView.frame)")
    }
    
    // MARK: - VideoToolbox Decompression Callback
    
    func decompressionOutputCallback(
        decompressionOutputRefCon _: UnsafeMutableRawPointer?,
        sourceFrameRefCon _: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags _: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp _: CMTime,
        presentationDuration _: CMTime?
    ) {
        guard status == noErr,
              let imageBuffer = imageBuffer,
              let textureCache = textureCache else {
            if status != noErr {
                print("MetalVideoDecoderRenderer: Decode error: \(status)")
            }
            return
        }
        
        if hdrEnabled {
            updateHDRMetadata()
        }
        
        // Get Metal texture from CVPixelBuffer
        let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        let srcMetalFormats = CVMetalHelpers.getTextureTypesForFormat(pixelFormat)
        let srcMetalFormat = srcMetalFormats[0]
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let planeWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
        let planeHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
        
        if width != videoWidth || height != videoHeight {
            videoWidth = width
            videoHeight = height
        }
        
        var imageTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, imageBuffer, nil,
            srcMetalFormat, planeWidth, planeHeight, 0, &imageTexture
        )
        
        if result != 0 {
            print("MetalVideoDecoderRenderer: CVMetalTextureCacheCreateTextureFromImage failed: \(result)")
            return
        }
        
        guard let mtlSourceTexture = CVMetalTextureGetTexture(imageTexture!) else {
            print("MetalVideoDecoderRenderer: Failed to get texture from CVMetalTexture")
            return
        }
        
        // Store the source texture directly
        textureLock.lock()
        currentPixelBuffer = imageBuffer
        textureLock.unlock()
        
        // MTKView will auto-draw since isPaused = false
    }
    
    // MARK: - AnyVideoDecoderRenderer Protocol
    
    func setup(withVideoFormat videoFormat: Int32, width videoWidth: Int32, height videoHeight: Int32, frameRate: Int32) {
        self.videoFormat = videoFormat
        self.frameRate = frameRate
        self.videoWidth = Int(videoWidth)
        self.videoHeight = Int(videoHeight)
        
        print("MetalVideoDecoderRenderer: Setup with format=\(videoFormat), \(videoWidth)x\(videoHeight)@\(frameRate)fps")
        
        // Configure cache attributes
        let cacheAttributes: [String: Any] = [
            kCVMetalTextureCacheMaximumTextureAgeKey as String: 1,
        ]
        
        // Let VideoToolbox choose the best pixel format - don't force anything
        let textureAttributes: [String: Any] = {
            var attrs: [String: Any] = [
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight,
            ]
            if hdrEnabled {
                attrs[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
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
            print("MetalVideoDecoderRenderer: Creating texture cache failed: \(res)")
        }
        
        // Ensure metal view is visible
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.metalView.isHidden = false
            if let parent = self.parentView {
                parent.bringSubviewToFront(self.metalView)
            }
            print("MetalVideoDecoderRenderer: Metal view visible, frame=\(self.metalView.frame), drawableSize=\(self.metalView.drawableSize)")
        }
    }
    
    func start() {
        print("MetalVideoDecoderRenderer: Starting display link")
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
    
    func stop() {
        print("MetalVideoDecoderRenderer: Stopping")
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc public func shutdown() {
        print("MetalVideoDecoderRenderer: Shutdown")
        
        NotificationCenter.default.removeObserver(self, name: .forceStopRendering, object: nil)
        
        // Stop display link
        stop()

        // Invalidate and clear VT session
        if let s = session {
            VTDecompressionSessionInvalidate(s)
        }
        session = nil

        // Clear format desc and parameter sets
        formatDesc = nil
        parameterSetBuffers.removeAll()

        // Flush and drop texture cache
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        textureCache = nil

        // Clear any retained frame
        textureLock.lock()
        currentPixelBuffer = nil
        textureLock.unlock()

        // Release pipeline state/cache
        copyPipelineState = nil
        copyPipelineFormat = nil

        // Pause the MTKView to avoid further draws
        DispatchQueue.main.async {
            self.metalView.isPaused = true
        }

        print("MetalVideoDecoderRenderer: Shutdown complete")
    }
    
    @objc private func displayLinkCallback(_ sender: CADisplayLink) {
        var handle: VIDEO_FRAME_HANDLE?
        var du: PDECODE_UNIT?
        
        while LiPollNextVideoFrame(&handle, &du) {
            guard let handle = handle, let du = du else {
                continue
            }
            
            let result = DrSubmitDecodeUnit(du)
            LiCompleteVideoFrame(handle, result)
            
            if framePacing {
                let displayRefreshRate = 1.0 / (sender.targetTimestamp - sender.timestamp)
                if displayRefreshRate >= Double(frameRate) * 0.9 {
                    if LiGetPendingVideoFrames() == 1 {
                        break
                    }
                }
            }
        }
    }
    
    @discardableResult
    func submitDecodeBuffer(
        _ dataPtr: UnsafeMutablePointer<UInt8>!,
        length: Int32,
        bufferType: Int32,
        decode du: PDECODE_UNIT!
    ) -> Int32 {
        // IDR frame handling
        if du.pointee.frameType == FRAME_TYPE_IDR {
            if bufferType != BUFFER_TYPE_PICDATA {
                if bufferType == BUFFER_TYPE_VPS ||
                    bufferType == BUFFER_TYPE_SPS ||
                    bufferType == BUFFER_TYPE_PPS {
                    let startLen = (dataPtr[2] == 0x01) ? 3 : 4
                    let newData = Data(bytes: dataPtr + startLen, count: Int(length) - startLen)
                    parameterSetBuffers.append([UInt8](newData))
                }
                return DR_OK
            }
            
            if let formatDesc = recreateFormatDescriptionForIDR(dataPtr: dataPtr, length: length) {
                self.formatDesc = formatDesc
                
                let decoderConfiguration: [String: Any] = [
                    kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
                ]
                
                // Let VideoToolbox choose the best output format
                var attributes: [CFString: Any] = [
                    kCVPixelBufferMetalCompatibilityKey: true,
                    kCVPixelBufferPoolMinimumBufferCountKey: 3
                ]
                if hdrEnabled {
                    attributes[kCVPixelBufferPixelFormatTypeKey] = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                }
                
                VTDecompressionSessionCreate(
                    allocator: kCFAllocatorDefault,
                    formatDescription: formatDesc,
                    decoderSpecification: decoderConfiguration as CFDictionary,
                    imageBufferAttributes: attributes as CFDictionary,
                    outputCallback: &decoderCallback,
                    decompressionSessionOut: &session
                )
                
                // Keep PQ primaries and decode in shader to match upstream pop.
                // if let session, hdrEnabled { VTSessionSetProperty(...) }
                
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            } else {
                return DR_NEED_IDR
            }
        }
        
        guard let formatDesc = formatDesc else {
            // No format desc yet - free the buffer since we're not using it
            free(dataPtr)
            return DR_NEED_IDR
        }
        
        guard let sampleBuffer = createSampleBuffer(
            dataPtr: dataPtr,
            length: Int(length),
            formatDesc: formatDesc,
            decodeUnit: du
        ) else {
            // createSampleBuffer failed - it will handle freeing if needed
            return DR_NEED_IDR
        }
        
        VTDecompressionSessionDecodeFrame(
            session!,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if du.pointee.frameType == FRAME_TYPE_IDR {
            callbacks.videoContentShown()
        }
        
        return DR_OK
    }
    
    func setHdrMode(_ enabled: Bool) {
        var metadataChanged = false
        
        let displayMetadata = HDRParsingUtils.parseHDRDisplayMetadata(enabled)
        if let displayMetadata = displayMetadata,
           masteringDisplayColorVolume == nil ||
           masteringDisplayColorVolume != displayMetadata {
            masteringDisplayColorVolume = displayMetadata
            metadataChanged = true
        } else if masteringDisplayColorVolume != nil {
            masteringDisplayColorVolume = nil
            metadataChanged = true
        }
        
        let lightMetadata = HDRParsingUtils.parseHDRLightMetadata(enabled)
        if let lightMetadata = lightMetadata,
           contentLightLevelInfo == nil ||
           contentLightLevelInfo != lightMetadata {
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
    
    // MARK: - Helper Methods
    
    private func recreateFormatDescriptionForIDR(
        dataPtr: UnsafeMutablePointer<UInt8>,
        length: Int32
    ) -> CMVideoFormatDescription? {
        if let old = formatDesc {
            formatDesc = nil
        }
        
        if (videoFormat & VIDEO_FORMAT_MASK_H264) != 0 {
            return createH264FormatDescription()
        } else if (videoFormat & VIDEO_FORMAT_MASK_H265) != 0 {
            return createHEVCFormatDescription()
        } else if (videoFormat & VIDEO_FORMAT_MASK_AV1) != 0 {
            let frameData = Data(bytesNoCopy: dataPtr, count: Int(length), deallocator: .none)
            return createAV1FormatDescriptionForIDRFrame(frameData)
        } else {
            abort()
        }
    }
    
    private func createH264FormatDescription() -> CMVideoFormatDescription? {
        let parameterSetCount = parameterSetBuffers.count
        var paramPtrs: [UnsafePointer<UInt8>] = []
        var paramSizes: [Int] = []
        
        // Keep buffers alive during format description creation
        let buffers = parameterSetBuffers
        for ps in buffers {
            ps.withUnsafeBufferPointer { buffer in
                paramPtrs.append(buffer.baseAddress!)
                paramSizes.append(ps.count)
            }
        }
        
        var formatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: parameterSetCount,
            parameterSetPointers: paramPtrs,
            parameterSetSizes: paramSizes,
            nalUnitHeaderLength: Int32(NAL_LENGTH_PREFIX_SIZE),
            formatDescriptionOut: &formatDesc
        )
        
        if status != noErr {
            print("MetalVideoDecoderRenderer: Failed to create H264 format description: \(status)")
            return nil
        }
        return formatDesc
    }
    
    private func createHEVCFormatDescription() -> CMVideoFormatDescription? {
        let parameterSetCount = parameterSetBuffers.count
        var paramPtrs: [UnsafePointer<UInt8>] = []
        var paramSizes: [Int] = []
        
        // Keep buffers alive during format description creation
        let buffers = parameterSetBuffers
        for ps in buffers {
            ps.withUnsafeBufferPointer { buffer in
                paramPtrs.append(buffer.baseAddress!)
                paramSizes.append(ps.count)
            }
        }
        
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
            print("MetalVideoDecoderRenderer: Failed to create HEVC format description: \(status)")
            return nil
        }
        return formatDesc
    }
    
    private func createAV1FormatDescriptionForIDRFrame(_ frameData: Data) -> CMVideoFormatDescription? {
        do {
            return try frameData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> CMFormatDescription in
                var mutableBuffer = UnsafeMutableBufferPointer<UInt8>(mutating: buffer.bindMemory(to: UInt8.self))
                return try CMVideoFormatDescriptionCreateFromAV1SequenceHeaderOBUWithAV1C(mutableBuffer)
            }
        } catch {
            print("MetalVideoDecoderRenderer: AV1 format description creation failed: \(error)")
            return nil
        }
    }
    
    private func createSampleBuffer(
        dataPtr: UnsafeMutablePointer<UInt8>,
        length: Int,
        formatDesc: CMVideoFormatDescription,
        decodeUnit: PDECODE_UNIT!
    ) -> CMSampleBuffer? {
        var frameBlockBuffer: CMBlockBuffer?
        
        // H.264/HEVC require NAL prefix fixups
        if (videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) != 0 {
            // Create buffer pointer WITHOUT taking ownership
            let nals = UnsafeMutableBufferPointer<UInt8>(start: dataPtr, count: length)
            if let newBlock = annexBBufferToCMSampleBuffer(buffer: nals, videoFormat: formatDesc) {
                frameBlockBuffer = newBlock
            } else {
                free(dataPtr)
                return nil
            }
        } else {
            // AV1: Create block buffer directly
            var dataBlockBuffer: CMBlockBuffer?
            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: dataPtr,
                blockLength: length,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: length,
                flags: 0,
                blockBufferOut: &dataBlockBuffer
            )
            if status != noErr {
                print("CMBlockBufferCreateWithMemoryBlock failed: \(status)")
                free(dataPtr)
                return nil
            }
            
            status = CMBlockBufferCreateEmpty(
                allocator: nil,
                capacity: 0,
                flags: 0,
                blockBufferOut: &frameBlockBuffer
            )
            if status != noErr {
                print("CMBlockBufferCreateEmpty failed: \(status)")
                return nil
            }
            
            status = CMBlockBufferAppendBufferReference(
                frameBlockBuffer!,
                targetBBuf: dataBlockBuffer!,
                offsetToData: 0,
                dataLength: length,
                flags: 0
            )
            if status != noErr {
                print("CMBlockBufferAppendBufferReference failed: \(status)")
                return nil
            }
        }
        
        var sampleBuffer: CMSampleBuffer?
        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTimeMake(value: Int64(decodeUnit.pointee.presentationTimeMs), timescale: 1000),
            decodeTimeStamp: CMTime.invalid
        )
        
        let status = CMSampleBufferCreateReady(
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
        
        if status != noErr {
            print("CMSampleBufferCreate failed: \(status)")
            return nil
        }
        
        return sampleBuffer
    }
    
    // AnnexB conversion
    private struct NaluIndex {
        var startOffset: Int
        var payloadStartOffset: Int
        var payloadSize: Int
        var threeByteHeader: Bool
    }
    
    private func findNaluIndices(bufferBounded: UnsafeMutableBufferPointer<UInt8>) -> ([NaluIndex], Bool) {
        var eligible = true
        guard bufferBounded.count >= 3 else {
            return ([], false)
        }
        
        var sequences = [NaluIndex]()
        let end = bufferBounded.count - 3
        var i = 0
        let buffer = Data(bytesNoCopy: bufferBounded.baseAddress!, count: bufferBounded.count, deallocator: .none)
        
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
                        eligible = false
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
        
        return (sequences, eligible)
    }
    
    private func annexBBufferToCMSampleBuffer(buffer: UnsafeMutableBufferPointer<UInt8>, videoFormat: CMFormatDescription) -> CMBlockBuffer? {
        let (naluIndices, eligible) = findNaluIndices(bufferBounded: buffer)
        
        if eligible {
            return annexBBufferToCMSampleBufferModifyInPlace(buffer: buffer, videoFormat: videoFormat, naluIndices: naluIndices)
        } else {
            return annexBBufferToCMSampleBufferWithCopy(buffer: buffer, videoFormat: videoFormat, naluIndices: naluIndices)
        }
    }
    
    private func annexBBufferToCMSampleBufferWithCopy(buffer: UnsafeMutableBufferPointer<UInt8>, videoFormat _: CMFormatDescription, naluIndices: [NaluIndex]) -> CMBlockBuffer? {
        // DON'T deallocate - the buffer is managed by C code
        
        let blockBufferLength = buffer.count + naluIndices.filter(\.threeByteHeader).count
        
        // Safe allocation with graceful frame dropping on OOM
        guard let blockBuffer = try? CMBlockBuffer(length: blockBufferLength, flags: .assureMemoryNow) else {
            print("⚠️ Failed to allocate CMBlockBuffer (\(blockBufferLength) bytes) - dropping frame due to memory pressure")
            return nil
        }
        
        var contiguousBuffer: CMBlockBuffer!
        if !CMBlockBufferIsRangeContiguous(blockBuffer, atOffset: 0, length: 0) {
            let err = CMBlockBufferCreateContiguous(
                allocator: nil, sourceBuffer: blockBuffer,
                blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: 0, flags: 0,
                blockBufferOut: &contiguousBuffer
            )
            if err != 0 {
                print("CMBlockBufferCreateContiguous error")
                return nil
            }
        } else {
            contiguousBuffer = blockBuffer
        }
        
        var blockBufferSize = 0
        var dataPtr: UnsafeMutablePointer<Int8>!
        let err = CMBlockBufferGetDataPointer(
            contiguousBuffer, atOffset: 0,
            lengthAtOffsetOut: nil, totalLengthOut: &blockBufferSize,
            dataPointerOut: &dataPtr
        )
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
        
        // Modify the buffer in-place to replace Annex-B start codes with length prefixes
        let pointer = UnsafeMutablePointer<UInt8>(OpaquePointer(buffer.baseAddress!))!
        for index in naluIndices {
            pointer.advanced(by: offset + 0).pointee = UInt8((index.payloadSize >> 24) & 0xFF)
            pointer.advanced(by: offset + 1).pointee = UInt8((index.payloadSize >> 16) & 0xFF)
            pointer.advanced(by: offset + 2).pointee = UInt8((index.payloadSize >> 8) & 0xFF)
            pointer.advanced(by: offset + 3).pointee = UInt8((index.payloadSize) & 0xFF)
            offset += 4
            offset += index.payloadSize
        }
        
        // Create CMBlockBuffer using the original dataPtr - CMBlockBuffer will take ownership
        // and use kCFAllocatorDefault (which calls free()) when it's released
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: buffer.baseAddress,
            blockLength: buffer.count,
            blockAllocator: kCFAllocatorDefault,  // This will call free() when done
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: buffer.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        if status != noErr {
            print("CMBlockBufferCreateWithMemoryBlock failed in annexBBufferToCMSampleBufferModifyInPlace: \(status)")
            return nil
        }
        
        return blockBuffer
    }
    
    // Build pipeline for a specified fragment shader (target format = render target)
    private func buildCopyPipeline(fragment: String) -> MTLRenderPipelineState? {
        guard let library = mtlDevice.makeDefaultLibrary() else {
            print("MetalVideoDecoderRenderer: Failed to get default library")
            return nil
        }
        
        let vertexFunction = library.makeFunction(name: "copyVertexShader")
        let fragmentFunction = library.makeFunction(name: fragment)
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "CopyBlitPipeline:\(fragment)"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        
        return try? mtlDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func updateHDRMetadata() {
        if !LiGetHdrMetadata(&hdrMetadata) {
            print("MetalVideoDecoderRenderer: Failed to fetch HDR metadata from Moonlight")
        }
    }
    
    private func colorDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return simd_length(d)
    }
    
    @objc private func handleForceStop() {
        print("[MetalRenderer] 🛑 ForceStopRendering received. Pausing MTKView.")
        self.metalView.isPaused = true
    }
    
    // MARK: - Corner Masking
    
    /*
    private func applyRoundedCornerMask(to view: MTKView) {
        let maskLayer = CAShapeLayer()
        let rect = view.bounds
        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
        maskLayer.path = path
        view.layer.mask = maskLayer
    }
    
    private func updateRoundedCornerMask() {
        guard let maskLayer = metalView.layer.mask as? CAShapeLayer else { return }
        let rect = metalView.bounds
        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
        maskLayer.path = path
    }
    */
}

// MARK: - MTKViewDelegate

extension MetalVideoDecoderRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("MetalVideoDecoderRenderer: Drawable size changed to \(size.width) x \(size.height)")
        
        // updateRoundedCornerMask()
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        
        textureLock.lock()
        let pixelBuffer = currentPixelBuffer
        textureLock.unlock()
        
        // 1. If no frame, clear to black and return
        if pixelBuffer == nil {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        // 2. We have a frame. Get info.
        let pb = pixelBuffer! // Safe unwrap
        let pixelFormat = CVPixelBufferGetPixelFormatType(pb)
        let planeCount = CVPixelBufferGetPlaneCount(pb)
        
        if hdrEnabled { updateHDRMetadata() }
        
        // 3. Determine Format (Bi-Planar vs Single)
        var isBiPlanar = false
        var yFormat: MTLPixelFormat = .invalid
        var cbcrFormat: MTLPixelFormat = .invalid
        
        if hdrEnabled && planeCount >= 2 {
            yFormat = .r16Unorm
            cbcrFormat = .rg16Unorm
            isBiPlanar = true
        } else {
            let srcMetalFormats = CVMetalHelpers.getTextureTypesForFormat(pixelFormat)
            if srcMetalFormats.count > 0 { yFormat = srcMetalFormats[0] }
            if srcMetalFormats.count > 1 { cbcrFormat = srcMetalFormats[1] }
            isBiPlanar = (planeCount >= 2) && (cbcrFormat != .invalid)
        }
        
        // 4. Setup Pipeline - Use UIKit-specific sharpened shaders
        let fragmentName = isBiPlanar ? "copyFragmentShaderHDR_EDR_UIKit" : "copyFragmentShaderHEVC_EDR_UIKit"
        
        if isBiPlanar {
            if copyPipelineStateYUV == nil || lastCopyFragment != fragmentName {
                copyPipelineStateYUV = buildCopyPipeline(fragment: fragmentName)
                lastCopyFragment = fragmentName
            }
            if copyPipelineStateYUV == nil { return }
        } else {
            if copyPipelineState == nil || lastCopyFragment != fragmentName {
                copyPipelineState = buildCopyPipeline(fragment: fragmentName)
                lastCopyFragment = fragmentName
            }
            if copyPipelineState == nil { return }
        }
        
        // 5. Create Textures
        var tex0: MTLTexture?
        var tex1: MTLTexture?
        
        if isBiPlanar {
            var yRef: CVMetalTexture?
            var uvRef: CVMetalTexture?
            let w0 = CVPixelBufferGetWidthOfPlane(pb, 0)
            let h0 = CVPixelBufferGetHeightOfPlane(pb, 0)
            let w1 = CVPixelBufferGetWidthOfPlane(pb, 1)
            let h1 = CVPixelBufferGetHeightOfPlane(pb, 1)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pb, nil, yFormat, w0, h0, 0, &yRef)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pb, nil, cbcrFormat, w1, h1, 1, &uvRef)
            if let y = yRef, let uv = uvRef {
                tex0 = CVMetalTextureGetTexture(y)
                tex1 = CVMetalTextureGetTexture(uv)
            }
        } else {
            var imgRef: CVMetalTexture?
            let w = CVPixelBufferGetWidth(pb)
            let h = CVPixelBufferGetHeight(pb)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pb, nil, yFormat, w, h, 0, &imgRef)
            if let img = imgRef {
                tex0 = CVMetalTextureGetTexture(img)
            }
        }
        
        // 6. Encode Render Pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        if isBiPlanar, let t0 = tex0, let t1 = tex1 {
            renderEncoder.setRenderPipelineState(copyPipelineStateYUV!)
            renderEncoder.setFragmentTexture(t0, index: 0)
            renderEncoder.setFragmentTexture(t1, index: 1)
        } else if let t0 = tex0 {
            renderEncoder.setRenderPipelineState(copyPipelineState!)
            renderEncoder.setFragmentTexture(t0, index: 0)
        } else {
            // Texture creation failed - abort frame
            renderEncoder.endEncoding()
            return
        }
        
        // 7. BUFFER 0: HDR Params (Detect from PixelBuffer with safe string comparison)
        struct HDRParams { var presetIndex: UInt32; var isPQ: UInt32; var isBT2020Matrix: UInt32; var isBT2020Primaries: UInt32 }
        
        // Force PQ mode when HDR is enabled (AV1 streams often don't set transfer function tag)
        // If user enabled HDR, assume PQ encoding regardless of metadata
        var isPQ: UInt32 = hdrEnabled ? 1 : 0
        var isBT2020Primaries: UInt32 = 0
        var isBT2020Matrix: UInt32 = 0
        
        // Still check attachments for color space, with HDR fallback
        if let primAttachment = CVBufferCopyAttachment(pb, kCVImageBufferColorPrimariesKey, nil),
           let primVal = primAttachment as? String {
            if primVal == "ITU_R_2020" { isBT2020Primaries = 1 }
            else if primVal == "ITU_R_709_2" { isBT2020Primaries = 0 }
        } else {
            // Fallback: If HDR is on, assume Rec.2020
            isBT2020Primaries = hdrEnabled ? 1 : 0
        }
        
        if let mtxAttachment = CVBufferCopyAttachment(pb, kCVImageBufferYCbCrMatrixKey, nil),
           let mtxVal = mtxAttachment as? String {
            if mtxVal == "ITU_R_2020" { isBT2020Matrix = 1 }
            else if mtxVal == "ITU_R_709_2" { isBT2020Matrix = 0 }
        } else {
            // Fallback: If HDR is on, assume Rec.2020
            isBT2020Matrix = hdrEnabled ? 1 : 0
        }
        
        // Always use presetIndex=0 for HDR (full PQ pipeline)
        let presetIndex: UInt32 = hdrEnabled ? 0 : 1
        
        var hdrParams = HDRParams(presetIndex: presetIndex, isPQ: isPQ, isBT2020Matrix: isBT2020Matrix, isBT2020Primaries: isBT2020Primaries)
        
        // Debug logging for HDR detection
        logCounter += 1
        if logCounter % 120 == 0 { // Log every 2 seconds at 60fps
            print("MetalVideoDecoderRenderer: HDR Debug - hdrEnabled=\(hdrEnabled), isPQ=\(isPQ), isBT2020Matrix=\(isBT2020Matrix), isBT2020Primaries=\(isBT2020Primaries), presetIndex=\(presetIndex)")
        }
        
        renderEncoder.setFragmentBytes(&hdrParams, length: MemoryLayout<HDRParams>.size, index: 0)
        
        // 8. BUFFER 2: Color Enhancements (CRITICAL FIX - prevent black screen)
        struct ColorEnhancementUniforms { var saturation: Float; var contrast: Float; var padding1: Float; var padding2: Float }
        
        // Always use the properties, whether HDR or SDR
        var sat = self.hdrSaturation
        var con = self.hdrContrast
        
        // Safety clamps (prevent invalid values)
        if sat < 0.1 { sat = 1.0 }
        if con < 0.1 { con = 1.0 }
        
        // Update debug logging
        if logCounter % 120 == 0 { // Log every 2 seconds at 60fps
            print("MetalVideoDecoderRenderer: Applying sat=\(sat), con=\(con) to shader")
        }
        
        var enh = ColorEnhancementUniforms(saturation: sat, contrast: con, padding1: 0, padding2: 0)
        renderEncoder.setFragmentBytes(&enh, length: MemoryLayout<ColorEnhancementUniforms>.size, index: 2)
        
        // 9. Draw
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Constants

private let NALU_START_PREFIX_SIZE: Int = 3
private let NAL_LENGTH_PREFIX_SIZE: Int = 4