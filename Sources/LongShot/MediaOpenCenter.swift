import Foundation

extension Notification.Name {
    static let mediaOpenRequested = Notification.Name("com.seven.longshot.mediaOpenRequested")
}

final class MediaOpenCenter {
    static let shared = MediaOpenCenter()

    private var pending: [URL] = []

    private init() {}

    func enqueue(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return }

        let append = { [weak self] in
            guard let self else { return }
            self.pending.append(contentsOf: files)
            NotificationCenter.default.post(name: .mediaOpenRequested, object: nil)
        }

        if Thread.isMainThread {
            append()
        } else {
            DispatchQueue.main.async(execute: append)
        }
    }

    func consume() -> [URL] {
        let files = pending
        pending.removeAll()
        return files
    }
}
