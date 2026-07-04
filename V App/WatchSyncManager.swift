import Foundation
import UIKit
import WatchConnectivity

/// Mirrors the memory library to the paired Apple Watch.
///
/// The watch has no access to the iPhone's App Group, so data travels over
/// WatchConnectivity through three complementary channels:
///
/// 1. **Application context** — the metadata of the most recent memories
///    (small, latest snapshot wins). Lets the watch render its list and prune
///    deletions even before any photo arrives.
/// 2. **User-info transfers** — one per memory with its photo, queued by the
///    system for background delivery to a real device.
/// 3. **On-demand messages** — the watch asks for the library or a single
///    photo while both apps are reachable (`sendMessage`). This is the fast
///    path, and the only one that works reliably in the simulator.
final class WatchSyncManager: NSObject, WCSessionDelegate {
    static let shared = WatchSyncManager()

    /// Most recent memories mirrored to the watch.
    private static let maxMemories = 12
    /// Max side of the photo sent to the watch; sized for the largest watch
    /// screen while keeping each payload under the WCSession message limit.
    private static let imageMaxSide: CGFloat = 400

    /// Hard ceiling for any single WCSession payload; the documented limit is
    /// ~65 KB, kept with margin for the dictionary metadata.
    private static let maxPayloadBytes = 60_000

    private struct Snapshot: Sendable, Equatable {
        let id: String
        let message: String
        let date: String
        let order: Int
    }

    /// Mutable sync state. Written from the main actor, read from the
    /// WCSession delegate queue, hence the lock.
    private struct SyncState {
        var snapshots: [Snapshot] = []
        /// What the last successful context push contained, to skip no-ops.
        var pushedSnapshots: [Snapshot]?
        /// Image ids already queued for transfer this launch.
        var queuedImageIDs: Set<String> = []
    }

    private let stateLock = NSLock()
    private var state = SyncState()

    private var lastSnapshots: [Snapshot] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.snapshots
    }

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call on the main actor with the current library.
    func sync(_ memories: [Memory]) {
        let snapshots = memories
            .sorted { $0.order > $1.order }
            .prefix(Self.maxMemories)
            .filter { !$0.imageFileName.isEmpty }
            .map { Snapshot(id: $0.imageFileName, message: $0.message, date: $0.formattedDate, order: $0.order) }
        stateLock.lock()
        state.snapshots = snapshots
        stateLock.unlock()
        pushIfPossible()
    }

    private func metadataPayload(for snapshots: [Snapshot]) -> [[String: Any]] {
        snapshots.map { ["id": $0.id, "message": $0.message, "date": $0.date, "order": $0.order] }
    }

    /// The in-memory snapshot when the app has synced this launch; otherwise
    /// the recovery file on disk. The fallback matters when the watch's
    /// request wakes this app in the background and the UI (which normally
    /// feeds `sync`) never ran.
    private func currentSnapshots() -> [Snapshot] {
        let snapshots = lastSnapshots
        if !snapshots.isEmpty { return snapshots }

        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        return LocalStore.shared.loadMetadata()
            .sorted { $0.order > $1.order }
            .prefix(Self.maxMemories)
            .filter { !$0.imageFileName.isEmpty }
            .map {
                Snapshot(
                    id: $0.imageFileName,
                    message: $0.message,
                    date: iso.date(from: $0.date).map { formatter.string(from: $0) } ?? $0.date,
                    order: $0.order
                )
            }
    }

    private func pushIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }

        // Diff against what was already pushed so repeated syncs (saves,
        // backgrounding) don't re-send unchanged data.
        stateLock.lock()
        let snapshots = state.snapshots
        let contextChanged = state.pushedSnapshots != snapshots
        let currentIDs = Set(snapshots.map(\.id))
        state.queuedImageIDs.formIntersection(currentIDs)
        let pendingIDs = currentIDs.subtracting(state.queuedImageIDs)
        state.pushedSnapshots = snapshots
        state.queuedImageIDs.formUnion(pendingIDs)
        stateLock.unlock()

        if contextChanged {
            try? session.updateApplicationContext(["memories": metadataPayload(for: snapshots)])
        }

        guard !pendingIDs.isEmpty else { return }

        // Queue photo pushes for background delivery on a real device. The
        // watch also pulls photos on demand, so this is best-effort.
        Task.detached(priority: .utility) {
            for transfer in session.outstandingUserInfoTransfers {
                if let id = transfer.userInfo["id"] as? String, !currentIDs.contains(id) {
                    transfer.cancel()
                }
            }
            for snapshot in snapshots where pendingIDs.contains(snapshot.id) {
                guard let data = Self.imageData(for: snapshot.id) else { continue }
                session.transferUserInfo([
                    "id": snapshot.id,
                    "message": snapshot.message,
                    "date": snapshot.date,
                    "order": snapshot.order,
                    "image": data
                ])
            }
        }
    }

    /// JPEG sized to fit `maxPayloadBytes`: steps quality down first, then
    /// the dimensions, so detailed photos can't exceed the WCSession limit.
    private static func imageData(for id: String) -> Data? {
        guard let image = LocalStore.shared.loadImage(named: id) else { return nil }
        var maxSide = imageMaxSide
        for _ in 0..<3 {
            let resized = image.downscaled(maxSide: maxSide)
            for quality: CGFloat in [0.5, 0.35, 0.25] {
                if let data = resized.jpegData(compressionQuality: quality),
                   data.count <= maxPayloadBytes {
                    return data
                }
            }
            maxSide *= 0.7
        }
        return nil
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.pushIfPossible() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.pushIfPossible() }
    }

    /// On-demand requests from the watch: the full library metadata, or one
    /// photo by id. Runs on the WCSession delegate queue.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["request"] as? String {
        case "library":
            replyHandler(["memories": metadataPayload(for: currentSnapshots())])
        case "image":
            if let id = message["id"] as? String, let data = Self.imageData(for: id) {
                replyHandler(["image": data])
            } else {
                replyHandler([:])
            }
        default:
            replyHandler([:])
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
