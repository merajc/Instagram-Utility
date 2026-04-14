import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @State private var viewModel = ViewModel()

    private let card = Color(NSColor.controlBackgroundColor)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftColumn
            rightColumn
        }
        .padding(20)
        .frame(minWidth: 980, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(
            isPresented: $viewModel.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
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
        VStack(alignment: .leading, spacing: 10) {
            headerCard

            if viewModel.isProcessing || viewModel.completedCount > 0 {
                progressRow
                metricStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !viewModel.logMessages.isEmpty {
                logCard
                    .transition(.opacity)
            }

            if !viewModel.results.isEmpty {
                // frame(maxHeight: .infinity) → absorbs ALL remaining vertical space
                // after fixed-height siblings are laid out. This is what keeps the
                // UI squeezed into whatever window height the user has.
                ChartsView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.results.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isProcessing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Header card ──────────────────────────────────────────────────────────

    private var headerCard: some View {
        HStack(spacing: 14) {
            // Folder icon
            Image(systemName: viewModel.selectedDirectory == nil ? "folder" : "folder.fill")
                .font(.title)
                .foregroundStyle(viewModel.selectedDirectory == nil ? Color.secondary : Color.blue)

            // Title — folder name or placeholder
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedDirectory?.lastPathComponent ?? "Select a folder")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let dir = viewModel.selectedDirectory {
                    Text(dir.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            // Overlay text input
            VStack(alignment: .leading, spacing: 3) {
                Text("Overlay Text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Japan Dec 2024", text: $viewModel.settings.overlayText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator, lineWidth: 1))
                    .frame(width: 200)
                    .onChange(of: viewModel.settings.overlayText) { viewModel.saveSettings() }
            }

            // Select folder button
            Button {
                viewModel.showFolderPicker = true
            } label: {
                Label(viewModel.isProcessing ? "Processing…" : "Select Folder",
                      systemImage: viewModel.isProcessing ? "hourglass" : "folder.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(viewModel.isProcessing ? Color.secondary.opacity(0.2) : Color.blue)
                    .foregroundStyle(viewModel.isProcessing ? Color.secondary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)
        }
        .padding(16)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // ── Progress row ─────────────────────────────────────────────────────────

    private var progressRow: some View {
        VStack(spacing: 5) {
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
                .tint(viewModel.isProcessing ? .blue : .green)
                .animation(.easeInOut, value: viewModel.progress)
        }
        .padding(.horizontal, 4)
    }

    // ── Metric strip ─────────────────────────────────────────────────────────

    private var metricStrip: some View {
        HStack(spacing: 10) {
            MetricCard(
                value: "\(viewModel.processedCount(for: .processed))",
                label: "Processed",
                accent: Color(hex: "#22C55E")
            )
            MetricCard(
                value: "\(viewModel.processedCount(for: .skipped))",
                label: "Copied",
                accent: Color(hex: "#EAB308")
            )
            MetricCard(
                value: "\(viewModel.processedCount(for: .error))",
                label: "Errors",
                accent: Color(hex: "#EF4444")
            )
        }
    }

    // ── Terminal log ─────────────────────────────────────────────────────────

    private var logCard: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(
                        Array(viewModel.logMessages.enumerated()),
                        id: \.0
                    ) { _, msg in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(logDotColor(msg))
                                .frame(width: 6, height: 6)
                                .padding(.top, 3.5)

                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(logTextColor(msg))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                    }
                    Color.clear.frame(height: 4).id("logBottom")
                }
                .padding(.vertical, 10)
            }
            .frame(minHeight: 72, maxHeight: 100)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1))
            .onChange(of: viewModel.logMessages.count) {
                withAnimation { proxy.scrollTo("logBottom") }
            }
        }
    }

    private func logDotColor(_ msg: String) -> Color {
        if msg.hasPrefix("Done")   { return Color(hex: "#22C55E") }
        if msg.hasPrefix("Error")  { return Color(hex: "#EF4444") }
        if msg.hasPrefix("Delete") { return Color(hex: "#EAB308") }
        return .blue
    }

    private func logTextColor(_ msg: String) -> Color {
        if msg.hasPrefix("Done")  { return Color(hex: "#22C55E") }
        if msg.hasPrefix("Error") { return Color(hex: "#EF4444") }
        return .primary
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: 12) {
            settingsCard
            performanceCard
            Spacer()
        }
        .frame(width: 234)
    }

    // ── Settings card ─────────────────────────────────────────────────────────

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Text Settings", systemImage: "slider.horizontal.3")
                .font(.headline)

            Divider()

            SliderRow(
                label: "Text Height",
                value: $viewModel.settings.textHeightPercent,
                range: 0.01...0.05,
                format: { String(format: "%.1f%%", $0 * 100) },
                onChange: { viewModel.saveSettings() }
            )

            SliderRow(
                label: "Margin",
                value: $viewModel.settings.marginPercent,
                range: 0.01...0.10,
                format: { String(format: "%.1f%%", $0 * 100) },
                onChange: { viewModel.saveSettings() }
            )
        }
        .padding(16)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // ── Performance card ──────────────────────────────────────────────────────

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Performance", systemImage: "speedometer")
                .font(.headline)

            Divider()

            if viewModel.results.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Run a batch to see metrics")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                PerfRow(icon: "timer",    label: "Average",  value: formatMs(viewModel.avgProcessingTime))
                PerfRow(icon: "bolt",     label: "Fastest",  value: formatMs(viewModel.fastestTime))
                PerfRow(icon: "tortoise", label: "Slowest",  value: formatMs(viewModel.slowestTime))

                Divider()

                PerfRow(icon: "clock",    label: "Total CPU", value: String(format: "%.1fs", viewModel.totalProcessingTime))
                PerfRow(icon: "photo.on.rectangle", label: "Images", value: "\(viewModel.totalCount)")
            }
        }
        .padding(16)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.2), value: viewModel.results.isEmpty)
    }

    private func formatMs(_ ms: Double) -> String {
        ms >= 1000 ? String(format: "%.2fs", ms / 1000) : String(format: "%.0fms", ms)
    }
}

// MARK: - MetricCard

struct MetricCard: View {
    let value: String
    let label: String
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            accent
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - PerfRow

struct PerfRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}

// MARK: - SliderRow

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
