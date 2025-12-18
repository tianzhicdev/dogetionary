//
//  AVPlayerManager.swift
//  dogetionary
//
//  Manages a single shared AVPlayer instance for all video questions
//

import Foundation
import AVFoundation

class AVPlayerManager: ObservableObject {
    static let shared = AVPlayerManager()

    private(set) var player: AVPlayer

    private init() {
        // Create one shared player instance
        self.player = AVPlayer()
        self.player.isMuted = false
        self.player.automaticallyWaitsToMinimizeStalling = false

        print("AVPlayerManager: Initialized with shared player instance")
    }

    /// Load a video into the shared player
    func loadVideo(url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: playerItem)

        print("AVPlayerManager: Loaded video at \(url.lastPathComponent)")
    }

    /// Pause the player
    func pause() {
        player.pause()
    }

    /// Reset player (remove current item)
    func reset() {
        player.replaceCurrentItem(with: nil)
    }
}
