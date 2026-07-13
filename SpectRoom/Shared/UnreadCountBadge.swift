//
//  UnreadCountBadge.swift
//  SpectRoom
//

import SwiftUI

struct UnreadCountBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(3)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.red)
                .clipShape(Circle())
        }
    }
}
