//
//  AppBanner.swift
//  dogetionary
//
//  Created by AI Assistant on 2025.
//

import SwiftUI

struct AppBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            // Logo
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            // App title
            Text("Unforgettable Dictionary")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray4)),
            alignment: .bottom
        )
    }
}

#Preview {
    AppBanner()
}