//
//  BadgePill.swift
//  dogetionary
//
//  Reusable badge/pill component for tags, labels, and status indicators
//

import SwiftUI

struct BadgePill: View {
    let text: String
    let color: Color
    let size: BadgeSize

    enum BadgeSize {
        case small
        case medium
        case large

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            case .large: return 14
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 4
            case .large: return 6
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }

    init(
        _ text: String,
        color: Color = AppTheme.accentCyan,
        size: BadgeSize = .medium
    ) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size.fontSize, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(color.opacity(0.15))
            .cornerRadius(size.cornerRadius)
    }
}

// MARK: - Preview

#Preview("Badge Sizes") {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            BadgePill("Small", color: AppTheme.accentCyan, size: .small)
            BadgePill("Medium", color: AppTheme.accentPink, size: .medium)
            BadgePill("Large", color: AppTheme.neonPurple, size: .large)
        }

        HStack(spacing: 12) {
            BadgePill("English", color: AppTheme.accentCyan)
            BadgePill("Advanced", color: AppTheme.electricYellow)
            BadgePill("New", color: AppTheme.successColor)
        }

        HStack(spacing: 12) {
            BadgePill("TOEFL", color: AppTheme.selectableTint, size: .small)
            BadgePill("IELTS", color: AppTheme.accentPink, size: .small)
            BadgePill("Business", color: AppTheme.neonPurple, size: .small)
        }
    }
    .padding()
    .background(AppTheme.bgPrimary)
}
