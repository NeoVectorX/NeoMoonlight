import SwiftUI

// MARK: - Long Press Control Button

struct LongPressControlBtn: View {
    let label: String
    let systemImage: String
    @Binding var controlsHighlighted: Bool
    @Binding var hideControls: Bool
    let startHighlightTimer: () -> Void
    let startHideTimer: () -> Void
    let primaryAction: () -> Void
    let longPressAction: () -> Void
    /// Optional; when set, called on tap so the host can fire sensory feedback (e.g. curved display spatial audio makes system tap quiet).
    var onTapFeedback: (() -> Void)? = nil
    
    var body: some View {
        Button {
            if !controlsHighlighted && hideControls {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            // Keep controlsHighlighted = true during action execution
            // This prevents state flicker that breaks drag gesture recognition
            hideControls = false
            onTapFeedback?()
            primaryAction()
            startHideTimer()
        } label: {
            Label(label, systemImage: systemImage)
                .font(.system(size: 24.07))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                        onTapFeedback?()
                        longPressAction()
                    }
                )
        }
        .labelStyle(.iconOnly)
    }
}
