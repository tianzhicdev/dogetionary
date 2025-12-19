//
//  ReviewService.swift
//  dogetionary
//
//  Handles spaced repetition reviews and practice sessions
//

import Foundation

class ReviewService: BaseNetworkService {
    static let shared = ReviewService()

    private init() {
        super.init(category: "ReviewService")
    }

    // MARK: - Due Words

    func getDueWords(completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        WordService.shared.getSavedWords(dueOnly: true, completion: completion)
    }

    func getDueCounts(completion: @escaping (Result<DueCountsResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/due_counts?user_id=\(userID)") else {
            logger.error("Invalid URL for due counts endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching due counts for user: \(userID)")

        let task = NetworkClient.shared.dataTask(url: url) { data, response, error in
            if let error = error {
                self.logger.error("Network error getting due counts: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type getting due counts")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("HTTP error getting due counts: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received getting due counts")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let response = try JSONDecoder().decode(DueCountsResponse.self, from: data)
                self.logger.info("Successfully fetched due counts - overdue: \(response.overdue_count), total: \(response.total_count)")
                completion(.success(response))
            } catch {
                self.logger.error("Failed to decode due counts response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    // MARK: - Review Submission

    func submitReview(word: String, learningLanguage: String, nativeLanguage: String, response: Bool, questionType: String? = nil, completion: @escaping (Result<ReviewSubmissionResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/reviews/submit") else {
            logger.error("Invalid URL for review submission endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Submitting review - Word: \(word), Response: \(response), Question Type: \(questionType ?? "recognition"), User: \(userID)")

        let reviewRequest = EnhancedReviewSubmissionRequest(
            user_id: userID,
            word: word,
            learning_language: learningLanguage,
            native_language: nativeLanguage,
            response: response,
            question_type: questionType
        )

        let body: Data
        do {
            body = try JSONEncoder().encode(reviewRequest)
        } catch {
            logger.error("Failed to encode review request: \(error.localizedDescription)")
            completion(.failure(DictionaryError.decodingError(error)))
            return
        }

        let headers = ["Content-Type": "application/json"]

        let task = NetworkClient.shared.dataTask(url: url, method: "POST", headers: headers, body: body) { data, response, error in
            if let error = error {
                self.logger.error("Network error submitting review: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for review submission")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error submitting review: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for review submission")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let reviewResponse = try JSONDecoder().decode(ReviewSubmissionResponse.self, from: data)
                self.logger.info("Successfully submitted review for word: \(word)")
                completion(.success(reviewResponse))
            } catch {
                self.logger.error("Failed to decode review submission response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    // MARK: - Batch Reviews

    func getReviewWordsBatch(count: Int, excludeWords: [String] = [], completion: @escaping (Result<BatchReviewResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        var urlString = "\(baseURL)/v3/next-review-words-batch?user_id=\(userID)&count=\(count)"

        if !excludeWords.isEmpty {
            let encoded = excludeWords.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlString += "&exclude_words=\(encoded)"
        }

        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL for batch review endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching batch review words: count=\(count), excluding=\(excludeWords.count) words")

        let task = NetworkClient.shared.dataTask(url: url) { data, response, error in
            if let error = error {
                self.logger.error("Network error getting batch reviews: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type getting batch reviews")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("HTTP error getting batch reviews: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received getting batch reviews")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let response = try JSONDecoder().decode(BatchReviewResponse.self, from: data)
                self.logger.info("Successfully fetched \(response.questions.count) batch questions, has_more=\(response.has_more)")
                completion(.success(response))
            } catch {
                self.logger.error("Failed to decode batch review response: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    self.logger.error("Detailed decoding error: \(decodingError)")
                }
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    // MARK: - Review Stats

    func getReviewProgressStats(completion: @escaping (Result<ReviewProgressStats, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/reviews/progress_stats?user_id=\(userID)") else {
            logger.error("Invalid URL for review progress stats endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let task = NetworkClient.shared.dataTask(url: url) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching review progress stats: \(error)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for review progress stats")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let stats = try JSONDecoder().decode(ReviewProgressStats.self, from: data)
                self.logger.info("Successfully decoded review progress stats")
                completion(.success(stats))
            } catch {
                self.logger.error("Failed to decode review progress stats: \(error)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    func getPracticeStatus(completion: @escaping (Result<PracticeStatusResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/practice-status?user_id=\(userID)") else {
            logger.error("Invalid URL for practice-status endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching practice status for user: \(userID)")
        performNetworkRequest(url: url, responseType: PracticeStatusResponse.self, completion: completion)
    }

    func getForgettingCurve(wordId: Int, completion: @escaping (Result<ForgettingCurveResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/words/\(wordId)/forgetting-curve?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for forgetting curve endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching forgetting curve for word ID: \(wordId), user: \(userID)")

        performNetworkRequest(
            url: url,
            method: "GET",
            body: nil,
            responseType: ForgettingCurveResponse.self,
            completion: completion
        )
    }
}
