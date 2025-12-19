//
//  AVPlayerManager.swift
//  dogetionary
//
//  Manages a pool of pre-created AVPlayer instances (one per video)
//

import Foundation
import AVFoundation

class AVPlayerManager: ObservableObject {
    static let shared = AVPlayerManager()

    // Pool of pre-created players: [videoId: AVPlayer]
    private var playerPool: [Int: AVPlayer] = [:]
    private let poolQueue = DispatchQueue(label: "com.dogetionary.avplayer.pool", attributes: .concurrent)

    private init() {
        print("AVPlayerManager: Initialized player pool")
    }

    /// Create and cache a player for a video (called after download completes)
    func createPlayer(videoId: Int, url: URL) {
        poolQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Don't recreate if already exists
            if self.playerPool[videoId] != nil {
                print("AVPlayerManager: Player already exists for video \(videoId)")
                return
            }

            // Create new player
            let player = AVPlayer(url: url)
            player.isMuted = false
            player.automaticallyWaitsToMinimizeStalling = false

            self.playerPool[videoId] = player

            print("✓ AVPlayerManager: Pre-created player for video \(videoId)")
        }
    }

    /// Get a pre-created player (instant if available)
    func getPlayer(videoId: Int) -> AVPlayer? {
        return poolQueue.sync {
            if let player = playerPool[videoId] {
                print("AVPlayerManager: Retrieved player for video \(videoId)")
                return player
            }
            print("AVPlayerManager: No player found for video \(videoId)")
            return nil
        }
    }

    /// Remove player when question is removed from queue
    func removePlayer(videoId: Int) {
        poolQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let player = self.playerPool.removeValue(forKey: videoId) {
                player.pause()
                player.replaceCurrentItem(with: nil)
                print("AVPlayerManager: Removed player for video \(videoId)")
            }
        }
    }

    /// Clear all players
    func clearAll() {
        poolQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            for (_, player) in self.playerPool {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }

            let count = self.playerPool.count
            self.playerPool.removeAll()

            print("AVPlayerManager: Cleared \(count) players from pool")
        }
    }

    /// Get pool statistics
    func getPoolInfo() -> (count: Int, videoIds: [Int]) {
        return poolQueue.sync {
            (playerPool.count, Array(playerPool.keys).sorted())
        }
    }
}
