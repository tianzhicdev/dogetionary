//
//  AppVersionService.swift
//  dogetionary
//
//  Handles app version checking and forced updates
//

import Foundation

class AppVersionService: BaseNetworkService {
    static let shared = AppVersionService()

    private init() {
        super.init(category: "AppVersionService")
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppConstants.Version.defaultVersion
    }

    func checkAppVersion(completion: @escaping (Result<AppVersionResponse, Error>) -> Void) {
        let version = AppVersionService.appVersion
        guard let url = URL(string: "\(baseURL)/v3/app-version?platform=ios&version=\(version)") else {
            logger.error("Invalid URL for app-version endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Checking app version: \(version)")
        performNetworkRequest(url: url, responseType: AppVersionResponse.self, completion: completion)
    }
}
