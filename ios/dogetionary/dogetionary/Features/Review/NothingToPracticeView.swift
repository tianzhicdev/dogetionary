//
//  NothingToPracticeView.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

struct NothingToPracticeView: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("All Caught Up!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.bigTitleText)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Nothing to Practice") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        NothingToPracticeView()
    }
}
