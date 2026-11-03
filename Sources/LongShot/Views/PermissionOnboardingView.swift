import SwiftUI

struct PermissionOnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack {
            Spacer(minLength: 20)
            HStack(spacing: 40) {
                illustration
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.orange)
                        Text("需要一项系统权限")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.10)))

                    Text("先开启屏幕录制")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("截录使用系统原生的 ScreenCaptureKit 读取窗口画面。不限制截图长度，按窗口原始分辨率拼接并保存无损 PNG，所有处理只在本机完成。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        StepRow(number: 1, text: "点击下方按钮，允许“截录”录制屏幕")
                        StepRow(number: 2, text: "在“隐私与安全性 → 屏幕录制”中打开开关")
                        StepRow(number: 3, text: "回到本应用，窗口列表会自动出现")
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 10) {
                        Button {
                            model.requestScreenPermission()
                        } label: {
                            Label("授权屏幕录制", systemImage: "rectangle.dashed")
                                .font(.system(size: 12.5, weight: .semibold))
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(GradientButtonStyle())

                        Button("已授权，刷新窗口") {
                            model.refreshPermissions()
                            Task { await model.refreshWindows() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Text("macOS 可能在首次授权后要求重新启动应用。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 450, alignment: .leading)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 24, y: 10)
            )
            Spacer(minLength: 20)

            HStack(spacing: 6) {
                Image(systemName: "hand.raised")
                Text("需要自动滚动时，还会请求“辅助功能”权限。")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var illustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.16), Color.purple.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 230, height: 270)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 122, height: 188)
                    .shadow(color: .black.opacity(0.15), radius: 14, y: 6)

                VStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: 82, height: 18)
                    ForEach(0..<6, id: \.self) { index in
                        Capsule()
                            .fill(Color.primary.opacity(index == 5 ? 0.08 : 0.14))
                            .frame(width: index % 3 == 0 ? 82 : 66, height: 5)
                            .frame(width: 82, alignment: .leading)
                    }
                }
            }
            .offset(y: -8)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.16, green: 0.52, blue: 1),
                                             Color(red: 0.48, green: 0.30, blue: 0.96)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 58, height: 58)
                            .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: -16, y: -18)
                }
            }
            .frame(width: 230, height: 270)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
