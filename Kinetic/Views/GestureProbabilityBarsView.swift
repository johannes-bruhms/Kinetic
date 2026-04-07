import SwiftUI

struct GestureProbabilityBarsView: View {
    let predictions: [String: Float]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(predictions.sorted(by: { $0.value > $1.value }), id: \.key) { name, probability in
                HStack(spacing: 8) {
                    Text(name)
                        .font(.caption.monospaced())
                        .frame(width: 80, alignment: .trailing)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(barColor(for: probability))
                                .frame(width: geo.size.width * CGFloat(probability))
                        }
                    }
                    .frame(height: 20)

                    Text("\(Int(probability * 100))%")
                        .font(.caption.monospaced())
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    private func barColor(for probability: Float) -> Color {
        if probability > 0.8 { return .green }
        if probability > 0.5 { return .yellow }
        return .gray
    }
}
