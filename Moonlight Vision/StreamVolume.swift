//
//  StreamVolume.swift
//  Moonlight Vision
//

import Foundation

enum StreamVolume {
    static func apply(_ volume: Int32) {
        setVolume(volume)
    }
}

@_silgen_name("setVolume")
private func setVolume(_ newVol: Int32)
