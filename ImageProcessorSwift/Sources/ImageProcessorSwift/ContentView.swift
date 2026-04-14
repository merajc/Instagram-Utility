import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @State private var viewModel = ViewModel()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftColumn
            rightSidebar
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
        // Folder picker — uses NSOpenPanel semantics on macOS
        .fileImporter(
            isPresented: $viewModel.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // Security-scoped resource: required for sandboxed apps,
                // harmless (returns false) when running via `swift run`.
                let accessing = url.startAccessingSecurityScopedResource()
                viewModel.selectedDirectory = url
                Task {
                    await viewModel.processDirectory(url)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
            case .failure(let err):
                viewModel.logMessages.append("Folder picker error: \(err.localizedDescription)")
            }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Top bar ────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "photo.stack.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text(viewModel.selectedDirectory?.lastPathComponent ?? "Select a folder to start…")
                    .font(.headline)
                    .foregroundStyle(
                        viewModel.selectedDirectory == nil ? .secondary : .primary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Overlay-text input (mirrors Python's QLineEdit)
                TextField("Overlay text", text: $viewModel.settings.overlayText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: viewModel.settings.overlayText) {
                        viewModel.saveSettings()
                    }

                Button(viewModel.isProcessing ? "Processing…" : "Select Folder") {
                    viewModel.showFolderPicker = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

            // ── Progress bar ───────────────────────────────────────────────
            if viewModel.isProcessing || viewModel.completedCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(viewModel.isProcessing ? "Processing…" : "Complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.completedCount) / \(viewModel.totalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .animation(.easeInOut, value: viewModel.progress)
                }
                .padding(.horizontal, 4)
            }

            // ── Log ────────────────────────────────────────────────────────
            if !viewModel.logMessages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(
                                Array(viewModel.logMessages.enumerated()),
                                id: \.0
                            ) { _, msg in
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(
                                        msg.hasPrefix("Error") ? .red
                                        : msg.hasPrefix("Done")  ? .green
                                        : .secondary
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("logBottom")
                        }
                        .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
                    .onChange(of: viewModel.logMessages.count) {
                        withAnimation { proxy.scrollTo("logBottom") }
                    }
                }
            }

            // ── Charts ─────────────────────────────────────────────────────
            if !viewModel.results.isEmpty {
                ChartsView(viewModel: viewModel)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.results.isEmpty)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Right sidebar

    private var rightSidebar: some View {
        VStack(spacing: 14) {
            statsCard
            settingsCard
            Spacer()
        }
        .frame(width: 230)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Statistics", systemImage: "chart.bar.fill")
                .font(.headline)

            Divider()

            StatRow(label: "Processed",   value: viewModel.processedCount(for: .processed), color: .green)
            StatRow(label: "Copied (4:3)", value: viewModel.processedCount(for: .skipped),  color: .orange)
            StatRow(label: "Errors",       value: viewModel.processedCount(for: .error),    color: .red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Text Settings", systemImage: "slider.horizontal.3")
                .font(.headline)

            Divider()

            // Text-height slider (1 % – 5 %)
            SliderRow(
                label: "Text Height",
                value: $viewModel.settings.textHeightPercent,
                range: 0.01 ... 0.05,
                format: { String(format: "%.1f%%", $0 * 100) },
                onChange: { viewModel.saveSettings() }
            )

            // Margin slider (1 % – 10 %)
            SliderRow(
                label: "Margin",
                value: $viewModel.settings.marginPercent,
                range: 0.01 ... 0.10,
                format: { String(format: "%.1f%%", $0 * 100) },
                onChange: { viewModel.saveSettings() }
            )
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Reusable sub-views

struct StatRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .onChange(of: value) { onChange() }
        }
    }
}
