//
//  LoopingVideoPlayer.swift
//  dogetionary
//
//  Simple video player with tap-to-pause and auto-loop
//

import SwiftUI
import AVFoundation
import Combine

/// Simple video player with tap-to-pause/restart (plays once, no loop)
struct LoopingVideoPlayer: View {
    let player: AVPlayer
    let videoId: Int  // Used for SwiftUI identity to detect video changes
    @State private var isPlaying = true
    @State private var hasEnded = false

    var body: some View {
        VideoPlayerView(player: player, videoId: videoId, hasEnded: $hasEnded)
            .onTapGesture {
                togglePlayPause()
            }
            .onAppear {
                print("LoopingVideoPlayer: Video \(videoId) view appeared")
                hasEnded = false
            }
            .onDisappear {
                player.pause()
                isPlaying = false
            }
    }

    private func togglePlayPause() {
        if hasEnded {
            // Video ended - restart from beginning
            player.seek(to: .zero)
            player.play()
            isPlaying = true
            hasEnded = false
        } else if isPlaying {
            // Currently playing - pause
            player.pause()
            isPlaying = false
        } else {
            // Currently paused (but not ended) - resume
            player.play()
            isPlaying = true
        }
    }
}

/// UIViewRepresentable wrapper for AVPlayerLayer
private struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let videoId: Int  // Forces view recreation when video changes
    @Binding var hasEnded: Bool

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player

        // Setup end observer for this video
        context.coordinator.setupEndObserver(for: player, hasEnded: $hasEnded)

        // Auto-play when view is created (works even if player not ready yet)
        player.play()
        print("LoopingVideoPlayer: Created view for video \(videoId) and started playback")

        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Only update if player changed
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
            context.coordinator.setupEndObserver(for: player, hasEnded: $hasEnded)
            player.play()
            print("LoopingVideoPlayer: Updated view with new player for video \(videoId)")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        private var endObserver: AnyCancellable?

        func setupEndObserver(for player: AVPlayer, hasEnded: Binding<Bool>) {
            // Remove previous observer if any
            endObserver?.cancel()

            // Observe when video ends and pause (no loop)
            endObserver = NotificationCenter.default.publisher(
                for: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem
            )
            .sink { [weak player] _ in
                // Pause video when it ends
                player?.pause()
                // Update binding to indicate video has ended
                DispatchQueue.main.async {
                    hasEnded.wrappedValue = true
                }
            }
        }

        deinit {
            endObserver?.cancel()
        }
    }
}

/// Custom UIView with AVPlayerLayer
private class PlayerUIView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
