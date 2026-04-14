import SwiftUI
import Observation

// MARK: - ViewModel
// @MainActor: all UI state mutations happen on the main thread.
// @Observable: SwiftUI automatically re-renders views that read any changed property.

@MainActor
@Observable
final class ViewModel {

    // UI state
    var results: [ProcessingResult] = []
    var logMessages: [String] = []
    var isProcessing = false
    var completedCount = 0
    var totalCount = 0
    var showFolderPicker = false
    var selectedDirectory: URL? = nil

    // Settings (persisted to ~/Library/Application Support/ImageProcessorSwift/settings.json)
    var settings = AppSettings()

    private let service = ImageProcessingService()

    private var settingsURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("ImageProcessorSwift", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    init() { loadSettings() }

    // MARK: Settings persistence

    func loadSettings() {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let s    = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return }
        settings = s
    }

    func saveSettings() {
        let dir = settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: settingsURL)
        }
    }

    // MARK: Processing

    func processDirectory(_ url: URL) async {
        guard !isProcessing else { return }

        isProcessing    = true
        results         = []
        logMessages     = []
        completedCount  = 0

        // Count JPEGs so we can show a determinate progress bar
        let jpegFiles = (
            try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil
            )
        )?.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) } ?? []

        totalCount = jpegFiles.count

        guard totalCount > 0 else {
            logMessages.append("No JPEG images found in the selected folder.")
            isProcessing = false
            return
        }

        // Log previously-deleted output files (mirrors Python behaviour)
        let outputDir = url.appendingPathComponent("cropped")
        if let existing = try? FileManager.default.contentsOfDirectory(
            at: outputDir, includingPropertiesForKeys: nil
        ) {
            for f in existing {
                logMessages.append("Deleted \(f.lastPathComponent) from cropped/")
            }
        }

        await service.process(
            directory: url,
            settings: settings
        ) { [weak self] result in
            guard let self else { return }
            self.results.append(result)
            self.logMessages.append(result.message)
            self.completedCount += 1
        }

        let p = results.filter { $0.status == .processed }.count
        let s = results.filter { $0.status == .skipped   }.count
        let e = results.filter { $0.status == .error     }.count
        logMessages.append("Done — \(p) processed, \(s) copied, \(e) errors.")
        isProcessing = false
    }

    // MARK: Convenience

    var progress: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    func processedCount(for status: ProcessingStatus) -> Int {
        results.filter { $0.status == status }.count
    }
}
