//
//  TabBarPreferenceKey.swift
//  dogetionary
//
//  Created by Claude on 10/8/25.
//

import SwiftUI

struct TabBarPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func captureTabFrame(for tag: Int) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TabBarPreferenceKey.self,
                    value: [tag: geometry.frame(in: .global)]
                )
            }
        )
    }
}
