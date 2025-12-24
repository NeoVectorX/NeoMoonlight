import Foundation

// SDR input should be BGRA8 sRGB
func applyACESFilmGrading(toBGRAData input: inout Data, width: Int, height: Int) {
    input.withUnsafeMutableBytes { (rawBuf: UnsafeMutableRawBufferPointer) in
        guard let ptr = rawBuf.baseAddress else { return }
        let pixelCount = width * height
        let pixels = ptr.bindMemory(to: UInt8.self, capacity: pixelCount * 4)
        
        for i in 0..<pixelCount {
            let ix = i * 4
            // BGRA
            var b = Float(pixels[ix + 0]) / 255.0
            var g = Float(pixels[ix + 1]) / 255.0
            var r = Float(pixels[ix + 2]) / 255.0
            let a = Float(pixels[ix + 3]) / 255.0
            
            // Apply ACES-like curve to each channel
            r = acesTonemap(r)
            g = acesTonemap(g)
            b = acesTonemap(b)
            
            // Clamp and convert back to [0,255]
            pixels[ix + 0] = UInt8(min(max(b * 255.0, 0), 255))
            pixels[ix + 1] = UInt8(min(max(g * 255.0, 0), 255))
            pixels[ix + 2] = UInt8(min(max(r * 255.0, 0), 255))
            pixels[ix + 3] = UInt8(a * 255.0)    // preserve original alpha
        }
    }
}

// Simplified ACES filmic tonemap curve
func acesTonemap(_ x: Float) -> Float {
    let a: Float = 2.51
    let b: Float = 0.03
    let c: Float = 2.43
    let d: Float = 0.59
    let e: Float = 0.14
    return min(max((x * (a * x + b)) / (x * (c * x + d) + e), 0.0), 1.0)
}