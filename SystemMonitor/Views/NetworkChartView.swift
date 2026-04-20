import SwiftUI
import Charts

struct NetworkChartView: View {
    let sample: NetworkSample

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
            }

            Chart {
                ForEach(Array(sample.downloadHistory.enumerated()), id: \.offset) { idx, val in
                    AreaMark(
                        x: .value("t", idx),
                        yStart: .value("min", 0),
                        yEnd: .value("bps", val)
                    )
                    .foregroundStyle(downloadGradient)
                    .interpolationMethod(.catmullRom)
                }
                ForEach(Array(sample.downloadHistory.enumerated()), id: \.offset) { idx, val in
                    LineMark(x: .value("t", idx), y: .value("bps", val))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
                ForEach(Array(sample.uploadHistory.enumerated()), id: \.offset) { idx, val in
                    AreaMark(
                        x: .value("t", idx),
                        yStart: .value("min", 0),
                        yEnd: .value("bps", val)
                    )
                    .foregroundStyle(uploadGradient)
                    .interpolationMethod(.catmullRom)
                }
                ForEach(Array(sample.uploadHistory.enumerated()), id: \.offset) { idx, val in
                    LineMark(x: .value("t", idx), y: .value("bps", val))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
            .animation(.easeInOut(duration: 0.35), value: sample.downloadHistory)
            .animation(.easeInOut(duration: 0.35), value: sample.uploadHistory)

            HStack(spacing: 14) {
                Label(sample.downloadString, systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label(sample.uploadString, systemImage: "arrow.up")
                    .foregroundStyle(.orange)
                Spacer()
            }
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .labelStyle(.titleAndIcon)
        }
    }

    private var yMax: Double {
        let peak = (sample.downloadHistory + sample.uploadHistory).max() ?? 0
        return max(peak * 1.1, 1024)   // keep a floor so idle network isn't a flat nothing
    }

    private var downloadGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.28), Color.blue.opacity(0.04)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var uploadGradient: LinearGradient {
        LinearGradient(
            colors: [Color.orange.opacity(0.25), Color.orange.opacity(0.03)],
            startPoint: .top, endPoint: .bottom
        )
    }
}
