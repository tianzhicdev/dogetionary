//
//  AudioRecorder.swift
//  dogetionary
//
//  Created for pronunciation practice feature
//

import SwiftUI
import AVFoundation
import Combine
import OSLog

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioData: Data?
    @Published var currentVolume: Float = 0.0
    @Published var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession = AVAudioSession.sharedInstance()
    private let logger = Logger()
    private var volumeTimer: Timer?

    override init() {
        super.init()
        setupRecording()
    }

    deinit {
        stopRecording()
        volumeTimer?.invalidate()
    }

    private func setupRecording() {
        recordingSession.requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    self?.logger.info("Microphone permission granted")
                } else {
                    self?.logger.error("Microphone permission denied")
                }
            }
        }
    }

    func startRecording() {
        // Clean up any previous recording
        stopRecording()

        // Reset audio session with Bluetooth support
        do {
            try recordingSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try recordingSession.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error)")
        }

        // Use unique filename to avoid conflicts
        let timestamp = Date().timeIntervalSince1970
        let audioFilename = getDocumentsDirectory().appendingPathComponent("pronunciation_\(timestamp).wav")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ] as [String : Any]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            isRecording = true
            startVolumeMonitoring()
            logger.info("Started recording pronunciation to: \(audioFilename.lastPathComponent)")
        } catch {
            logger.error("Could not start recording: \(error)")
        }
    }

    func stopRecording() {
        stopVolumeMonitoring()

        guard let recorder = audioRecorder else {
            isRecording = false
            return
        }

        if recorder.isRecording {
            recorder.stop()
        }

        isRecording = false

        // Save the recording URL
        recordingURL = recorder.url

        // Read the audio data
        if let data = try? Data(contentsOf: recorder.url) {
            audioData = data
            logger.info("Recording stopped, data size: \(data.count) bytes")
        } else {
            logger.error("Failed to read audio data from: \(recorder.url)")
        }

        // Clean up recorder but keep the file
        audioRecorder = nil

        // Deactivate audio session
        do {
            try recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths.first ?? FileManager.default.temporaryDirectory
    }

    private func startVolumeMonitoring() {
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateVolume()
        }
    }

    private func stopVolumeMonitoring() {
        volumeTimer?.invalidate()
        volumeTimer = nil
        currentVolume = 0.0
    }

    private func updateVolume() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalizedVolume = pow(10.0, averagePower / 20.0)

        DispatchQueue.main.async {
            self.currentVolume = Float(normalizedVolume)
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            logger.info("Recording finished successfully")
        } else {
            logger.error("Recording failed")
        }
    }
}