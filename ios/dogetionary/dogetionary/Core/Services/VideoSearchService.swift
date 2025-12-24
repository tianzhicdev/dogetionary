//
//  VideoSearchService.swift
//  dogetionary
//
//  Handles video search and retrieval for words
//  Extends BaseNetworkService for proper NetworkClient integration
//

import Foundation

class VideoSearchService: BaseNetworkService {
    static let shared = VideoSearchService()

    private init() {
        super.init(category: "VideoSearchService")
    }

    // MARK: - Video Availability Check

    /// Check if word has videos in word_to_video table
    func checkWordHasVideos(word: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word

        guard let url = URL(string: "\(baseURL)/v3/api/check-word-videos?word=\(encodedWord)&lang=en") else {
            logger.error("Invalid URL for checkWordHasVideos: \(word)")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Checking if word '\(word)' has videos")

        performNetworkRequest(
            url: url,
            method: "GET",
            body: nil,
            responseType: VideoCheckResponse.self
        ) { result in
            switch result {
            case .success(let response):
                self.logger.info("Word '\(word)' has videos: \(response.has_videos)")
                completion(.success(response.has_videos))
            case .failure(let error):
                self.logger.error("Failed to check videos for '\(word)': \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Video Questions Retrieval

    /// Fetch video questions for a specific word
    func getVideoQuestionsForWord(word: String, limit: Int = 5, completion: @escaping (Result<[BatchReviewQuestion], Error>) -> Void) {
        let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word

        guard let url = URL(string: "\(baseURL)/v3/api/video-questions-for-word?word=\(encodedWord)&lang=en&limit=\(limit)") else {
            logger.error("Invalid URL for getVideoQuestionsForWord: \(word)")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching \(limit) video questions for word '\(word)'")

        performNetworkRequest(
            url: url,
            method: "GET",
            body: nil,
            responseType: VideoQuestionsResponse.self
        ) { result in
            switch result {
            case .success(let response):
                self.logger.info("Fetched \(response.questions.count) video questions for '\(word)'")
                completion(.success(response.questions))
            case .failure(let error):
                self.logger.error("Failed to fetch video questions for '\(word)': \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Async Video Search Trigger

    /// Trigger async video search on server (fire-and-forget)
    func triggerVideoSearch(word: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/api/trigger-video-search") else {
            logger.error("Invalid URL for triggerVideoSearch")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Triggering async video search for word '\(word)'")

        let requestBody: [String: String] = ["word": word, "learning_language": "en"]

        guard let bodyData = try? JSONEncoder().encode(requestBody) else {
            logger.error("Failed to encode request body for triggerVideoSearch")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        let task = NetworkClient.shared.dataTask(
            url: url,
            method: "POST",
            headers: headers,
            body: bodyData
        ) { data, response, error in
            if let error = error {
                self.logger.error("Failed to trigger video search: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response for triggerVideoSearch")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                self.logger.info("Video search triggered successfully for '\(word)'")
                completion(.success(()))
            } else {
                self.logger.error("Server error triggering video search: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }

        task.resume()
    }
}

// MARK: - Response Models

struct VideoCheckResponse: Codable {
    let has_videos: Bool
}

struct VideoQuestionsResponse: Codable {
    let word: String
    let questions: [BatchReviewQuestion]
    let count: Int
}
