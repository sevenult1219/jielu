import AppKit
import SwiftUI

struct TaskSourceOption: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
}

struct SourceChoiceBar: View {
    let options: [TaskSourceOption]
    let selectedID: String
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                let selected = option.id == selectedID
                Button {
                    onSelect(option.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: option.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(option.title)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(selected ? accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? accent.opacity(0.11) : Color.primary.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                selected ? accent.opacity(0.45) : Color.primary.opacity(0.06),
                                lineWidth: selected ? 1.2 : 0.8
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TaskStepHeader: View {
    let number: Int
    let title: String
    var detail: String? = nil
    var accent: Color = .accentColor

    var body: some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct TaskTargetCard: View {
    let systemIcon: String
    let image: NSImage?
    let title: String
    let detail: String
    var badge: String? = nil
    var actionTitle: String? = nil
    var accent: Color = .accentColor
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.10))
                    .frame(width: 44, height: 44)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: systemIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.045)))
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(accent)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.8)
                )
        )
    }
}

struct TaskOptionsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.8)
                )
        )
    }
}

struct TaskActionBar: View {
    let summary: String
    let detail: String
    let actionTitle: String
    let actionIcon: String
    let enabled: Bool
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.55)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 12.5, weight: .bold))
                        Text(actionTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(TaskPrimaryButtonStyle(colors: colors))
                .disabled(!enabled)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.56))
        }
    }
}

struct TaskPrimaryButtonStyle: ButtonStyle {
    let colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        TaskPrimaryButtonBody(configuration: configuration, colors: colors)
    }

    private struct TaskPrimaryButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyle.Configuration
        let colors: [Color]

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isEnabled ? colors : [Color.gray.opacity(0.55), Color.gray.opacity(0.42)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(
                    color: isEnabled ? (colors.first ?? .clear).opacity(0.20) : .clear,
                    radius: 7,
                    y: 3
                )
                .brightness(configuration.isPressed ? -0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.994 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
