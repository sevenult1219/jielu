import AppKit
import SwiftUI

struct RecordingResultView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: RecordingResult

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "record.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("录屏已保存")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("\(result.durationText) · \(result.dimensionsText) px · \(result.fileSizeText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    finish()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            VideoPlayerPanel(url: result.url, thumbnail: result.thumbnail, mixesAudioTracks: true)
                .frame(height: 380)
                .padding(.horizontal, 24)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.url])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    NSWorkspace.shared.open(result.url)
                } label: {
                    Label("用默认播放器打开", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(spacing: 5) {
                Image(systemName: "film")
                Text("影片/长截屏/\(result.url.lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(width: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            model.dismissRecordingResult()
        }
    }

    private func finish() {
        model.dismissRecordingResult()
        dismiss()
    }
}
