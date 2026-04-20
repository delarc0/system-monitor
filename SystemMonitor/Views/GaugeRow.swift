import SwiftUI

/// One row: [icon] label [animated bar] [percentage] + optional subline.
struct GaugeRow: View {
    let icon: String
    let label: String
    let value: Double              // 0..100
    let valueText: String
    var subline: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)

                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(width: 64, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(loadColor(value))
                            .frame(width: max(2, geo.size.width * min(value, 100) / 100))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
                    }
                }
                .frame(height: 6)

                Text(valueText)
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(.primary)
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
