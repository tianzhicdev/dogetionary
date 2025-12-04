//
//  LeaderboardService.swift
//  dogetionary
//
//  Handles leaderboard rankings, achievements, and streak tracking
//

import Foundation

class LeaderboardService: BaseNetworkService {
    static let shared = LeaderboardService()

    private init() {
        super.init(category: "LeaderboardService")
    }

    func getLeaderboard(completion: @escaping (Result<[LeaderboardEntry], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/leaderboard-score") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("🏆 Fetching leaderboard")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                self.logger.error("❌ Leaderboard request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Leaderboard request failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }

            self.logger.info("✅ Leaderboard response received: \(data.count) bytes")

            do {
                let leaderboardResponse = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
                self.logger.info("✅ Leaderboard decoded: \(leaderboardResponse.leaderboard.count) entries")
                completion(.success(leaderboardResponse.leaderboard))
            } catch {
                self.logger.error("Failed to decode leaderboard response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func getStreakDays(completion: @escaping (Result<StreakDaysResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/get-streak-days?user_id=\(userID)") else {
            logger.error("Invalid URL for streak days endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching streak days for user: \(userID)")
        performNetworkRequest(url: url, responseType: StreakDaysResponse.self, completion: completion)
    }

    func getAchievementProgress(completion: @escaping (Result<AchievementProgressResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/achievements/progress?user_id=\(userID)") else {
            logger.error("Invalid URL for achievements endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching achievement progress for user: \(userID)")
        performNetworkRequest(url: url, responseType: AchievementProgressResponse.self, completion: completion)
    }

    func getTestVocabularyAwards(completion: @escaping (Result<TestVocabularyAwardsResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/achievements/test-vocabulary-awards?user_id=\(userID)") else {
            logger.error("Invalid URL for test-vocabulary-awards endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching test vocabulary awards for user: \(userID)")
        performNetworkRequest(url: url, responseType: TestVocabularyAwardsResponse.self, completion: completion)
    }
}
