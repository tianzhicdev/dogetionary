//
//  OptionButton.swift
//  dogetionary
//
//  Unified option button component for multiple choice questions
//  Supports both ID badge style (A, B, C, D) and word-only style
//

import SwiftUI

struct OptionButton: View {
    let option: QuestionOption
    let style: DisplayStyle
    let isSelected: Bool
    let isCorrect: Bool
    let correctAnswer: String?
    let showFeedback: Bool
    let onTap: () -> Void

    enum DisplayStyle {
        case idBadgeAndText  // Shows "A" + option.text (for MC and Video)
        case textOnly        // Shows option.text only (for Fill Blank)
    }

    // Show this option as correct if user was wrong and this is the correct answer
    var shouldShowAsCorrect: Bool {
        showFeedback && !isSelected && isCorrect
    }

    var backgroundGradient: LinearGradient {
        return AppTheme.feedbackGradient(
            isCorrect: isCorrect,
            isSelected: isSelected,
            showFeedback: showFeedback,
            shouldShowAsCorrect: shouldShowAsCorrect
        )
    }

    var borderGradient: LinearGradient? {
        return AppTheme.feedbackBorderGradient(
            isCorrect: isCorrect,
            isSelected: isSelected,
            showFeedback: showFeedback
        )
    }

    var shadowColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? AppTheme.successColor.opacity(0.8) : AppTheme.errorColor.opacity(0.8)
        } else if shouldShowAsCorrect {
            return AppTheme.successColor.opacity(0.6)
        } else if isSelected {
            return AppTheme.accentCyan.opacity(0.6)
        }
        return AppTheme.clear
    }

    var body: some View {
        HStack {
            // Checkbox button for selection
            Button(action: onTap) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppTheme.selectableTint : AppTheme.smallTitleText.opacity(0.3))
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(showFeedback)

            switch style {
            case .idBadgeAndText:
                // Option ID (A, B, C, D)
                Text(option.id)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.selectableTint)
                    .frame(width: 32, height: 32)

                // Option Text - clickable for word lookup
                ClickableTextView(
                    text: option.text,
                    font: .body.weight(.medium),
                    foregroundColor: AppTheme.bodyText,
                    alignment: .leading
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .textOnly:
                // Option Text (word) - clickable for word lookup
                ClickableTextView(
                    text: option.text,
                    font: .headline.weight(.semibold),
                    foregroundColor: AppTheme.bodyText,
                    alignment: .center
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }

            // Feedback icons (after answer submission)
            if showFeedback && (isSelected || shouldShowAsCorrect) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? AppTheme.successColor : AppTheme.errorColor)
                    .font(.title3)
                    .shadow(color: AppTheme.black.opacity(0.6), radius: 2, y: 1)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Option Button - ID Badge Style Not Selected") {
    let sampleOption = QuestionOption(id: "A", text: "Lasting for a very short time")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            OptionButton(
                option: sampleOption,
                style: .idBadgeAndText,
                isSelected: false,
                isCorrect: true,
                correctAnswer: "A",
                showFeedback: false,
                onTap: { }
            )
            .padding()
        }
    }
}

#Preview("Option Button - ID Badge Style Selected Correct") {
    let sampleOption = QuestionOption(id: "A", text: "Lasting for a very short time")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            OptionButton(
                option: sampleOption,
                style: .idBadgeAndText,
                isSelected: true,
                isCorrect: true,
                correctAnswer: "A",
                showFeedback: true,
                onTap: { }
            )
            .padding()
        }
    }
}

#Preview("Option Button - ID Badge Style Selected Wrong") {
    let sampleOption = QuestionOption(id: "B", text: "Eternal and unchanging")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            OptionButton(
                option: sampleOption,
                style: .idBadgeAndText,
                isSelected: true,
                isCorrect: false,
                correctAnswer: "A",
                showFeedback: true,
                onTap: { }
            )
            .padding()
        }
    }
}

#Preview("Option Button - Text Only Style Selected Correct") {
    let sampleOption = QuestionOption(id: "A", text: "beautiful")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            OptionButton(
                option: sampleOption,
                style: .textOnly,
                isSelected: true,
                isCorrect: true,
                correctAnswer: "A",
                showFeedback: true,
                onTap: { }
            )
            .padding()
        }
    }
}

#Preview("Option Button - Text Only Style Selected Wrong") {
    let sampleOption = QuestionOption(id: "B", text: "careful")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            OptionButton(
                option: sampleOption,
                style: .textOnly,
                isSelected: true,
                isCorrect: false,
                correctAnswer: "A",
                showFeedback: true,
                onTap: { }
            )
            .padding()
        }
    }
}
