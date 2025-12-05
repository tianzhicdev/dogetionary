//
//  AnimatedScoreStar.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI
import Lottie

struct AnimatedScoreStar: View {
    var size: CGFloat = 25

    var body: some View {
        LottieView(animation: .named("animated_star"))
            .playing(loopMode: .loop)
            .frame(width: size, height: size)
    }
}

#Preview {
    AnimatedScoreStar()
}
