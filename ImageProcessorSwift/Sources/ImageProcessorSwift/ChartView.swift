import SwiftUI
import Charts

// MARK: - Compact Pie / Donut Chart

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
            Slice(label: "Processed", count: processed, color: Color(hex: "#22C55E")),
            Slice(label: "Copied",    count: skipped,   color: Color(hex: "#EAB308")),
            Slice(label: "Errors",    count: errors,    color: Color(hex: "#EF4444"))
        ].filter { $0.count > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.subheadline.bold())

            if slices.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Count", slice.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(slice.color)
                    .annotation(position: .overlay) {
                        Text("\(slice.count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .chartLegend(position: .bottom, spacing: 6)
                .chartForegroundStyleScale(
                    domain: slices.map(\.label),
                    range:  slices.map(\.color)
                )
                .frame(height: 160)
            }
        }
        .padding(12)
    }
}

// MARK: - Horizontal Bar Chart

struct BarChartView: View {

    let results: [ProcessingResult]

    @State private var hoveredIndex: Int? = nil

    private struct BarItem: Identifiable {
        let id: Int
        let filename: String
        let time: Double
        let fileSize: Double
        let thumbnail: NSImage?
    }

    private var items: [BarItem] {
        results.enumerated().map { i, r in
            BarItem(id: i, filename: r.filename, time: r.processingTime,
                    fileSize: r.fileSize, thumbnail: r.thumbnail)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processing Time per Image")
                .font(.subheadline.bold())

            // String y-axis → Swift Charts treats it as categorical → horizontal bars.
            // No inner ScrollView; the left-column ScrollView handles scrolling.
            Chart(items) { item in
                BarMark(
                    x: .value("Time (ms)", item.time),
                    y: .value("Image",     "\(item.id + 1)")   // String = categorical → horizontal
                )
                .foregroundStyle(
                    hoveredIndex == item.id
                        ? Color(hex: "#1D4ED8")
                        : Color(hex: "#3B82F6")
                )
                .opacity(hoveredIndex == nil || hoveredIndex == item.id ? 1.0 : 0.7)
                .cornerRadius(3)
            }
            .chartYAxis(.hidden)
            .chartXAxisLabel("ms", alignment: .trailing)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    AxisValueLabel().font(.caption2)
                }
            }
            // Hover: map y-position → bar index (bars stacked vertically in horizontal chart)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotRect = geo[plotFrame]
                                let relY = location.y - plotRect.origin.y
                                let ratio = max(0, min(1, relY / plotRect.height))
                                let idx = Int(ratio * CGFloat(items.count))
                                hoveredIndex = items.indices.contains(idx) ? idx : items.indices.last
                            case .ended:
                                hoveredIndex = nil
                            }
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let idx = hoveredIndex, results.indices.contains(idx) {
                    TooltipView(result: results[idx])
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.15), radius: 6)
                        .padding(6)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            // maxHeight: .infinity → chart fills whatever vertical space ChartsView gives it.
            // Swift Charts distributes 17 bars proportionally across the available height.
            .frame(maxHeight: .infinity)
            .padding(.trailing, 4)
        }
        .padding(12)
    }
}

// MARK: - Hover Tooltip

struct TooltipView: View {
    let result: ProcessingResult

    var statusColor: Color {
        switch result.status {
        case .processed: return Color(hex: "#22C55E")
        case .skipped:   return Color(hex: "#EAB308")
        case .error:     return Color(hex: "#EF4444")
        }
    }

    var statusLabel: String {
        switch result.status {
        case .processed: return "Processed"
        case .skipped:   return "Copied"
        case .error:     return "Error"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let thumb = result.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(result.filename)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .leading)

                Label(String(format: "%.2f MB", result.fileSize), systemImage: "doc")
                    .font(.caption2).foregroundStyle(.secondary)
                Label(String(format: "%.1f ms", result.processingTime), systemImage: "timer")
                    .font(.caption2).foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusLabel).font(.caption2).foregroundStyle(statusColor)
                }
            }
        }
        .padding(10)
    }
}

// MARK: - Combined Charts Container

struct ChartsView: View {
    let viewModel: ViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Compact donut — fixed width
            PieChartView(
                processed: viewModel.processedCount(for: .processed),
                skipped:   viewModel.processedCount(for: .skipped),
                errors:    viewModel.processedCount(for: .error)
            )
            .frame(width: 200)

            Divider()

            // Horizontal bar chart fills remaining space
            BarChartView(results: viewModel.results)
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 200, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
