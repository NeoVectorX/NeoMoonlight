//
//  ScreenAdjustCurvaturePill.swift
//  Moonlight Vision
//

import SwiftUI

private enum ScreenAdjustCurvatureChrome {
    static let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    static let minWidth: CGFloat = 480
    static let pillHeight: CGFloat = 78
    /// Outer padding so content clears the capsule rounded ends.
    static let horizontalPadding: CGFloat = 28
    /// Inset within the track row so end tick labels aren't clipped.
    static let trackEndInset: CGFloat = 22
    static let trackHeight: CGFloat = 8
    static let thumbSize: CGFloat = 24
    static let thumbRing: CGFloat = 30
}

struct ScreenAdjustCurvaturePill: View {
    let magnitude: Float
    let opacity: CGFloat
    var interactionEnabled: Bool = true
    var onMagnitudeChanged: (Float) -> Void
    var onDragStarted: () -> Void
    var onDragEnded: (Float) -> Void

    @State private var dragUnit: Float?

    private var displayUnit: Float {
        if let dragUnit { return dragUnit }
        return CurvedCurvatureMapping.magnitudeToSliderUnit(magnitude)
    }

    private var displayLabel: String {
        CurvedCurvatureMapping.label(for: CurvedCurvatureMapping.sliderUnitToMagnitude(displayUnit))
    }

    private var activeTick: CurvatureTick {
        CurvedCurvatureMapping.nearestTick(toSliderUnit: displayUnit)
    }

    private var isDragging: Bool { dragUnit != nil }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, ScreenAdjustCurvatureChrome.horizontalPadding)
                .padding(.top, 10)

            trackRow
                .padding(.horizontal, ScreenAdjustCurvatureChrome.horizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .frame(minWidth: ScreenAdjustCurvatureChrome.minWidth)
        .frame(height: ScreenAdjustCurvatureChrome.pillHeight)
        .glassBackgroundEffect()
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
        .opacity(opacity)
        .allowsHitTesting(interactionEnabled)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: displayLabel)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDragging)
    }

    private var headerRow: some View {
        ZStack {
            Text("CURVATURE")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Spacer()
                Text(displayLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var trackRow: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let inset = ScreenAdjustCurvatureChrome.trackEndInset
            let trackWidth = max(width - inset * 2, 1)
            let trackY = geo.size.height * 0.38
            let labelY = geo.size.height * 0.88
            let thumbX = thumbPosition(for: displayUnit, inset: inset, trackWidth: trackWidth)

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: trackWidth, height: ScreenAdjustCurvatureChrome.trackHeight)
                    .position(x: inset + trackWidth / 2, y: trackY)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                ScreenAdjustCurvatureChrome.brandViolet.opacity(0.95),
                                ScreenAdjustCurvatureChrome.brandViolet.opacity(0.65),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, thumbX - inset), height: ScreenAdjustCurvatureChrome.trackHeight)
                    .position(x: inset + max(0, thumbX - inset) / 2, y: trackY)

                ForEach(Array(CurvatureTick.allCases.enumerated()), id: \.offset) { _, tick in
                    let unit = CurvedCurvatureMapping.tickToSliderUnit(tick)
                    let x = inset + CGFloat(unit) * trackWidth
                    let isActive = tick == activeTick

                    Circle()
                        .fill(isActive ? ScreenAdjustCurvatureChrome.brandViolet : Color.white.opacity(isActive ? 1 : 0.35))
                        .frame(width: isActive ? 7 : 5, height: isActive ? 7 : 5)
                        .position(x: x, y: trackY)

                    Text(tick.label)
                        .font(.system(size: isActive ? 11 : 10, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.42))
                        .lineLimit(1)
                        .fixedSize()
                        .position(x: x, y: labelY)
                        .animation(.easeOut(duration: 0.15), value: activeTick)
                }

                ZStack {
                    Circle()
                        .fill(ScreenAdjustCurvatureChrome.brandViolet.opacity(isDragging ? 0.35 : 0.18))
                        .frame(
                            width: ScreenAdjustCurvatureChrome.thumbRing * (isDragging ? 1.12 : 1.0),
                            height: ScreenAdjustCurvatureChrome.thumbRing * (isDragging ? 1.12 : 1.0)
                        )

                    Circle()
                        .fill(.white)
                        .frame(width: ScreenAdjustCurvatureChrome.thumbSize, height: ScreenAdjustCurvatureChrome.thumbSize)
                        .overlay {
                            Circle()
                                .strokeBorder(ScreenAdjustCurvatureChrome.brandViolet.opacity(0.55), lineWidth: 1.5)
                        }
                }
                .shadow(color: ScreenAdjustCurvatureChrome.brandViolet.opacity(isDragging ? 0.45 : 0.2), radius: isDragging ? 8 : 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
                .position(x: thumbX, y: trackY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragUnit == nil {
                            onDragStarted()
                        }
                        let unit = sliderUnit(for: value.location.x, inset: inset, trackWidth: trackWidth)
                        dragUnit = unit
                        onMagnitudeChanged(CurvedCurvatureMapping.sliderUnitToContinuousMagnitude(unit))
                    }
                    .onEnded { value in
                        let unit = sliderUnit(for: value.location.x, inset: inset, trackWidth: trackWidth)
                        dragUnit = nil
                        onDragEnded(CurvedCurvatureMapping.sliderUnitToMagnitude(unit))
                    }
            )
        }
        .frame(height: 36)
    }

    private func sliderUnit(for locationX: CGFloat, inset: CGFloat, trackWidth: CGFloat) -> Float {
        let clampedX = min(max(locationX - inset, 0), trackWidth)
        return Float(clampedX / trackWidth)
    }

    private func thumbPosition(for unit: Float, inset: CGFloat, trackWidth: CGFloat) -> CGFloat {
        let thumbRadius = ScreenAdjustCurvatureChrome.thumbSize / 2
        let raw = inset + CGFloat(unit) * trackWidth
        return min(max(raw, inset + thumbRadius), inset + trackWidth - thumbRadius)
    }
}
