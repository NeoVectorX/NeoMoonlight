import SwiftUI

private struct InCurvedSpaceKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var inCurvedSpace: Bool {
        get { self[InCurvedSpaceKey.self] }
        set { self[InCurvedSpaceKey.self] = newValue }
    }
}