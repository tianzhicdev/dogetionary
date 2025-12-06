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

    init(milestone: Int, size: CGFloat = 40) {
        self.identifier = "score_\(milestone)_badge"
        self.size = size
    }

    init(testName: String, size: CGFloat = 40) {
        self.identifier = "\(testName.lowercased())_badge"
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
        BadgeAnimation(milestone: 100, size: 50)
        BadgeAnimation(milestone: 500, size: 50)
        BadgeAnimation(milestone: 10000, size: 50)
        BadgeAnimation(testName: "TOEFL_BEGINNER", size: 50)
        BadgeAnimation(testName: "IELTS_ADVANCED", size: 50)
        BadgeAnimation(testName: "TIANZ", size: 50)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
