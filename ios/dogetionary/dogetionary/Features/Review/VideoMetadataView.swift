//
//  VideoMetadataView.swift
//  dogetionary
//
//  Displays movie title and year for video questions
//

import SwiftUI

struct VideoMetadataView: View {
    let metadata: VideoMetadata

    var displayTitle: String? {
        // Prefer movie_title, fallback to title
        return metadata.movie_title ?? metadata.title
    }

    var body: some View {
        if let title = displayTitle {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.smallTitleText)

                if let year = metadata.movie_year {
                    Text("(\(year))")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.bodyText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.panelFill.opacity(0.5))
            )
            .padding(.horizontal)
        }
    }
}

// MARK: - Preview

#Preview("With Movie Title and Year") {
    let metadata = VideoMetadata(
        movie_title: "The Killer's Game",
        movie_year: 2024,
        title: nil
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VideoMetadataView(metadata: metadata)
    }
}

#Preview("With Title Fallback") {
    let metadata = VideoMetadata(
        movie_title: nil,
        movie_year: nil,
        title: "diagnosis_example_01"
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VideoMetadataView(metadata: metadata)
    }
}

#Preview("With Movie Title Only") {
    let metadata = VideoMetadata(
        movie_title: "17 Miracles",
        movie_year: nil,
        title: nil
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VideoMetadataView(metadata: metadata)
    }
}
