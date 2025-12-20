//
//  ScheduleService.swift
//  dogetionary
//
//  Handles test preparation schedules and progress tracking
//

import Foundation

class ScheduleService: BaseNetworkService {
    static let shared = ScheduleService()

    private init() {
        super.init(category: "ScheduleService")
    }

    func getTodaySchedule(completion: @escaping (Result<DailyScheduleEntry, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/schedule/today?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for today schedule endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching today's schedule for user: \(userID)")

        let headers = ["Accept": "application/json"]

        let task = NetworkClient.shared.dataTask(url: url, method: "GET", headers: headers) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching today schedule: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for today schedule")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching today schedule: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for today schedule")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let scheduleEntry = try JSONDecoder().decode(DailyScheduleEntry.self, from: data)
                self.logger.info("Successfully fetched today's schedule - has_schedule: \(scheduleEntry.has_schedule)")
                completion(.success(scheduleEntry))
            } catch {
                self.logger.error("Failed to decode today schedule response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    func getScheduleRange(days: Int = 7, onlyNewWords: Bool = true, completion: @escaping (Result<GetScheduleRangeResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        let onlyNewWordsParam = onlyNewWords ? "true" : "false"
        guard let url = URL(string: "\(baseURL)/v3/schedule/range?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)&days=\(days)&only_new_words=\(onlyNewWordsParam)") else {
            logger.error("Invalid URL for schedule range endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching schedule range for \(days) days (only new words: \(onlyNewWords))")

        let headers = ["Accept": "application/json"]

        let task = NetworkClient.shared.dataTask(url: url, method: "GET", headers: headers) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching schedule range: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for schedule range")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for schedule range")
                completion(.failure(DictionaryError.noData))
                return
            }

            if httpResponse.statusCode != 200 {
                self.logger.error("Schedule range request failed with status \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            do {
                let decoder = JSONDecoder()
                let scheduleRangeResponse = try decoder.decode(GetScheduleRangeResponse.self, from: data)
                self.logger.info("Successfully fetched schedule range with \(scheduleRangeResponse.schedules.count) days")
                completion(.success(scheduleRangeResponse))
            } catch {
                self.logger.error("Failed to decode schedule range response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    func getTestProgress(completion: @escaping (Result<TestProgressResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/schedule/test-progress?user_id=\(userID)") else {
            logger.error("Invalid URL for test progress endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching test progress for user: \(userID)")
        performNetworkRequest(url: url, responseType: TestProgressResponse.self, completion: completion)
    }
}
