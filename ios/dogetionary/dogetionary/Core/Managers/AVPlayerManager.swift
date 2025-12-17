//
//  AVPlayerManager.swift
//  dogetionary
//
//  Manages pre-creation and caching of AVPlayer instances for video questions
//

import Foundation
import AVFoundation
import Combine

class AVPlayerManager: ObservableObject {
    static let shared = AVPlayerManager()

    private let maxCachedPlayers = 10
    private var playerCache: [Int: AVPlayer] = [:]
    private var playerAccessTimes: [Int: Date] = [:]
    private let cacheQueue = DispatchQueue(label: "com.dogetionary.avplayer.cache", attributes: .concurrent)
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe VideoService state changes to pre-create players
        observeVideoStates()
    }

    // MARK: - Public API

    /// Get a pre-created player if available (instant)
    func getPlayer(videoId: Int) -> AVPlayer? {
        return cacheQueue.sync {
            if let player = playerCache[videoId] {
                print("AVPlayerManager: Cache hit for video \(videoId)")
                // Update access time for LRU
                playerAccessTimes[videoId] = Date()
                return player
            }
            print("AVPlayerManager: Cache miss for video \(videoId)")
            return nil
        }
    }

    /// Prepare players for multiple videos (non-blocking)
    func preparePlayers(videoIds: [Int]) {
        for videoId in videoIds {
            preparePlayer(videoId: videoId)
        }
    }

    /// Prepare a single player (non-blocking)
    func preparePlayer(videoId: Int) {
        // Check if already cached
        if getPlayer(videoId: videoId) != nil {
            print("AVPlayerManager: Player already prepared for video \(videoId)")
            return
        }

        // Check if video is cached in VideoService
        let state = VideoService.shared.getDownloadState(videoId: videoId)

        switch state {
        case .cached(let url):
            // Video is ready, create player
            createAndCachePlayer(videoId: videoId, url: url)

        case .downloading, .notStarted:
            // Video not ready yet, will be created when download completes
            print("AVPlayerManager: Video \(videoId) not cached yet, will prepare when ready")

        case .failed:
            // Video download failed, can't create player
            print("AVPlayerManager: Cannot prepare player for video \(videoId) - download failed")
        }
    }

    /// Manually cache a player that was created elsewhere
    func cachePlayer(videoId: Int, player: AVPlayer) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.playerCache[videoId] = player
            self.playerAccessTimes[videoId] = Date()

            print("AVPlayerManager: Cached player for video \(videoId)")

            // Cleanup old players if needed
            self.enforceMaxCacheSize()
        }
    }

    /// Release a player when no longer needed
    func releasePlayer(videoId: Int) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let player = self.playerCache.removeValue(forKey: videoId) {
                player.pause()
                player.replaceCurrentItem(with: nil)
                self.playerAccessTimes.removeValue(forKey: videoId)
                print("AVPlayerManager: Released player for video \(videoId)")
            }
        }
    }

    /// Clear all cached players
    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            for (_, player) in self.playerCache {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }

            let count = self.playerCache.count
            self.playerCache.removeAll()
            self.playerAccessTimes.removeAll()

            print("AVPlayerManager: Cleared \(count) players from cache")
        }
    }

    /// Get cache statistics
    func getCacheInfo() -> (playerCount: Int, videoIds: [Int]) {
        return cacheQueue.sync {
            (playerCache.count, Array(playerCache.keys).sorted())
        }
    }

    // MARK: - Private Helpers

    /// Observe VideoService state changes to auto-create players
    private func observeVideoStates() {
        VideoService.shared.$downloadStates
            .sink { [weak self] states in
                guard let self = self else { return }

                // For each newly-cached video, prepare player
                for (videoId, state) in states {
                    if case .cached(let url) = state {
                        // Only create if not already in cache
                        if self.getPlayer(videoId: videoId) == nil {
                            self.createAndCachePlayer(videoId: videoId, url: url)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Create AVPlayer and add to cache
    private func createAndCachePlayer(videoId: Int, url: URL) {
        // Create player on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            print("AVPlayerManager: Creating player for video \(videoId)")

            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)

            // Pre-load the video
            player.automaticallyWaitsToMinimizeStalling = false

            // Cache the player
            self.cacheQueue.async(flags: .barrier) {
                self.playerCache[videoId] = player
                self.playerAccessTimes[videoId] = Date()

                print("AVPlayerManager: ✓ Player ready for video \(videoId)")

                // Cleanup old players if needed
                self.enforceMaxCacheSize()
            }
        }
    }

    /// Enforce max cache size using LRU eviction
    private func enforceMaxCacheSize() {
        // Must be called within barrier block
        if playerCache.count <= maxCachedPlayers {
            return
        }

        print("AVPlayerManager: Cache full (\(playerCache.count) players), evicting oldest")

        // Sort by access time (oldest first)
        let sortedIds = playerCache.keys.sorted { id1, id2 in
            let time1 = playerAccessTimes[id1] ?? Date.distantPast
            let time2 = playerAccessTimes[id2] ?? Date.distantPast
            return time1 < time2
        }

        // Remove oldest players
        let toRemove = playerCache.count - maxCachedPlayers
        for videoId in sortedIds.prefix(toRemove) {
            if let player = playerCache.removeValue(forKey: videoId) {
                player.pause()
                player.replaceCurrentItem(with: nil)
                playerAccessTimes.removeValue(forKey: videoId)
                print("AVPlayerManager: Evicted player for video \(videoId)")
            }
        }
    }
}
