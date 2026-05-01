//
//  CurvedDisplayStreamView+Mesh.swift
//  Neo Moonlight
//
//  UV / hit helpers for the curved panel. Core mesh generation lives in CurvedDisplayStreamView.swift
//  (`generateCurvedRoundedPlane`, `makeChromosphereMesh`, `fallbackChromospherePlaneMesh`).
//

import SwiftUI
import RealityKit

extension _CurvedDisplayStreamView {

    // MARK: - Inverse UV Calculation (3D hit point → screen coordinates)

    /// Converts a 3D local position on the curved mesh to UV coordinates (0-1 range)
    func convertPositionToUV(
        localPosition: SIMD3<Float>,
        width: Float,
        aspectRatio: Float,
        curveMagnitude: Float
    ) -> SIMD2<Float> {
        let height = width * aspectRatio
        let maxCurveAngle: Float = CURVED_MAX_ANGLE
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 2.0))

        let u: Float

        if currentAngle < 0.0001 {
            u = (localPosition.x / width) + 0.5
        } else {
            let radius = width / currentAngle
            let sinTheta = localPosition.x / radius
            let cosTheta = (radius - localPosition.z) / radius
            let theta = atan2(sinTheta, cosTheta)
            u = (theta / currentAngle) + 0.5
        }

        let v = 1.0 - ((localPosition.y / height) + 0.5)

        return SIMD2<Float>(
            max(0, min(1, u)),
            max(0, min(1, v))
        )
    }
}
