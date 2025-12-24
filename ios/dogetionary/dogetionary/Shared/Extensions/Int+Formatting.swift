//
//  Int+Formatting.swift
//  dogetionary
//
//  Reusable integer formatting utilities
//

import Foundation

extension Int {
    /// Format word count for display (e.g., "1,247 words" or "3.5K words")
    func formatAsWordCount() -> String {
        if self >= 10000 {
            let k = Double(self) / 1000.0
            return String(format: "%.1fK words", k)
        } else if self >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let formatted = formatter.string(from: NSNumber(value: self)) ?? "\(self)"
            return "\(formatted) words"
        } else {
            return "\(self) words"
        }
    }

    /// Format time commitment display (converts minutes to hours if >= 60)
    /// - Returns: String representation of minutes or hours (e.g., "45" for 45 min, "1.5" for 90 min)
    func formatAsTimeCommitment() -> String {
        if self < 60 {
            return "\(self)"
        } else {
            let hours = Double(self) / 60.0
            if hours == Double(Int(hours)) {
                return "\(Int(hours))"
            } else {
                return String(format: "%.1f", hours)
            }
        }
    }
}
