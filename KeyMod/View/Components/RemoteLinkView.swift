//
//  RemoteLinkView.swift
//  KeyMod
//
//  Created on 2026/3/1.
//

import SwiftUI
import UIKit

/// A reusable component that displays a remote support link with a copy button.
struct RemoteLinkView: View {
    let url: URL
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                Text("Remote Support Link")
                    .fontWeight(.semibold)
                Spacer()
            }

            // URL Display with Copy Button
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share this link with your remote assistant:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(url.absoluteString)
                        .font(.footnote)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    // Copy Button
                    Button(action: copyURL) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.body)
                            .foregroundColor(isCopied ? .green : .accentColor)
                            .frame(width: 40, height: 40)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .animation(.easeInOut(duration: 0.2), value: isCopied)

                    // Share Button
                    Button(action: shareLink) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .foregroundColor(.accentColor)
                            .frame(width: 40, height: 40)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Feedback Message
            if isCopied {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Link copied to clipboard!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
        .border(Color.green.opacity(0.3), width: 2)
        .cornerRadius(8)
    }

    private func copyURL() {
        UIPasteboard.general.url = url
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { self.isCopied = false }
        }
    }

    private func shareLink() {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        activityVC.popoverPresentationController?.sourceView = topVC.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: topVC.view.bounds.midX,
            y: topVC.view.bounds.midY,
            width: 0, height: 0
        )
        topVC.present(activityVC, animated: true)
    }
}

#Preview {
    RemoteLinkView(url: URL(string: "https://example.com/tunnel/abc123")!)
        .padding()
}
