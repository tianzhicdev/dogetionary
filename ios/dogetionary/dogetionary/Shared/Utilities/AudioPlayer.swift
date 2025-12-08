//
//  AudioPlayer.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import Foundation
import AVFoundation
import os.log

class AudioPlayer: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.shojin.app", category: "AudioPlayer")
    
    @Published var isPlaying = false
    @Published var errorMessage: String?
    
    func playAudio(from data: Data) {
        do {
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Create player from data
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            
            // Play audio
            if let player = player {
                player.play()
                isPlaying = true
                errorMessage = nil
                logger.info("Started playing audio")
            }
            
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
            isPlaying = false
        }
    }
    
    func stopAudio() {
        player?.stop()
        isPlaying = false
        logger.info("Stopped playing audio")
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
        logger.info("Audio finished playing successfully: \(flag)")
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.errorMessage = error?.localizedDescription ?? "Audio decode error"
        }
        logger.error("Audio decode error: \(error?.localizedDescription ?? "Unknown error")")
    }
}