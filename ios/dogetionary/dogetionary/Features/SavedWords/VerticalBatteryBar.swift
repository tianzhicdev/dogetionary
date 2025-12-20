//
//  VerticalBatteryBar.swift
//  dogetionary
//
//  Created by Claude Code on 12/20/24.
//

import SwiftUI

/// Vertical battery-style progress indicator showing word mastery level (1-7 scale)
struct VerticalBatteryBar: View {
    let level: Int  // 1-7 scale from backend

    private var progressColor: LinearGradient {
        LinearGradient(
            colors: [AppTheme.selectableTint, AppTheme.neonPurple],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emptyColor: Color {
        AppTheme.panelFill.opacity(0.3)
    }

    var body: some View {
        VStack(spacing: 1) {
            // Display segments from top to bottom (7 to 1)
            ForEach((1...7).reversed(), id: \.self) { segment in
                let isFilled = segment <= level

                Capsule()
                    .fill(isFilled ? AnyShapeStyle(progressColor) : AnyShapeStyle(emptyColor))
                    .frame(width: 8, height: 4)
            }
        }
        .frame(width: 8, height: 32)
    }
}

// MARK: - Preview

#Preview("Vertical Battery Bar") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            ForEach(1...7, id: \.self) { level in
                VStack(spacing: 4) {
                    VerticalBatteryBar(level: level)
                    Text("L\(level)")
                        .font(.caption2)
                        .foregroundColor(AppTheme.smallTitleText)
                }
            }
        }
        .padding()
        .background(AppTheme.panelFill)
    }
    .padding()
    .background(AppTheme.verticalGradient2)
}
