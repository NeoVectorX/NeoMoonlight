import Foundation
import Metal
import MetalKit
import UIKit

// ChromaHalo multi-zone color payload — 5 screen regions sampled per frame.
struct ChromaHaloColors {
    let left:   SIMD3<Float>
    let right:  SIMD3<Float>
    let top:    SIMD3<Float>
    let bottom: SIMD3<Float>
    let center: SIMD3<Float>
}

// Optimized engine that samples 5 screen zones (left, right, top, bottom, center).
// Each zone uses a 3x3 weighted grid (9 samples) = 45 total GPU reads per frame.
// Throttled to ~6.6 fps, async, non-blocking — zero impact on render pipeline.
actor AmbientLightEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var computePipelineState: MTLComputePipelineState?
    // 5 zones × RGBA = 5 float4 values
    private let resultBuffer: MTLBuffer

    private var lastUpdateTime: TimeInterval = 0
    // 0.15s = ~6.6 updates per second — fast enough for reactive, slow enough to save power
    private let updateInterval: TimeInterval = 0.15
    private var isProcessing = false
    private var lastSentColors: ChromaHaloColors?

    init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue

        // 5 zones × RGBA (float4) = 5 × 16 bytes = 80 bytes
        guard let buffer = dev.makeBuffer(length: MemoryLayout<SIMD4<Float>>.size * 5, options: .storageModeShared) else {
            return nil
        }
        self.resultBuffer = buffer

        do {
            let library = try dev.makeLibrary(source: chromaHaloShader, options: nil)
            guard let function = library.makeFunction(name: "sample_chromahalo_zones") else { return nil }
            self.computePipelineState = try dev.makeComputePipelineState(function: function)
        } catch {
            print("AmbientLightEngine: ChromaHalo shader compilation error: \(error)")
            return nil
        }
    }

    func analyze(texture: MTLTexture) {
        let now = CACurrentMediaTime()
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
        // 5 threads — one per zone
        encoder.dispatchThreads(MTLSize(width: 5, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 5, height: 1, depth: 1))
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self = self else { return }

            let pointer = self.resultBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 5)
            let rawLeft   = pointer[0]
            let rawRight  = pointer[1]
            let rawTop    = pointer[2]
            let rawBottom = pointer[3]
            let rawCenter = pointer[4]

            let newColors = ChromaHaloColors(
                left:   SIMD3(rawLeft.x,   rawLeft.y,   rawLeft.z),
                right:  SIMD3(rawRight.x,  rawRight.y,  rawRight.z),
                top:    SIMD3(rawTop.x,    rawTop.y,    rawTop.z),
                bottom: SIMD3(rawBottom.x, rawBottom.y, rawBottom.z),
                center: SIMD3(rawCenter.x, rawCenter.y, rawCenter.z)
            )

            Task {
                let shouldSend: Bool
                let threshold: Float = 0.015

                if let last = await self.lastSentColors {
                    let diff = chromaHaloDiff(newColors, last)
                    shouldSend = diff > threshold
                } else {
                    shouldSend = true
                }

                if shouldSend {
                    await self.updateLastSentColors(newColors)
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .chromaHaloColorsUpdated,
                            object: nil,
                            userInfo: [
                                "left":   newColors.left,
                                "right":  newColors.right,
                                "top":    newColors.top,
                                "bottom": newColors.bottom,
                                "center": newColors.center
                            ]
                        )
                    }
                }

                await self.unlock()
            }
        }

        commandBuffer.commit()
    }

    private func unlock() { isProcessing = false }
    private func updateLastSentColors(_ c: ChromaHaloColors) { lastSentColors = c }
}

// Max channel-diff across all 5 zones — determines if update is worth sending.
private func chromaHaloDiff(_ a: ChromaHaloColors, _ b: ChromaHaloColors) -> Float {
    func d(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> Float {
        abs(x.x - y.x) + abs(x.y - y.y) + abs(x.z - y.z)
    }
    return max(d(a.left, b.left), max(d(a.right, b.right), max(d(a.top, b.top), max(d(a.bottom, b.bottom), d(a.center, b.center)))))
}

// MARK: - Metal Shader Source
// 5 threads, one per zone. Each zone samples a 3×3 weighted grid (9 reads).
// Zones are inset 12% from each edge to avoid black bars and encoder border artifacts.
private let chromaHaloShader = """
#include <metal_stdlib>
using namespace metal;

kernel void sample_chromahalo_zones(
    texture2d<float, access::read> tex [[texture(0)]],
    device float4 *result [[buffer(0)]],
    uint id [[thread_position_in_grid]])
{
    if (id >= 5) return;

    float w = float(tex.get_width());
    float h = float(tex.get_height());

    // Zone centers (normalized UV). Safe 12% inset from edges avoids letterbox/encode artifacts.
    // [0]=left, [1]=right, [2]=top, [3]=bottom, [4]=center
    float2 centers[5];
    centers[0] = float2(0.12, 0.50); // left
    centers[1] = float2(0.88, 0.50); // right
    centers[2] = float2(0.50, 0.12); // top
    centers[3] = float2(0.50, 0.88); // bottom
    centers[4] = float2(0.50, 0.50); // center

    // Zone radius — each zone samples a 3×3 area spanning ~16% of the image
    float radius = 0.08;

    float2 center = centers[id];
    float4 sum = float4(0.0);
    float totalWeight = 0.0;

    // 3×3 Gaussian-weighted grid
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 offset = float2(float(dx), float(dy)) * radius;
            float2 uv = clamp(center + offset, float2(0.02), float2(0.98));
            uint2 pos = uint2(uv.x * w, uv.y * h);
            float dist2 = float(dx*dx + dy*dy);
            float weight = exp(-0.5 * dist2);
            sum += tex.read(pos) * weight;
            totalWeight += weight;
        }
    }

    result[id] = sum / totalWeight;
}
"""

extension Notification.Name {
    static let chromaHaloColorsUpdated = Notification.Name("ChromaHaloColorsUpdated")
}

// Legacy single-color notification kept for backward compatibility with any remaining callers
extension Notification.Name {
    static let ambientAverageColorUpdated = Notification.Name("AmbientAverageColorUpdated")
}

struct AmbientAverageColorPayload: Codable {
    let r: Float
    let g: Float
    let b: Float
}
