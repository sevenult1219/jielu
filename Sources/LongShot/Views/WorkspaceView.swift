import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.section {
            case .home:
                HomeView()
            case .screenshot:
                ScreenshotWorkspace()
            case .record:
                RecordWorkspace()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}
