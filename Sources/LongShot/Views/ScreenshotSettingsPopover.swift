import SwiftUI

struct ScreenshotSettingsPopover: View {
    @EnvironmentObject private var model: AppModel

    private var overlapBinding: Binding<Double> {
        Binding(
            get: { model.settings.overlapFraction },
            set: { model.settings.overlapFraction = $0 }
        )
    }

    private var delayBinding: Binding<Double> {
        Binding(
            get: { model.settings.scrollDelay },
            set: { model.settings.scrollDelay = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("截屏设置")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("重叠区域")
                        .font(.system(size: 11.5))
                    Spacer()
                    Text("\(Int((model.settings.overlapFraction * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: overlapBinding, in: 0.45...0.70, step: 0.05)
                    .controlSize(.small)
                Text("重叠越多，拼接越稳，滚动次数也会增加。")
                    .font(.system(size: 9.8))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("滚动等待")
                        .font(.system(size: 11.5))
                    Spacer()
                    Text(String(format: "%.2f 秒", model.settings.scrollDelay))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Picker("", selection: delayBinding) {
                    Text("0.35").tag(0.35)
                    Text("0.55").tag(0.55)
                    Text("0.80").tag(0.80)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                Text("页面有惯性滚动动画时，选择更长的等待时间。")
                    .font(.system(size: 9.8))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .opacity(0.55)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("无长度限制 · 原始像素")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("仅受磁盘剩余空间限制")
                        .font(.system(size: 9.2))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
            )
        }
        .padding(18)
        .frame(width: 292)
    }
}
