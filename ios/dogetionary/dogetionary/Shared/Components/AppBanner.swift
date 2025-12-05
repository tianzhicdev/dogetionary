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
            // Banner 1
            Image("banner1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 22)

            // Banner 2
            Image("banner2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(AppTheme.clear)
    }
}

#Preview {
    AppBanner()
}
