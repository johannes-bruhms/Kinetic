import SwiftUI

struct IMUWaveformView: View {
    let sample: MotionSample?

    @State private var accelHistory: [[Double]] = [[], [], []] // x, y, z
    private let maxPoints = 200

    var body: some View {
        Canvas { context, size in
            let colors: [Color] = [.red, .green, .blue]
            let midY = size.height / 2
            let scaleY = size.height / 4 // ±2g fills half

            for axis in 0..<3 {
                let points = accelHistory[axis]
                guard points.count > 1 else { continue }

                var path = Path()
                for (i, value) in points.enumerated() {
                    let x = size.width * Double(i) / Double(maxPoints)
                    let y = midY - value * scaleY
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(path, with: .color(colors[axis]), lineWidth: 1.5)
            }
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: sample?.timestamp) { _, _ in
            guard let sample else { return }
            let accel = sample.userAcceleration
            accelHistory[0].append(accel.x)
            accelHistory[1].append(accel.y)
            accelHistory[2].append(accel.z)

            for i in 0..<3 {
                if accelHistory[i].count > maxPoints {
                    accelHistory[i].removeFirst()
                }
            }
        }
    }
}
