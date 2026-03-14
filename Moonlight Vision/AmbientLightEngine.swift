import Foundation
import Metal
import MetalKit
import UIKit

// Optimized engine that uses stochastic sampling (25 points) instead of full-frame averaging.
// This reduces GPU load by ~99.9% compared to MPSImageStatisticsMean.
actor AmbientLightEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var computePipelineState: MTLComputePipelineState?
    private let resultBuffer: MTLBuffer
    
    private var lastUpdateTime: TimeInterval = 0
    // 0.15s = ~6.6 updates per second. Fast enough for "reactive" feel, slow enough to save M2/R1 power.
    private let updateInterval: TimeInterval = 0.15 
    private var isProcessing = false
    private var lastSentColor: SIMD3<Float>?

    init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        
        // Shared buffer for result (RGBA) so CPU can read it without copying
        guard let buffer = dev.makeBuffer(length: MemoryLayout<SIMD4<Float>>.size, options: .storageModeShared) else {
            return nil
        }
        self.resultBuffer = buffer
        
        // Compile the lightweight sampling shader
        do {
            let library = try dev.makeLibrary(source: stochasticShader, options: nil)
            guard let function = library.makeFunction(name: "sample_ambient_color") else { return nil }
            self.computePipelineState = try dev.makeComputePipelineState(function: function)
        } catch {
            print("AmbientLightEngine: Shader compilation error: \(error)")
            return nil
        }
    }

    func analyze(texture: MTLTexture) {
        let now = CACurrentMediaTime()
        
        // Throttle: Don't run if too soon OR if the GPU is still busy with the last request.
        // This prevents the "command buffer jam" that causes stutter.
        guard now - lastUpdateTime >= updateInterval, !isProcessing else { return }
        
        lastUpdateTime = now
        isProcessing = true

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = computePipelineState else {
            isProcessing = false
            return
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(resultBuffer, offset: 0, index: 0)
        
        // We only launch ONE thread. It reads 25 pixels. Extremely cheap.
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), 
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        
        // Async completion handler - NO waitUntilCompleted()!
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self = self else { return }
            
            // Read result directly from shared memory
            let pointer = self.resultBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 1)
            let c = pointer.pointee
            let newColor = SIMD3<Float>(c.x, c.y, c.z)
            
            Task {
                let lastColor = await self.lastSentColor
                
                // Delta check: only send if the color changed significantly
                let threshold: Float = 0.02 // 2% change threshold across RGB channels
                let shouldSend: Bool
                
                if let last = lastColor {
                    let diff = abs(newColor.x - last.x) + abs(newColor.y - last.y) + abs(newColor.z - last.z)
                    shouldSend = diff > threshold
                } else {
                    shouldSend = true
                }
                
                if shouldSend {
                    await self.updateLastSentColor(newColor)
                    
                    // Send to main thread for UI update
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .ambientAverageColorUpdated,
                            object: nil,
                            userInfo: ["r": newColor.x, "g": newColor.y, "b": newColor.z]
                        )
                    }
                }
                
                // Unlock for the next frame
                await self.unlock()
            }
        }
        
        commandBuffer.commit()
    }
    
    private func unlock() {
        isProcessing = false
    }
    
    private func updateLastSentColor(_ color: SIMD3<Float>) {
        lastSentColor = color
    }
}

// MARK: - Metal Shader Source
// Samples 25 points in a 5x5 grid pattern (center of each cell) to approximate the average color instantly.
// Uses (i - 0.5) / 5.0 to avoid edge artifacts (letterboxing, black bars, compression noise).
private let stochasticShader = """
#include <metal_stdlib>
using namespace metal;

kernel void sample_ambient_color(texture2d<float, access::read> sourceTexture [[texture(0)]],
                                 device float4 *resultBuffer [[buffer(0)]],
                                 uint id [[thread_position_in_grid]])
{
    // Safety check
    if (id > 0) return;

    float width = float(sourceTexture.get_width());
    float height = float(sourceTexture.get_height());
    float4 sum = float4(0.0);
    
    // 5x5 Grid Sample = 25 reads total.
    // Center-sample each cell: (i - 0.5) / 5.0 gives us 0.1, 0.3, 0.5, 0.7, 0.9
    // This avoids edge artifacts (black bars, letterboxing).
    for (int i = 1; i <= 5; i++) {
        for (int j = 1; j <= 5; j++) {
            float u = (float(i) - 0.5) / 5.0;
            float v = (float(j) - 0.5) / 5.0;
            uint2 pos = uint2(u * width, v * height);
            sum += sourceTexture.read(pos);
        }
    }
    
    // Average the results
    resultBuffer[0] = sum / 25.0;
}
"""

extension Notification.Name {
    static let ambientAverageColorUpdated = Notification.Name("AmbientAverageColorUpdated")
}

struct AmbientAverageColorPayload: Codable {
    let r: Float
    let g: Float
    let b: Float
}
