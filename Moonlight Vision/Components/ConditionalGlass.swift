import SwiftUI

struct ConditionalGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassBackgroundEffect()
        } else {
            content
        }
    }
}

extension View {
    func conditionalGlass(_ enabled: Bool) -> some View {
        self.modifier(ConditionalGlass(enabled: enabled))
    }
}