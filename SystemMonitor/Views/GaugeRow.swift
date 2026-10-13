import SwiftUI

/// One row: [icon] label [sparkline] [percentage] + optional subline.
///
/// The sparkline replaces the old flat capsule rather than sitting next to it.
/// Its y-axis is pinned to 0…100, so the trace's height still reads as the
/// current level exactly like a bar did, but it also shows where the metric
/// has just been, which a bar throws away every tick.
struct GaugeRow: View {
    let icon: String
    let label: String
    let value: Double              // 0..100
    let valueText: String
    var history: [Double] = []
    var historyCapacity: Int = 60
    var subline: String? = nil
    var isAlerting: Bool = false
    /// Load for the colour when it is not `value`: a battery is bad when low.
    var colorValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: isAlerting ? "exclamationmark.triangle.fill" : icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(isAlerting ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .symbolEffect(.pulse, isActive: isAlerting)

                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(width: 64, alignment: .leading)

                Sparkline(
                    values: history,
                    capacity: historyCapacity,
                    current: value,
                    color: loadColor(colorValue ?? value)
                )
                .frame(height: 18)

                Text(valueText)
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(isAlerting ? Color.red : Color.primary)
            }

            if let sub = subline, !sub.isEmpty {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 90)
            }
        }
    }
}

/// A fixed-scale (0…100) trace. Hand-drawn rather than a `Chart`: there are up
/// to four of these redrawing every tick, and a Path costs a fraction of a
/// chart's layout pass.
struct Sparkline: View {
    let values: [Double]
    /// Slots the window holds once warmed up. x is scaled against this, not
    /// against `values.count`, so a partial series fills in from the right
    /// instead of stretching a handful of samples across the full width.
    let capacity: Int
    let current: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = plotPoints(in: size)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.05))

                if points.count > 1 {
                    area(points, in: size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.45), color.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    line(points)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                } else {
                    // Before any history accumulates, fall back to a plain bar
                    // so the row still reads as a level.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(2, size.width * min(current, 100) / 100))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func plotPoints(in size: CGSize) -> [CGPoint] {
        let slots = max(capacity, values.count)
        guard values.count > 1, slots > 1 else { return [] }

        let step = size.width / CGFloat(slots - 1)
        let leading = slots - values.count      // empty slots, kept on the left
        return values.enumerated().map { index, value in
            let clamped = min(max(value, 0), 100)
            return CGPoint(
                x: CGFloat(leading + index) * step,
                y: size.height - (size.height * clamped / 100)
            )
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    /// Built with explicit `addLine` calls: `addLines` begins with its own
    /// `move(to:)`, which orphans the bottom-left corner and leaves the shape
    /// closing diagonally back to the first sample, so a flat series renders
    /// as a wedge rising left to right.
    private func area(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: points[0].x, y: size.height))
        for point in points {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
        path.closeSubpath()
        return path
    }
}
