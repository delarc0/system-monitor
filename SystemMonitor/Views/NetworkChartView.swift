import SwiftUI
import Charts

/// Download above the zero line, upload mirrored below it.
///
/// The previous version stacked two areas from the same baseline, so upload
/// painted over download and neither could be read; it also had no axis label,
/// which left no way to tell a 5 KB/s hump from a 500 MB/s one.
struct NetworkChartView: View {
    let sample: NetworkSample
    var scale: NetworkScale = .shared

    private struct Point: Identifiable {
        let id: Int
        let download: Double       // normalised to 0...1
        let upload: Double         // normalised to 0...1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Chart {
                RuleMark(y: .value("Rate", 0))
                    .foregroundStyle(Color.primary.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))

                // Every mark carries an explicit `series:`. Without it Charts
                // groups marks by x value, merges the two areas into one series
                // and applies a single style to both.
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Time", point.id),
                        yStart: .value("Rate", 0),
                        yEnd: .value("Rate", point.download),
                        series: .value("Direction", "Download")
                    )
                    .foregroundStyle(gradient(.blue))
                    .interpolationMethod(.monotone)
                }
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.id),
                        y: .value("Rate", point.download),
                        series: .value("Direction", "Download")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }

                ForEach(points) { point in
                    AreaMark(
                        x: .value("Time", point.id),
                        yStart: .value("Rate", -point.upload),
                        yEnd: .value("Rate", 0),
                        series: .value("Direction", "Upload")
                    )
                    .foregroundStyle(gradient(.orange, flipped: true))
                    .interpolationMethod(.monotone)
                }
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.id),
                        y: .value("Rate", -point.upload),
                        series: .value("Direction", "Upload")
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
            .chartYScale(domain: -1...1)
            // Scaled against capacity, not the sample count, so a partial
            // window fills in from the right rather than stretching.
            .chartXScale(domain: 0...max(sample.capacity - 1, 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { $0.clipped() }
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

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text("Network")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer()
            // Without this the chart is shapes with no magnitude.
            Text(scaleLabel)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var scaleLabel: String {
        switch scale {
        case .shared:
            return "±\(formatByteRate(downloadScale)) · \(windowLabel)"
        case .perDirection:
            return "↓\(formatByteRate(downloadScale)) ↑\(formatByteRate(uploadScale)) · \(windowLabel)"
        }
    }

    // MARK: - Scaling

    private var downloadScale: Double {
        switch scale {
        case .shared: return Self.niceCeiling(max(peak(sample.downloadHistory), peak(sample.uploadHistory)))
        case .perDirection: return Self.niceCeiling(peak(sample.downloadHistory))
        }
    }

    private var uploadScale: Double {
        switch scale {
        case .shared: return downloadScale
        case .perDirection: return Self.niceCeiling(peak(sample.uploadHistory))
        }
    }

    private func peak(_ series: [Double]) -> Double { series.max() ?? 0 }

    /// Round the window's peak up to a 1/2/5 × 10ⁿ figure inside its B/KB/MB/GB
    /// unit, so the labelled scale is a number worth reading, with a floor so
    /// an idle link doesn't magnify its own noise into a mountain range.
    ///
    /// Must never return less than `peak`, or the chart silently clips the very
    /// spike it exists to show.
    private static func niceCeiling(_ peak: Double) -> Double {
        let floorValue = 64.0 * 1024
        guard peak > floorValue else { return floorValue }

        // `unit` is the largest power of 1024 not exceeding peak, so `mantissa`
        // lands in [1, 1024) and needs its own decimal rounding on top.
        let unit = pow(1024, floor(log2(peak) / 10))
        let mantissa = peak / unit
        let magnitude = pow(10, floor(log10(mantissa)))
        let normalized = mantissa / magnitude
        let step: Double
        switch normalized {
        case ..<1: step = 1
        case ..<2: step = 2
        case ..<5: step = 5
        default: step = 10
        }
        return step * magnitude * unit
    }

    /// Values are normalised to 0…1 against their own axis scale so the two
    /// halves can carry different magnitudes in `.perDirection`.
    private var points: [Point] {
        // Align on the most recent samples: if the two histories ever differ in
        // length, the newest readings still have to line up on the x axis.
        let count = min(sample.downloadHistory.count, sample.uploadHistory.count)
        let downloadOffset = sample.downloadHistory.count - count
        let uploadOffset = sample.uploadHistory.count - count
        let downMax = max(downloadScale, 1)
        let upMax = max(uploadScale, 1)
        let leading = max(sample.capacity - count, 0)   // empty slots stay on the left

        return (0..<count).map {
            Point(
                id: leading + $0,
                download: min(sample.downloadHistory[$0 + downloadOffset] / downMax, 1),
                upload: min(sample.uploadHistory[$0 + uploadOffset] / upMax, 1)
            )
        }
    }

    private var windowLabel: String {
        let seconds = sample.windowSeconds
        return seconds >= 120 ? "\(seconds / 60) min" : "\(seconds)s"
    }

    private func gradient(_ color: Color, flipped: Bool = false) -> LinearGradient {
        let stops = [color.opacity(0.30), color.opacity(0.03)]
        return LinearGradient(
            colors: flipped ? stops.reversed() : stops,
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
