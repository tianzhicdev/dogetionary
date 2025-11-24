//
//  ForceUpgradeView.swift
//  dogetionary
//
//  Created by AI Assistant on 11/23/25.
//

import SwiftUI

/// A full-screen blocking view that requires the user to upgrade the app
struct ForceUpgradeView: View {
    let upgradeURL: String
    let message: String?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon placeholder
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)

                VStack(spacing: 16) {
                    Text("Update Required")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(message ?? "Please update to the latest version to continue using Unforgettable Dictionary.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Update button
                Button(action: openAppStore) {
                    HStack {
                        Image(systemName: "arrow.down.app.fill")
                        Text("Update Now")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }

    private func openAppStore() {
        guard let url = URL(string: upgradeURL) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ForceUpgradeView(
        upgradeURL: "https://apps.apple.com/app/id6752226667",
        message: "A new version with important updates is available. Please update to continue."
    )
}
