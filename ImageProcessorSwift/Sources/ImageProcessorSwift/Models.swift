import Foundation
import SwiftUI
import AppKit

// MARK: - Status

enum ProcessingStatus {
    case processed, skipped, error
}

// MARK: - Result
// @unchecked Sendable: NSImage is not Sendable, but we only access
// thumbnail images on the MainActor after processing completes.
struct ProcessingResult: Identifiable, @unchecked Sendable {
    let id = UUID()
    let status: ProcessingStatus
    let filename: String
    let processingTime: Double  // milliseconds
    let fileSize: Double        // megabytes
    let message: String
    let thumbnail: NSImage?
}

// MARK: - Settings (mirrors Python settings.json layout)

struct AppSettings: Codable {
    var overlayText: String = "Japan Dec 2024"
    var textHeightPercent: Double = 0.02
    var marginPercent: Double = 0.05

    enum CodingKeys: String, CodingKey {
        case overlayText     = "overlay_text"
        case textHeightPercent = "text_height"
        case marginPercent   = "margin"
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255.0,
            green: Double((int >> 8)  & 0xFF) / 255.0,
            blue:  Double(int         & 0xFF) / 255.0
        )
    }
}
