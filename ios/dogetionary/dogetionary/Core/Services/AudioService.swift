//
//  AudioService.swift
//  dogetionary
//
//  Handles text-to-speech audio fetching and caching
//

import Foundation

class AudioService: BaseNetworkService {
    static let shared = AudioService()

    private init() {
        super.init(category: "AudioService")
    }

    func fetchAudioForText(_ text: String, language: String, completion: @escaping (Data?) -> Void) {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/v3/audio/\(encodedText)/\(language)") else {
            logger.error("Invalid URL for text: '\(text)' language: \(language)")
            completion(nil)
            return
        }

        logger.info("Fetching/generating audio for text: '\(text)' in \(language)")

        let headers = ["Accept": "application/json"]

        let task = NetworkClient.shared.dataTask(url: url, method: "GET", headers: headers) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching audio: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for audio")
                completion(nil)
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching audio: \(httpResponse.statusCode)")
                completion(nil)
                return
            }

            guard let data = data else {
                self.logger.error("No audio data received")
                completion(nil)
                return
            }

            do {
                let audioResponse = try JSONDecoder().decode(AudioDataResponse.self, from: data)
                let audioData = Data(base64Encoded: audioResponse.audio_data)

                if audioResponse.generated == true {
                    self.logger.info("Successfully generated and fetched audio for text: '\(text)'")
                } else {
                    self.logger.info("Successfully fetched cached audio for text: '\(text)'")
                }

                completion(audioData)
            } catch {
                self.logger.error("Failed to decode audio response: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }
}
