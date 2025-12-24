import SwiftUI
import RealityKit
import simd
import UIKit

struct AmbientDimmerImmersiveView: View {
    @State private var enabled = UserDefaults.standard.bool(forKey: "ambient.dimming.enabled")
    @State private var opacity: CGFloat = 0.38
    @State private var dome: ModelEntity?

    var body: some View {
        RealityView { content in
            let sphere = ModelEntity(mesh: .generateSphere(radius: 60))
            var mat = UnlitMaterial(color: .init(tint: UIColor.black.withAlphaComponent(enabled ? opacity : 0.0)))
            mat.isDoubleSided = true
            sphere.model = ModelComponent(mesh: sphere.model?.mesh ?? .generateSphere(radius: 60), materials: [mat])
            sphere.position = .zero
            content.add(sphere)
            dome = sphere
        } update: { content in
            updateMaterial()
        }
        .onAppear { updateMaterial() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            enabled = UserDefaults.standard.bool(forKey: "ambient.dimming.enabled")
            updateMaterial()
        }
    }

    private func updateMaterial() {
        guard let dome else { return }
        var mat = UnlitMaterial(color: .init(tint: UIColor.black.withAlphaComponent(enabled ? opacity : 0.0)))
        mat.isDoubleSided = true
        dome.model?.materials = [mat]
    }
}