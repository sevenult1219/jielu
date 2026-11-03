import SwiftUI

struct GradientButtonStyle: ButtonStyle {
    var verticalPadding: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        GradientButtonBody(configuration: configuration, verticalPadding: verticalPadding)
    }

    private struct GradientButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled

        let configuration: ButtonStyle.Configuration
        let verticalPadding: CGFloat

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isEnabled
                                    ? [Color(red: 0.12, green: 0.50, blue: 1.0),
                                       Color(red: 0.42, green: 0.30, blue: 0.97)]
                                    : [Color.gray.opacity(0.55), Color.gray.opacity(0.45)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(
                    color: isEnabled ? Color.accentColor.opacity(0.24) : .clear,
                    radius: 8,
                    y: 3
                )
                .brightness(configuration.isPressed ? -0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.992 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
