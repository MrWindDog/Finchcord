//
//  GuildIconView.swift
//  Stossycord
//
//  Created by Stossy11 on 20/9/2024.
//

import SwiftUI

struct ServerIconView: View {
    let iconURL: String?
    
    var body: some View {
        Group {
            if let iconURL = iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderIcon(letter: "!")
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholderIcon(letter: "?")
                    }
                }
            } else {
                placeholderIcon(letter: "")
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(
            Circle()
                #if os(iOS)
                .stroke(Color(.systemBackground), lineWidth: 2)
                #elseif os(macOS)
                .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 2)
                #endif
        )
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func placeholderIcon(letter: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.3))
            
            if !letter.isEmpty {
                Text(letter)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ServerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
