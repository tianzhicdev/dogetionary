//
//  LoopingVideoPlayer.swift
//  dogetionary
//
//  Simple video player with tap-to-pause and auto-loop
//

import SwiftUI
import AVFoundation
import Combine

/// Simple looping video player with tap-to-pause
struct LoopingVideoPlayer: View {
    let player: AVPlayer
    @State private var isPlaying = true

    var body: some View {
        VideoPlayerView(player: player)
            .onTapGesture {
                togglePlayPause()
            }
            .onAppear {
                player.play()
                isPlaying = true
            }
            .onDisappear {
                player.pause()
                isPlaying = false
            }
    }

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}

/// UIViewRepresentable wrapper for AVPlayerLayer
private struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player

        // Setup looping observer
        context.coordinator.setupLoopingObserver(for: player)

        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        private var loopObserver: AnyCancellable?

        func setupLoopingObserver(for player: AVPlayer) {
            // Remove previous observer if any
            loopObserver?.cancel()

            // Observe when video ends and restart
            loopObserver = NotificationCenter.default.publisher(
                for: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem
            )
            .sink { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        deinit {
            loopObserver?.cancel()
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
