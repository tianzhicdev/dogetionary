//
//  BadgeAnimation.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

struct BadgeAnimation: View {
    let identifier: String
    var size: CGFloat = 40

    // Unified initializer - backend sends badge_id like "score_100" or "TIANZ"
    init(badgeId: String, size: CGFloat = 40) {
        self.identifier = "\(badgeId.lowercased())_badge"
        self.size = size
    }

    var body: some View {
        Image(identifier)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        BadgeAnimation(badgeId: "score_100", size: 50)
        BadgeAnimation(badgeId: "score_500", size: 50)
        BadgeAnimation(badgeId: "score_10000", size: 50)
        BadgeAnimation(badgeId: "TOEFL_BEGINNER", size: 50)
        BadgeAnimation(badgeId: "IELTS_ADVANCED", size: 50)
        BadgeAnimation(badgeId: "TIANZ", size: 50)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
