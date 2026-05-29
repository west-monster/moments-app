import SwiftUI

enum AppTheme {
    static let background = Color(.systemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let accent = Color(red: 0.33, green: 0.53, blue: 1.0)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let divider = Color(.separator)

    static func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .default))
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(accent)
    }
}

struct VergeGridBackground: View {
    @Environment(\.colorScheme) var colorScheme

    private var lineColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
    }

    var body: some View {
        GeometryReader { geo in
            let columns = 5
            let spacing = geo.size.width / CGFloat(columns)
            Canvas { context, size in
                for i in 1..<columns {
                    let x = spacing * CGFloat(i)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.33)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
