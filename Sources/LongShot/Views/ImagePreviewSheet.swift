import SwiftUI

struct ImagePreviewSheet: View {
    let result: CaptureResult
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PreviewMode = .fitWidth

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("查看图片")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(result.dimensionsText) · 原始像素无损 PNG")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $mode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 210)

                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            TiledImagePreview(rawImage: result.rawImage, mode: mode)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 22)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("滚动或双指滑动查看长图；100% 为屏幕像素 1:1，200% 用于检查文字细节。")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 12)
        }
        .frame(width: 1_060, height: 740)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
