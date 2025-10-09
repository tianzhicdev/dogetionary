//
//  OnboardingTooltipView.swift
//  dogetionary
//
//  Created by Claude on 10/8/25.
//

import SwiftUI

struct OnboardingTooltipView: View {
    let title: String
    let message: String
    let buttonText: String
    let onNext: () -> Void
    let onSkip: () -> Void
    let arrowPosition: ArrowPosition

    enum ArrowPosition {
        case top
        case bottom
    }

    var body: some View {
        VStack(spacing: 16) {
            if arrowPosition == .bottom {
                tooltipContent
                arrow
            } else {
                arrow
                tooltipContent
            }
        }
    }

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)

            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(action: onNext) {
                    Text(buttonText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
            }

            Button(action: onSkip) {
                Text("Skip Tutorial")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: 280)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    private var arrow: some View {
        Triangle()
            .fill(Color(uiColor: .systemBackground))
            .frame(width: 20, height: 10)
            .rotationEffect(.degrees(arrowPosition == .bottom ? 180 : 0))
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        OnboardingTooltipView(
            title: "Search New Words",
            message: "This is where you can search for new words",
            buttonText: "Next",
            onNext: {},
            onSkip: {},
            arrowPosition: .bottom
        )
    }
}
