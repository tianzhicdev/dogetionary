//
//  IllustrationService.swift
//  dogetionary
//
//  Handles AI-generated word illustrations
//

import Foundation

class IllustrationService: BaseNetworkService {
    static let shared = IllustrationService()

    private init() {
        super.init(category: "IllustrationService")
    }

    func getIllustration(word: String, language: String, completion: @escaping (Result<IllustrationResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/illustration") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let requestBody: [String: Any] = [
            "word": word,
            "language": language
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        logger.info("🎨 Getting illustration for word: \(word) (cache-first with generation fallback)")

        let task = NetworkClient.shared.dataTask(url: url, method: "POST", headers: headers, body: jsonData) { data, response, error in
            if let error = error {
                self.logger.error("❌ Get illustration request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Get illustration failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let illustrationResponse = try JSONDecoder().decode(IllustrationResponse.self, from: data)
                if illustrationResponse.cached == true {
                    self.logger.info("✅ Cached illustration retrieved for: \(word)")
                } else {
                    self.logger.info("✅ New illustration generated for: \(word)")
                }
                completion(.success(illustrationResponse))
            } catch {
                self.logger.error("Failed to decode illustration response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    func generateIllustration(word: String, language: String, completion: @escaping (Result<IllustrationResponse, Error>) -> Void) {
        // Backward compatibility: generateIllustration now just calls getIllustration
        getIllustration(word: word, language: language, completion: completion)
    }
}
