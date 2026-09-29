import CloudKit
import Foundation

/// A document as reconciliation sees it: only the parts that sync, read
/// without touching the word blobs.
nonisolated struct LocalDocumentSnapshot: Equatable {
    var id: UUID
    var title: String
    var position: ReadingPosition
    var dateAdded: Date
    /// Shown by a reader, book page, or alert right now, so it can't be
    /// removed yet.
    var isOpen = false
}

/// What reconciliation found for iCloud sync to do.
nonisolated struct ReconcilePlan: Equatable {
    /// Records with local changes iCloud doesn't have.
    var saves: [CloudRecordKey] = []
    /// Records of documents deleted on this device that iCloud still has.
    var deletes: [CloudRecordKey] = []
    /// Documents to take off this device now that nothing shows them.
    var removals: [UUID] = []
    /// Positions to write into local documents: a removed copy's reading
    /// handed to the copy that stays.
    var positionUpdates: [UUID: ReadingPosition] = [:]
}

/// What this device knows about its library in iCloud: each document's
/// records as last confirmed by the server, local changes not yet sent, and
/// deletions not yet confirmed.
///
/// Kept in its own file beside the SwiftData store, never in it, so syncing
/// doesn't change the store's schema. Losing the file is safe: the next start
/// fetches everything, matches it to the library by document ID, and uploads
/// what iCloud doesn't have. Sync never deletes anything because ledger state
/// is missing:
/// - A deletion is only sent for a document this ledger saw in the library
///   that has since left it, or for a local copy merged into an identical
///   book already in iCloud.
/// - Nothing is uploaded until a full fetch has shown what iCloud has.
/// - Only a copy that was never uploaded is ever merged away.
nonisolated struct CloudSyncLedger: Codable {
    struct Entry: Codable, Equatable {
        enum Removal: Codable, Equatable {
            /// Deleted from iCloud by another device while shown here. Its
            /// reading goes to an identical local copy, if there is one.
            case deletedElsewhere(foldInto: UUID?)
            /// A copy never uploaded, of a book already in iCloud as the
            /// given document. Its reading goes to that document.
            case mergedInto(UUID)
        }

        /// The document has been in this device's library. Entries without
        /// one hold a reading state whose book hasn't arrived yet.
        var hasLocalDocument = false
        /// Set when the document is to leave this device once nothing shows it.
        var removal: Removal?
        var bookSystemFields: Data?
        var stateSystemFields: Data?
        /// The title iCloud has.
        var syncedTitle: String?
        /// The reading state iCloud has.
        var syncedState: StampedReadingPosition?
        /// A local reading state iCloud doesn't have yet, stamped when its
        /// resume point was set.
        var localState: StampedReadingPosition?
        var contentHash: String?
    }

    /// `CKSyncEngine`'s own state: change tokens and pending changes.
    var engineState: CKSyncEngine.State.Serialization?
    /// The SwiftData store these entries describe. Any other store (a reset
    /// or replaced library) means none of them apply.
    var storeIdentifier: String?
    /// Whether a full fetch has finished since this ledger started. Until
    /// then nothing is uploaded, so a library that iCloud already has (the
    /// same books under the same IDs, or identical books from another
    /// device) isn't sent again.
    var hasFetchedEverything = false
    /// Keyed by document UUID string.
    var entries: [String: Entry] = [:]
    /// Documents deleted here whose records iCloud hasn't confirmed deleting.
    var pendingDeletes: Set<String> = []

    func entry(for id: UUID) -> Entry? {
        entries[id.uuidString]
    }

    func isPendingDelete(_ id: UUID) -> Bool {
        pendingDeletes.contains(id.uuidString)
    }

    /// Whether iCloud has confirmed the document's book record.
    func isInICloud(_ id: UUID) -> Bool {
        entries[id.uuidString]?.bookSystemFields != nil
    }

    /// Whether this ledger no longer describes the library: many documents
    /// it saw are gone at once, as when an older copy of the store is
    /// restored. Sending those as deletions would delete them everywhere, so
    /// sync starts over instead, and anything missing comes back from iCloud.
    func hasLostTrack(ofLibraryWith presentIDs: Set<UUID>) -> Bool {
        let known = entries.filter { $0.value.hasLocalDocument && $0.value.removal == nil }.keys
        let missing = known.filter { key in
            UUID(uuidString: key).map { !presentIDs.contains($0) } ?? false
        }
        return missing.count >= 3 && missing.count * 4 >= known.count
    }

    /// The stamp for a local document's position. Only a change to the
    /// resume point or speed counts as newer: opening and closing a book
    /// touches its last-read date without moving it, and that mustn't beat
    /// reading done on another device. Unchanged since the last sync keeps
    /// iCloud's stamp, a pending change keeps the stamp it got when first
    /// seen, and a document that has never synced uses its own dates, so the
    /// first upload of an existing library doesn't make every copy look just
    /// read.
    func stamped(_ id: UUID, position: ReadingPosition, dateAdded: Date, now: Date) -> StampedReadingPosition {
        let entry = entry(for: id)
        let modifiedAt: Date
        if let synced = entry?.syncedState, synced.position.hasSameResumePoint(as: position) {
            modifiedAt = synced.modifiedAt
        } else if let pending = entry?.localState, pending.position.hasSameResumePoint(as: position) {
            modifiedAt = pending.modifiedAt
        } else if entry?.syncedState == nil && entry?.localState == nil {
            modifiedAt = position.lastReadDate ?? dateAdded
        } else {
            modifiedAt = now
        }
        return StampedReadingPosition(position: position, modifiedAt: modifiedAt)
    }

    /// Hands a copy's reading to the copy that stays. Returns the kept
    /// copy's new position, or nil if it doesn't change. The copy's entry
    /// must still exist.
    mutating func mergeReading(
        from copy: LocalDocumentSnapshot,
        into keeper: LocalDocumentSnapshot,
        now: Date
    ) -> ReadingPosition? {
        let merged = StampedReadingPosition.merged(
            stamped(keeper.id, position: keeper.position, dateAdded: keeper.dateAdded, now: now),
            stamped(copy.id, position: copy.position, dateAdded: copy.dateAdded, now: now)
        )
        guard merged.position != keeper.position else { return nil }
        entries[keeper.id.uuidString, default: Entry()].localState = merged
        return merged.position
    }

    // MARK: - Local changes

    /// Compares the library with what iCloud last confirmed. Records new
    /// local changes and returns the records to send.
    mutating func reconcile(_ documents: [LocalDocumentSnapshot], now: Date) -> ReconcilePlan {
        var plan = ReconcilePlan()
        let presentIDs = Set(documents.map(\.id))
        var snapshots = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Documents waiting to leave go once nothing shows them, handing
        // their reading to the copy that stays.
        for (key, entry) in entries {
            guard let removal = entry.removal, let id = UUID(uuidString: key) else { continue }
            if let document = snapshots[id] {
                guard !document.isOpen else { continue }
                let keeperID: UUID?
                switch removal {
                case .deletedElsewhere(let foldInto):
                    keeperID = foldInto
                case .mergedInto(let target):
                    // The copy in iCloud is gone or going, or this one
                    // turned out to be in iCloud too: it stays, like any
                    // other book.
                    guard snapshots[target] != nil,
                          entries[target.uuidString]?.removal == nil,
                          entry.bookSystemFields == nil else {
                        entries[key]?.removal = nil
                        continue
                    }
                    keeperID = target
                }
                if let keeperID, let keeper = snapshots[keeperID],
                   let position = mergeReading(from: document, into: keeper, now: now) {
                    snapshots[keeperID]?.position = position
                    plan.positionUpdates[keeperID] = position
                }
                plan.removals.append(id)
                snapshots[id] = nil
            }
            if case .mergedInto = removal {
                // Never uploaded as far as this device knows; if an upload
                // did land, the book it duplicates is in iCloud, so deleting
                // this copy's records loses nothing.
                pendingDeletes.insert(key)
            }
            entries[key] = nil
        }

        for document in snapshots.values {
            let key = document.id.uuidString
            var entry = entries[key] ?? Entry()
            // Still shown while waiting to leave: nothing to send for it.
            guard entry.removal == nil else { continue }
            entry.hasLocalDocument = true
            if entry.bookSystemFields == nil || entry.syncedTitle != document.title {
                plan.saves.append(CloudRecordKey(.book, document.id))
            }
            if entry.stateSystemFields == nil || entry.syncedState?.position != document.position {
                entry.localState = stamped(document.id, position: document.position, dateAdded: document.dateAdded, now: now)
                plan.saves.append(CloudRecordKey(.state, document.id))
            } else {
                entry.localState = nil
            }
            entries[key] = entry
        }

        // Documents that were in the library and aren't any more were
        // deleted here.
        for (key, entry) in entries where entry.hasLocalDocument && entry.removal == nil {
            guard let id = UUID(uuidString: key), !presentIDs.contains(id) else { continue }
            pendingDeletes.insert(key)
            entries[key] = nil
        }

        plan.saves.sort()
        plan.removals.sort { $0.uuidString < $1.uuidString }
        plan.deletes = pendingDeletes.sorted().compactMap(UUID.init(uuidString:)).flatMap {
            [CloudRecordKey(.book, $0), CloudRecordKey(.state, $0)]
        }
        return plan
    }

    /// Marks a local copy that was never uploaded, of a book iCloud already
    /// has as `keeperID`. It leaves once nothing shows it, handing its
    /// reading to the kept copy.
    mutating func markMerged(_ id: UUID, into keeperID: UUID) {
        var entry = entries[id.uuidString] ?? Entry()
        entry.hasLocalDocument = true
        entry.removal = .mergedInto(keeperID)
        entries[id.uuidString] = entry
    }

    // MARK: - Records from iCloud

    /// Takes in a book record, fetched or returned by a conflict. Returns a
    /// title to show locally, or nil to keep the local one: a rename made
    /// here and not yet sent wins over an older title in iCloud.
    mutating func receiveBook(
        _ fields: BookRecordFields,
        systemFields: Data,
        for id: UUID,
        localTitle: String?
    ) -> String? {
        let key = id.uuidString
        var entry = entries[key] ?? Entry()
        let previousTitle = entry.syncedTitle
        entry.bookSystemFields = systemFields
        entry.syncedTitle = fields.title
        entry.contentHash = fields.contentHash
        entries[key] = entry
        guard let localTitle, localTitle != fields.title else { return nil }
        let renamedHere = previousTitle != nil && localTitle != previousTitle
        return renamedHere ? nil : fields.title
    }

    /// Takes in a reading state record. `local` is the document's current
    /// position, or nil when its book hasn't arrived; the state then waits
    /// in the ledger for it. Returns the position the document should show,
    /// merged with any local reading iCloud doesn't have yet.
    mutating func receiveState(
        _ remote: StampedReadingPosition,
        systemFields: Data,
        for id: UUID,
        local: (position: ReadingPosition, dateAdded: Date)?,
        now: Date
    ) -> ReadingPosition? {
        let key = id.uuidString
        var localStamp: StampedReadingPosition?
        if let local {
            localStamp = stamped(id, position: local.position, dateAdded: local.dateAdded, now: now)
        }
        var entry = entries[key] ?? Entry()
        entry.stateSystemFields = systemFields
        entry.syncedState = remote
        guard let localStamp else {
            entries[key] = entry
            return nil
        }
        let merged = StampedReadingPosition.merged(localStamp, remote)
        entry.localState = merged.position == remote.position ? nil : merged
        entries[key] = entry
        return merged.position
    }

    /// Records a document from iCloud as part of this device's library.
    /// Called only after the store has saved it, so a failed save can never
    /// look like a local deletion.
    mutating func markLocal(_ id: UUID) {
        entries[id.uuidString, default: Entry()].hasLocalDocument = true
    }

    /// Takes in a record deleted from iCloud. For a book, returns whether
    /// to remove the local document now; a document that's open waits until
    /// it closes, then hands its reading to `foldInto`.
    mutating func receiveDeletion(of record: CloudRecordKey, isOpen: Bool, foldInto: UUID? = nil) -> Bool {
        let key = record.documentID.uuidString
        switch record.kind {
        case .book:
            pendingDeletes.remove(key)
            // No entry: nothing here is known to be that book's synced copy.
            guard var entry = entries[key], entry.hasLocalDocument else {
                entries[key] = nil
                return false
            }
            if isOpen {
                entry.removal = .deletedElsewhere(foldInto: foldInto)
                entries[key] = entry
                return false
            }
            entries[key] = nil
            return true
        case .state:
            if let entry = entries[key], !entry.hasLocalDocument {
                entries[key] = nil
            }
            return false
        }
    }

    // MARK: - Send results

    mutating func setContentHash(_ contentHash: String, for id: UUID) {
        entries[id.uuidString]?.contentHash = contentHash
    }

    /// Records a save iCloud confirmed. `title` and `state` are the values
    /// the saved record carries.
    mutating func confirmSaved(
        _ record: CloudRecordKey,
        systemFields: Data,
        title: String?,
        state: StampedReadingPosition?
    ) {
        let key = record.documentID.uuidString
        // Deleted here while the save was in flight: the deletion follows.
        guard var entry = entries[key] else { return }
        switch record.kind {
        case .book:
            entry.bookSystemFields = systemFields
            if let title { entry.syncedTitle = title }
        case .state:
            entry.stateSystemFields = systemFields
            if let state {
                entry.syncedState = state
                if entry.localState?.position == state.position {
                    entry.localState = nil
                }
            }
        }
        entries[key] = entry
    }

    mutating func confirmDeleted(_ record: CloudRecordKey) {
        if record.kind == .book {
            pendingDeletes.remove(record.documentID.uuidString)
        }
    }

    /// Forgets a record iCloud no longer has, so the next save creates it
    /// again.
    mutating func forgetServerRecord(_ record: CloudRecordKey) {
        let key = record.documentID.uuidString
        guard var entry = entries[key] else { return }
        switch record.kind {
        case .book:
            entry.bookSystemFields = nil
            entry.syncedTitle = nil
        case .state:
            entry.stateSystemFields = nil
            entry.syncedState = nil
        }
        entries[key] = entry
    }

    /// Forgets every record after iCloud lost the zone (an encrypted data
    /// reset), so the whole library uploads again. What's in the library
    /// here is kept.
    mutating func forgetServerRecords() {
        for (key, entry) in entries {
            guard entry.hasLocalDocument else {
                entries[key] = nil
                continue
            }
            var kept = Entry()
            kept.hasLocalDocument = true
            kept.removal = entry.removal
            kept.contentHash = entry.contentHash
            entries[key] = kept
        }
        pendingDeletes.removeAll()
    }

    // MARK: - Storage

    static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "CloudSync", directoryHint: .isDirectory)
            .appending(path: "Ledger.plist")
    }

    /// The saved ledger, or an empty one. An unreadable file is set aside
    /// for diagnosis; an empty ledger only means fetching and matching again.
    static func load(from url: URL = fileURL) -> CloudSyncLedger {
        guard let data = try? Data(contentsOf: url) else { return CloudSyncLedger() }
        do {
            return try PropertyListDecoder().decode(CloudSyncLedger.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("unreadable"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable"))
            return CloudSyncLedger()
        }
    }

    func save(to url: URL = Self.fileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

nonisolated extension ReadingPosition {
    /// The part of a position that the most recent device decides: where to
    /// resume and at what speed. The furthest point and last-read date only
    /// ever move forward, so they don't make a position newer.
    func hasSameResumePoint(as other: ReadingPosition) -> Bool {
        currentWordIndex == other.currentWordIndex && wordsPerMinute == other.wordsPerMinute
    }
}
