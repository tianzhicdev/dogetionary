//
//  UserPreferencesService.swift
//  dogetionary
//
//  Handles user preferences and settings
//

import Foundation

class UserPreferencesService: BaseNetworkService {
    static let shared = UserPreferencesService()

    private init() {
        super.init(category: "UserPreferencesService")
    }

    func getUserPreferences(userID: String, completion: @escaping (Result<UserPreferences, Error>) -> Void) {
        guard let encodedUserID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/v3/users/\(encodedUserID)/preferences") else {
            logger.error("Invalid URL for user preferences GET endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching user preferences for: \(userID)")

        let headers = ["Accept": "application/json"]

        let task = NetworkClient.shared.dataTask(url: url, method: "GET", headers: headers) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching user preferences: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for user preferences")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching user preferences: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for user preferences")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
                self.logger.info("Successfully fetched user preferences")
                completion(.success(preferences))
            } catch {
                self.logger.error("Failed to decode user preferences response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    func updateUserPreferences(userID: String, learningLanguage: String, nativeLanguage: String, userName: String, userMotto: String, testPrep: String? = nil, studyDurationDays: Int? = nil, dailyTimeCommitmentMinutes: Int? = nil, timezone: String? = nil, completion: @escaping (Result<UserPreferences, Error>) -> Void) {
        guard let encodedUserID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/v3/users/\(encodedUserID)/preferences") else {
            logger.error("Invalid URL for user preferences POST endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Updating user preferences for: \(userID)")

        var requestBody: [String: Any] = [
            "learning_language": learningLanguage,
            "native_language": nativeLanguage,
            "user_name": userName,
            "user_motto": userMotto
        ]

        if let testPrep = testPrep {
            requestBody["test_prep"] = testPrep
        }

        if let studyDurationDays = studyDurationDays {
            requestBody["study_duration_days"] = studyDurationDays
        }

        if let dailyTimeCommitmentMinutes = dailyTimeCommitmentMinutes {
            requestBody["daily_time_commitment_minutes"] = dailyTimeCommitmentMinutes
        }

        if let timezone = timezone {
            requestBody["timezone"] = timezone
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode user preferences request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        let task = NetworkClient.shared.dataTask(url: url, method: "POST", headers: headers, body: jsonData) { data, response, error in
            if let error = error {
                self.logger.error("Network error updating user preferences: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for user preferences update")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error updating user preferences: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for user preferences update")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
                self.logger.info("Successfully updated user preferences")
                completion(.success(preferences))
            } catch {
                self.logger.error("Failed to decode user preferences update response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }

        task.resume()
    }

    func submitFeedback(feedback: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/feedback") else {
            logger.error("Invalid URL for feedback endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let body: [String: Any] = [
            "user_id": userID,
            "feedback": feedback
        ]

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            logger.error("Failed to encode feedback request: \(error)")
            completion(.failure(error))
            return
        }

        let headers = ["Content-Type": "application/json"]

        let task = NetworkClient.shared.dataTask(url: url, method: "POST", headers: headers, body: jsonData) { data, response, error in
            if let error = error {
                self.logger.error("Network error submitting feedback: \(error)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for feedback submission")
                completion(.failure(DictionaryError.noData))
                return
            }

            if httpResponse.statusCode == 201 {
                self.logger.info("Successfully submitted feedback")
                completion(.success(true))
            } else {
                self.logger.error("Failed to submit feedback. Status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }

        task.resume()
    }
}
