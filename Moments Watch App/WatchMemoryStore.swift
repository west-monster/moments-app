import Foundation
import UIKit
import WatchConnectivity

struct WatchMemory: Codable, Identifiable, Equatable {
    let id: String
    let message: String
    let date: String
    let order: Int
}

/// Receives the memory library mirrored from the iPhone (see the app's
/// `WatchSyncManager`) and caches it in Documents so the watch app works
/// without the phone nearby.
///
/// Sync is pull-first: on activation the store applies the last received
/// application context, asks the phone for the current library, and then
/// requests every photo it doesn't have yet (`sendMessage` wakes the iPhone
/// app if needed). Background pushes from the phone (`didReceiveUserInfo`)
/// fill the same cache when the apps aren't reachable.
final class WatchMemoryStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var memories: [WatchMemory] = []
    @Published private(set) var images: [String: UIImage] = [:]

    private let fileManager = FileManager.default

    override init() {
        super.init()
        loadFromDisk()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Local cache

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var metadataURL: URL {
        documentsURL.appendingPathComponent("memories.json")
    }

    private func imageURL(for id: String) -> URL {
        documentsURL.appendingPathComponent("memory_\(id)")
    }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: metadataURL),
           let stored = try? JSONDecoder().decode([WatchMemory].self, from: data) {
            memories = stored.sorted { $0.order > $1.order }
        }
        for memory in memories {
            if let image = UIImage(contentsOfFile: imageURL(for: memory.id).path) {
                images[memory.id] = image
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(memories) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    // MARK: - Updates (main thread)

    private func apply(metadata: Any?) {
        guard let list = metadata as? [[String: Any]] else { return }
        let parsed = list.compactMap { dict -> WatchMemory? in
            guard let id = dict["id"] as? String,
                  let message = dict["message"] as? String,
                  let date = dict["date"] as? String,
                  let order = dict["order"] as? Int else { return nil }
            return WatchMemory(id: id, message: message, date: date, order: order)
        }
        // An empty list is a valid "no memories" state; a non-empty list that
        // fails to parse is garbage — keep what we have.
        if parsed.isEmpty && !list.isEmpty { return }

        memories = parsed.sorted { $0.order > $1.order }
        persist()

        // Drop cached photos for memories that no longer exist.
        let ids = Set(parsed.map(\.id))
        for staleID in images.keys where !ids.contains(staleID) {
            images.removeValue(forKey: staleID)
            try? fileManager.removeItem(at: imageURL(for: staleID))
        }
    }

    private func storeImage(_ data: Data, for id: String) {
        guard let image = UIImage(data: data) else { return }
        try? data.write(to: imageURL(for: id), options: .atomic)
        images[id] = image
    }

    private func upsert(_ memory: WatchMemory, imageData: Data) {
        memories.removeAll { $0.id == memory.id }
        memories.append(memory)
        memories.sort { $0.order > $1.order }
        persist()
        storeImage(imageData, for: memory.id)
    }

    // MARK: - Pull from the phone

    private static let maxAttempts = 3
    private static let retryDelay: TimeInterval = 2

    /// Photo requests currently in flight, so overlapping triggers
    /// (activation, context, reachability) don't duplicate messages.
    private var pendingImageIDs: Set<String> = []

    /// `notReachable` failures are not retried on a timer — the phone is
    /// simply away, and `sessionReachabilityDidChange` re-requests everything
    /// the moment it returns. Timed retries are reserved for transient
    /// delivery errors while reachable.
    private static func isUnreachable(_ error: Error) -> Bool {
        (error as? WCError)?.code == .notReachable
    }

    private func requestLibrary(attempt: Int = 0) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "library"], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.apply(metadata: reply["memories"])
                self?.requestMissingImages()
            }
        }, errorHandler: { [weak self] error in
            guard !Self.isUnreachable(error), attempt + 1 < Self.maxAttempts else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) {
                self?.requestLibrary(attempt: attempt + 1)
            }
        })
    }

    private func requestMissingImages() {
        for memory in memories where images[memory.id] == nil && !pendingImageIDs.contains(memory.id) {
            requestImage(for: memory.id)
        }
    }

    private func requestImage(for id: String, attempt: Int = 0) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            pendingImageIDs.remove(id)
            return
        }
        pendingImageIDs.insert(id)
        session.sendMessage(["request": "image", "id": id], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.pendingImageIDs.remove(id)
                guard let data = reply["image"] as? Data else { return }
                self?.storeImage(data, for: id)
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                guard !Self.isUnreachable(error), attempt + 1 < Self.maxAttempts else {
                    self?.pendingImageIDs.remove(id)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) {
                    self?.requestImage(for: id, attempt: attempt + 1)
                }
            }
        })
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            // Context delivered while the app wasn't running.
            self.apply(metadata: session.receivedApplicationContext["memories"])
            self.requestLibrary()
            self.requestMissingImages()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            guard session.isReachable else { return }
            self.requestLibrary()
            self.requestMissingImages()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.apply(metadata: applicationContext["memories"])
            self.requestMissingImages()
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = userInfo["id"] as? String,
              let message = userInfo["message"] as? String,
              let date = userInfo["date"] as? String,
              let order = userInfo["order"] as? Int,
              let imageData = userInfo["image"] as? Data else { return }
        DispatchQueue.main.async {
            self.upsert(WatchMemory(id: id, message: message, date: date, order: order), imageData: imageData)
        }
    }
}
