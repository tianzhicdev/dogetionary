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
    let allowWordTap: Bool  // If false, disable clickable text (for mc_def_native)

    enum DisplayStyle {
        case idBadgeAndText  // Shows "A" + option.text (for MC and Video)
        case textOnly        // Shows option.text only (for Fill Blank)
    }

    init(option: QuestionOption, style: DisplayStyle, isSelected: Bool, isCorrect: Bool, correctAnswer: String?, showFeedback: Bool, onTap: @escaping () -> Void, allowWordTap: Bool = true) {
        self.option = option
        self.style = style
        self.isSelected = isSelected
        self.isCorrect = isCorrect
        self.correctAnswer = correctAnswer
        self.showFeedback = showFeedback
        self.onTap = onTap
        self.allowWordTap = allowWordTap
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
            // Feedback icons (after answer submission)
            if showFeedback && (isSelected || shouldShowAsCorrect) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? AppTheme.successColor : AppTheme.errorColor)
                    .font(.title3)
                    .shadow(color: AppTheme.black.opacity(0.6), radius: 2, y: 1)
            }

            switch style {
            case .idBadgeAndText:
                // Option ID (A, B, C, D)
                Text(option.id)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.selectableTint)
                    .frame(width: 32, height: 32)

                // Option Text + Native Translation
                VStack(alignment: .leading, spacing: 4) {
                    // Main text - clickable or plain based on allowWordTap
                    if allowWordTap {
                        ClickableTextView(
                            text: option.text,
                            font: .body.weight(.medium),
                            foregroundColor: AppTheme.bodyText,
                            alignment: .leading
                        )
                    } else {
                        Text(option.text)
                            .font(.body.weight(.medium))
                            .foregroundColor(AppTheme.bodyText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Native language translation (if available)
                    if let textNative = option.text_native {
                        Text(textNative)
                            .font(.caption)
                            .foregroundColor(AppTheme.bodyText.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .textOnly:
                // Option Text + Native Translation
                VStack(alignment: .leading, spacing: 4) {
                    // Main text (word) - clickable or plain based on allowWordTap
                    if allowWordTap {
                        ClickableTextView(
                            text: option.text,
                            font: .headline.weight(.semibold),
                            foregroundColor: AppTheme.bodyText,
                            alignment: .leading
                        )
                    } else {
                        Text(option.text)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(AppTheme.bodyText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Native language translation (if available)
                    if let textNative = option.text_native {
                        Text(textNative)
                            .font(.caption)
                            .foregroundColor(AppTheme.bodyText.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Square checkbox button for selection
            Button(action: onTap) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.selectableTint, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.selectableTint)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(showFeedback)
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
