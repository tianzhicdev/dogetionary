//
//  UserManager.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import Foundation
import os.log

class UserManager: ObservableObject {
    static let shared = UserManager()
    private let logger = Logger(subsystem: "com.dogetionary.app", category: "UserManager")
    private let userIDKey = "DogetionaryUserID"
    
    @Published var userID: String
    
    private init() {
        // Try to load existing user ID from UserDefaults
        if let savedUserID = UserDefaults.standard.string(forKey: userIDKey) {
            self.userID = savedUserID
            logger.info("Loaded existing user ID: \(savedUserID)")
        } else {
            // Generate new UUID and save it
            let newUserID = UUID().uuidString
            self.userID = newUserID
            UserDefaults.standard.set(newUserID, forKey: userIDKey)
            logger.info("Generated new user ID: \(newUserID)")
        }
    }
    
    func getUserID() -> String {
        return userID
    }
}