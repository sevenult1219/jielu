import AppKit
import SwiftUI

struct AppBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.055),
                        Color.purple.opacity(0.025),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .init(x: 0.62, y: 0.50)
                )
                Circle()
                    .fill(Color.cyan.opacity(0.05))
                    .frame(width: proxy.size.width * 0.42)
                    .blur(radius: 120)
                    .offset(x: proxy.size.width * 0.36, y: proxy.size.height * 0.42)
            }
            .ignoresSafeArea()
        }
    }
}

struct LogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.55, blue: 1.0),
                            Color(red: 0.45, green: 0.30, blue: 0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 2.5) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.96))
                    .frame(width: 16, height: 2.8)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.75))
                    .frame(width: 16, height: 2.8)
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: Color.accentColor.opacity(0.22), radius: 7, y: 3)
    }
}

struct WorkspaceHeader: View {
    let title: String
    let subtitle: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.055)))
                }
                .buttonStyle(.plain)
                .help("返回首页")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }
}

struct AccessPermissionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("自动滚动需要“辅助功能”权限")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("授权后，截录才能向窗口发送滚动事件。")
                    .font(.system(size: 10.2))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("去授权") {
                model.requestAccessibilityPermission()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.16), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 26)
        .padding(.bottom, 12)
    }
}
