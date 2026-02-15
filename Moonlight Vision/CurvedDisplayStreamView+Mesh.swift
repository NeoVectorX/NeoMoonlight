//
//  CurvedDisplayStreamView+Mesh.swift
//  Neo Moonlight
//
//  Extracted from CurvedDisplayStreamView.swift
//

import SwiftUI
import RealityKit

extension _CurvedDisplayStreamView {
    
    // MARK: - Mesh Generation

    func generateCurvedRoundedPlane(
        width: Float,
        aspectRatio: Float,
        resolution: (UInt32, UInt32),
        curveMagnitude: Float,
        cornerRadiusFraction: Float
    ) throws -> MeshResource {
        var descr = MeshDescriptor(name: "curved_rounded_plane")
        let height = width * aspectRatio
        let vertexCount = Int(resolution.0 * resolution.1)
        let numQuadsX = resolution.0 - 1
        let numQuadsY = resolution.1 - 1
        let triangleCount = Int(numQuadsX * numQuadsY * 2)
        let indexCount = triangleCount * 3
        
        var positions = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var texcoords = [SIMD2<Float>](repeating: .zero, count: vertexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        
        let maxCurveAngle: Float = CURVED_MAX_ANGLE
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 2.0))
        let halfAngle = currentAngle / 2.0
        let isFlat = currentAngle < 0.0001
        let radius: Float = isFlat ? .infinity : (width / currentAngle)
        
        let cornerRadius = max(0.0, min(0.25, cornerRadiusFraction)) * height
        let x0 = -width / 2.0
        let y0 = -height / 2.0
        
        let texInset: Float = 0.002
        
        var vi = 0
        var ii = 0
        
        for y_v in 0 ..< resolution.1 {
            let v_geo = Float(y_v) / Float(resolution.1 - 1)
            let yFlat = (0.5 - v_geo) * height
            let v_tex = (1.0 - v_geo) * (1.0 - 2.0 * texInset) + texInset

            for x_v in 0 ..< resolution.0 {
                let u = Float(x_v) / Float(resolution.0 - 1)
                let xFlat = (u - 0.5) * width

                var xr = xFlat, yr = yFlat
                if cornerRadius > 0 {
                    if xr < x0 + cornerRadius && yr < y0 + cornerRadius {
                        let dx = xr - (x0 + cornerRadius), dy = yr - (y0 + cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (x0 + cornerRadius) + nx; yr = (y0 + cornerRadius) + ny }
                    } else if xr > -x0 - cornerRadius && yr < y0 + cornerRadius {
                        let dx = xr - (-x0 - cornerRadius), dy = yr - (y0 + cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (-x0 - cornerRadius) + nx; yr = (y0 + cornerRadius) + ny }
                    } else if xr < x0 + cornerRadius && yr > -y0 - cornerRadius {
                        let dx = xr - (x0 + cornerRadius), dy = yr - (-y0 - cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (x0 + cornerRadius) + nx; yr = (-y0 - cornerRadius) + ny }
                    } else if xr > -x0 - cornerRadius && yr > -y0 - cornerRadius {
                        let dx = xr - (-x0 - cornerRadius), dy = yr - (-y0 - cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (-x0 - cornerRadius) + nx; yr = (-y0 - cornerRadius) + ny }
                    }
                }
                
                var px = xr, pz: Float = 0.0
                if !isFlat, radius.isFinite {
                    let t = xr / (width / 2.0)
                    let theta = t * halfAngle
                    px = radius * sin(theta)
                    pz = radius - (radius * cos(theta))
                }

                positions[vi] = SIMD3<Float>(px, yr, pz)
                let u_tex = u * (1.0 - 2.0 * texInset) + texInset
                texcoords[vi] = SIMD2<Float>(u_tex, v_tex)

                if x_v < numQuadsX && y_v < numQuadsY {
                    let current = UInt32(vi), nextRow = current + resolution.0
                    indices[ii + 0] = current; indices[ii + 1] = nextRow; indices[ii + 2] = nextRow + 1
                    indices[ii + 3] = current; indices[ii + 4] = nextRow + 1; indices[ii + 5] = current + 1
                    ii += 6
                }
                vi += 1
            }
        }

        descr.positions = MeshBuffer(positions)
        descr.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descr.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descr])
    }

    private func normalizeAndScale(_ dx: Float, _ dy: Float, _ cornerRadius: Float) -> (Float, Float)? {
        let dist = sqrt(dx*dx + dy*dy)
        if dist > cornerRadius {
            let s = cornerRadius / dist
            return (dx * s, dy * s)
        }
        return nil
    }
    
    // MARK: - Inverse UV Calculation (3D hit point → screen coordinates)
    
    /// Converts a 3D local position on the curved mesh to UV coordinates (0-1 range)
    /// This is the inverse of the mesh generation curve math.
    func convertPositionToUV(
        localPosition: SIMD3<Float>,
        width: Float,
        aspectRatio: Float,
        curveMagnitude: Float
    ) -> SIMD2<Float> {
        let height = width * aspectRatio
        let maxCurveAngle: Float = CURVED_MAX_ANGLE
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 2.0))
        
        var u: Float
        
        if currentAngle < 0.0001 {
            // Flat mode: simple linear mapping
            u = (localPosition.x / width) + 0.5
        } else {
            let radius = width / currentAngle
            
            // Inverse of: px = radius * sin(theta), pz = radius * (1 - cos(theta))
            // Use atan2 for robust angle recovery
            let sinTheta = localPosition.x / radius
            let cosTheta = (radius - localPosition.z) / radius
            let theta = atan2(sinTheta, cosTheta)
            
            // Map theta to u in range 0 to 1
            u = (theta / currentAngle) + 0.5
        }
        
        // Y is linear (flip for texture coordinates where 0 = top)
        let v = 1.0 - ((localPosition.y / height) + 0.5)
        
        // Clamp to valid range
        return SIMD2<Float>(
            max(0, min(1, u)),
            max(0, min(1, v))
        )
    }
}
