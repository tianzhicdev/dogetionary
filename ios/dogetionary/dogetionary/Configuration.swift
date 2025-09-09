//
//  Configuration.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import Foundation

struct Configuration {
    
    enum Environment {
        case development
        case production
        
        var baseURL: String {
            switch self {
            case .development:
                return "http://localhost:5000"
            case .production:
                return "https://dogetionary.webhop.net/api"
            }
        }
    }
    
    // Change this to switch between local and remote
    #if DEBUG
    static let environment: Environment = .development
    #else
    static let environment: Environment = .production
    #endif
    
    static var baseURL: String {
        return environment.baseURL
    }
    
    // Override for manual testing - set this to force production mode in debug builds
    static var forceProduction: Bool {
        UserDefaults.standard.bool(forKey: "forceProduction")
    }
    
    static var effectiveBaseURL: String {
        if forceProduction {
            return Environment.production.baseURL
        }
        return baseURL
    }
}
