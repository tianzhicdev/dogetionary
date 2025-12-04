//
//  PronunciationService.swift
//  dogetionary
//
//  Handles pronunciation practice and evaluation
//

import Foundation

class PronunciationService: BaseNetworkService {
    static let shared = PronunciationService()

    private init() {
        super.init(category: "PronunciationService")
    }

    func practicePronunciation(originalText: String, audioData: Data, metadata: [String: Any], completion: @escaping (Result<PronunciationResult, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/pronunciation/practice") else {
            logger.error("Invalid URL for pronunciation practice endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Submitting pronunciation practice for text: '\(originalText)'")

        let audioBase64 = audioData.base64EncodedString()

        let requestBody: [String: Any] = [
            "user_id": userID,
            "original_text": originalText,
            "audio_data": audioBase64,
            "metadata": metadata
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode pronunciation practice request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        request.timeoutInterval = AppConstants.Network.standardTimeout

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error in pronunciation practice: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for pronunciation practice")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error in pronunciation practice: \(httpResponse.statusCode)")

                // Handle speech recognition failures from server
                if httpResponse.statusCode == 500, let data = data,
                   let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = responseDict["error"] as? String {

                    let result = PronunciationResult(
                        result: false,
                        similarityScore: 0.0,
                        recognizedText: "",
                        feedback: errorMessage
                    )
                    self.logger.info("Speech recognition failed, returning negative result")
                    completion(.success(result))
                    return
                }

                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for pronunciation practice")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let result = PronunciationResult(
                    result: responseDict?["result"] as? Bool ?? false,
                    similarityScore: responseDict?["similarity_score"] as? Double ?? 0.0,
                    recognizedText: responseDict?["recognized_text"] as? String ?? "",
                    feedback: responseDict?["feedback"] as? String ?? ""
                )

                self.logger.info("Successfully processed pronunciation practice")
                completion(.success(result))
            } catch {
                self.logger.error("Failed to decode pronunciation practice response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func submitPronunciationReview(
        audioData: Data,
        originalText: String,
        word: String,
        evaluationThreshold: Double = AppConstants.Validation.pronunciationThreshold
    ) async throws -> PronunciationEvaluationResult {
        let userID = UserManager.shared.getUserID()
        let learningLanguage = UserDefaults.standard.string(forKey: "learningLanguage") ?? "en"
        let nativeLanguage = UserDefaults.standard.string(forKey: "nativeLanguage") ?? "en"

        guard let url = URL(string: "\(baseURL)/v3/review/pronounce") else {
            logger.error("Invalid URL for pronunciation review endpoint")
            throw DictionaryError.invalidURL
        }

        logger.info("Submitting pronunciation review for word: '\(word)'")

        let audioBase64 = audioData.base64EncodedString()

        let requestBody: [String: Any] = [
            "user_id": userID,
            "word": word,
            "original_text": originalText,
            "audio_data": audioBase64,
            "learning_language": learningLanguage,
            "native_language": nativeLanguage,
            "evaluation_threshold": evaluationThreshold
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode pronunciation review request")
            throw DictionaryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        request.timeoutInterval = AppConstants.Network.standardTimeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type for pronunciation review")
            throw DictionaryError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("Server error in pronunciation review: \(httpResponse.statusCode)")
            throw DictionaryError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(PronunciationEvaluationResult.self, from: data)

        logger.info("Successfully processed pronunciation review - passed: \(result.passed), score: \(result.similarity_score)")

        return result
    }
}
