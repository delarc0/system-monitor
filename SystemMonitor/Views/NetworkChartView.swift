import SwiftUI

/// Download above the zero line, upload mirrored below it, on one shared scale so
/// the two halves stay comparable. Drawn like the sparklines, with no chart framework.
struct NetworkChartView: View {
    let sample: NetworkSample

    private var scale: Double {
        niceByteCeiling(max(sample.downloadHistory.max() ?? 0, sample.uploadHistory.max() ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text("Network")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                // Without this the chart is shapes with no magnitude.
                Text("±\(formatByteRate(scale)) · \(Int(Double(MetricHistory.capacity) * MetricsService.interval) / 60) min")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let middle = geo.size.height / 2
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.05))
                    trace(sample.downloadHistory, .blue, width: geo.size.width, middle: middle, direction: -1)
                    trace(sample.uploadHistory, .orange, width: geo.size.width, middle: middle, direction: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 56)

            HStack(spacing: 14) {
                Label(formatByteRate(sample.downloadBps), systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label(formatByteRate(sample.uploadBps), systemImage: "arrow.up")
                    .foregroundStyle(.orange)
                Spacer()
            }
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private func trace(_ values: [Double], _ color: Color, width: CGFloat, middle: CGFloat, direction: CGFloat) -> some View {
        let scale = max(scale, 1)
        let points = tracePoints(values, width: width) { middle + direction * middle * min($0 / scale, 1) }
        if points.count > 1 {
            traceArea(points, baseline: middle).fill(color.opacity(0.18))
            traceLine(points).stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }
}
