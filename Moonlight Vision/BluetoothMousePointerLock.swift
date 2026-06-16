//
//  BluetoothMousePointerLock.swift
//  Neo Moonlight
//
//

import GameController
import ObjectiveC
import UIKit

// MARK: - Pointer lock

private final class GlobalPointerLock {
    static let shared = GlobalPointerLock()

    var isLocked = false {
        didSet {
            guard oldValue != isLocked else { return }
            DispatchQueue.main.async {
                for scene in UIApplication.shared.connectedScenes {
                    guard let windowScene = scene as? UIWindowScene else { continue }
                    for window in windowScene.windows {
                        window.rootViewController?.setNeedsUpdateOfPrefersPointerLocked()
                    }
                }
            }
        }
    }

    private static let swizzleOnce: Void = {
        let original = #selector(getter: UIViewController.prefersPointerLocked)
        let swizzled = #selector(getter: UIViewController.neo_swizzledPrefersPointerLocked)
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, original),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzled) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    static func install() {
        _ = swizzleOnce
    }
}

private extension UIViewController {
    @objc dynamic var neo_swizzledPrefersPointerLocked: Bool {
        if GlobalPointerLock.shared.isLocked {
            return true
        }
        return neo_swizzledPrefersPointerLocked
    }
}

enum BluetoothMousePointerLock {
    private static var observersInstalled = false

    static func installIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        GlobalPointerLock.install()

        NotificationCenter.default.addObserver(
            forName: .GCMouseDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            applyWhenMouseConnected()
        }
        NotificationCenter.default.addObserver(
            forName: .GCMouseDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            release()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            GlobalPointerLock.shared.isLocked = false
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            applyWhenMouseConnected()
        }
    }

    static func applyWhenMouseConnected() {
        installIfNeeded()
        let shouldLock = !GCMouse.mice().isEmpty
        GlobalPointerLock.shared.isLocked = shouldLock
        if shouldLock {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfPrefersPointerLocked()
                }
            }
        }
    }

    static func release() {
        GlobalPointerLock.shared.isLocked = false
    }
}

enum BluetoothMouseRouting {
    static var hasConnectedMouse: Bool {
        if #available(iOS 14.0, *) {
            return !GCMouse.mice().isEmpty
        }
        return false
    }

    static func sync() {
        BluetoothMousePointerLock.applyWhenMouseConnected()
    }

    static func releasePointerLock() {
        BluetoothMousePointerLock.release()
    }
}
