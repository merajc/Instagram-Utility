import SwiftUI
import Charts

// MARK: - Summary Pie Chart

struct PieChartView: View {
    let processed: Int
    let skipped: Int
    let errors: Int

    private struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private var slices: [Slice] {
        [
            Slice(label: "Processed", count: processed, color: Color(hex: "#4CAF50")),
            Slice(label: "Copied",    count: skipped,   color: Color(hex: "#FFC107")),
            Slice(label: "Errors",    count: errors,    color: Color(hex: "#F44336"))
        ].filter { $0.count > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
                .foregroundStyle(.primary)

            if slices.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Count", slice.count),
                        innerRadius: .ratio(0.4),
                        angularInset: 2
                    )
                    .foregroundStyle(slice.color)
                    .annotation(position: .overlay) {
                        Text("\(slice.count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .chartForegroundStyleScale(
                    domain: slices.map(\.label),
                    range:  slices.map(\.color)
                )
            }
        }
        .padding()
    }
}

// MARK: - Processing-time Bar Chart with Hover Tooltip

struct BarChartView: View {
    let results: [ProcessingResult]

    @State private var hoveredIndex: Int? = nil

    private struct BarItem: Identifiable {
        let id: Int        // index
        let filename: String
        let time: Double
        let size: Double
        let thumbnail: NSImage?
    }

    private var items: [BarItem] {
        results.enumerated().map { i, r in
            BarItem(id: i, filename: r.filename, time: r.processingTime,
                    size: r.fileSize, thumbnail: r.thumbnail)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processing Time per Image")
                .font(.headline)

            Chart(items) { item in
                BarMark(
                    x: .value("Index", item.id),
                    y: .value("ms",    item.time)
                )
                .foregroundStyle(
                    hoveredIndex == item.id
                        ? Color(hex: "#1565C0")
                        : Color(hex: "#2196F3")
                )
                .opacity(hoveredIndex == nil || hoveredIndex == item.id ? 1.0 : 0.6)
            }
            .chartXAxis(.hidden)
            .chartYAxisLabel("Time (ms)")
            // Overlay to detect hover position and map it to an array index
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotRect = geo[plotFrame]
                                let relX = location.x - plotRect.origin.x
                                let ratio = max(0, min(1, relX / plotRect.width))
                                let idx = Int(ratio * CGFloat(items.count))
                                hoveredIndex = items.indices.contains(idx) ? idx : items.indices.last
                            case .ended:
                                hoveredIndex = nil
                            }
                        }
                }
            }
            // Fixed-position tooltip at top-right avoids needing exact bar pixel coordinates
            .overlay(alignment: .topTrailing) {
                if let idx = hoveredIndex, results.indices.contains(idx) {
                    TooltipView(result: results[idx])
                        .padding(4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.15), radius: 6)
                        .padding(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.12), value: hoveredIndex)
        }
        .padding()
    }
}

// MARK: - Hover Tooltip

struct TooltipView: View {
    let result: ProcessingResult

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            if let thumb = result.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.3), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(result.filename)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(String(format: "%.2f MB", result.fileSize), systemImage: "doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(String(format: "%.1f ms", result.processingTime), systemImage: "timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(result.status == .processed ? "Processed" : result.status == .skipped ? "Copied" : "Error",
                      systemImage: result.status == .error ? "xmark.circle" : "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(result.status == .error ? .red : .green)
            }
        }
        .padding(10)
    }
}

// MARK: - Combined Charts Container

struct ChartsView: View {
    let viewModel: ViewModel

    var body: some View {
        HStack(spacing: 0) {
            PieChartView(
                processed: viewModel.processedCount(for: .processed),
                skipped:   viewModel.processedCount(for: .skipped),
                errors:    viewModel.processedCount(for: .error)
            )
            .frame(maxWidth: .infinity)

            Divider()

            BarChartView(results: viewModel.results)
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 260)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
