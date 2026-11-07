import SwiftUI

/// One row: [icon] label [sparkline] [percentage] + optional subline.
///
/// Its y-axis is pinned to 0…100, so the trace's height still reads as the current
/// level exactly like a bar did, but it also shows where the metric has just been.
struct GaugeRow: View {
    let icon: String
    let label: String
    let value: Double              // 0..100
    var history: [Double] = []
    var subline: String? = nil
    var isAlerting: Bool = false
    /// Load for the colour when it is not `value`: memory colours by pressure.
    var colorValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                GaugeLabel(icon: isAlerting ? "exclamationmark.triangle.fill" : icon, label: label, isAlerting: isAlerting)

                Sparkline(values: history, current: value, color: loadColor(colorValue ?? value))
                    .frame(height: 18)

                Text(String(format: "%.0f%%", value))
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(isAlerting ? Color.red : Color.primary)
            }

            if let subline, !subline.isEmpty {
                Text(subline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 90)
            }
        }
    }
}

struct GaugeLabel: View {
    let icon: String
    let label: String
    var isAlerting: Bool = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16)
            .foregroundStyle(isAlerting ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))

        Text(label)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(width: 64, alignment: .leading)
    }
}

/// A fixed-scale (0…100) trace, or a plain level bar when there is no history.
struct Sparkline: View {
    let values: [Double]
    let current: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = tracePoints(values, width: size.width) {
                size.height - size.height * min(max($0, 0), 100) / 100
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.05))

                if points.count > 1 {
                    traceArea(points, baseline: size.height).fill(color.opacity(0.18))
                    traceLine(points).stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(2, size.width * min(current, 100) / 100))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

/// x is scaled against the history's capacity, not `values.count`, so a partial
/// series fills in from the right instead of stretching a few samples across the width.
func tracePoints(_ values: [Double], width: CGFloat, y: (Double) -> CGFloat) -> [CGPoint] {
    let slots = max(MetricHistory.capacity, values.count)
    guard values.count > 1 else { return [] }

    let step = width / CGFloat(slots - 1)
    let leading = slots - values.count      // empty slots, kept on the left
    return values.enumerated().map { index, value in
        CGPoint(x: CGFloat(leading + index) * step, y: y(value))
    }
}

func traceLine(_ points: [CGPoint]) -> Path {
    var path = Path()
    path.addLines(points)
    return path
}

/// Built with explicit `addLine` calls: `addLines` begins with its own `move(to:)`,
/// which orphans the baseline corner and leaves the shape closing diagonally back to
/// the first sample, so a flat series renders as a wedge rising left to right.
func traceArea(_ points: [CGPoint], baseline: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: points[0].x, y: baseline))
    for point in points {
        path.addLine(to: point)
    }
    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baseline))
    path.closeSubpath()
    return path
}
