import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData
import SwiftUI
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Syncs the library and each book's reading position through the user's
/// private iCloud database with `CKSyncEngine`.
///
/// Sync sits beside SwiftData, not inside it: the store keeps its schema and
/// every device's library stays local-first. After each save,
/// ``CloudSyncLedger`` compares the library with what iCloud last confirmed
/// and queues what changed. Changes from other devices are merged into the
/// store on the main context and saved like any local edit, so
/// `ModelContext.didSave` observers see them too.
///
/// Each document syncs as a book record (title, file name, date added,
/// chapters, words, complexity scores) and a reading state record. The
/// security-scoped bookmark stays on the device that made it, which is the
/// only place it resolves.
///
/// Explicitly main-actor: conforming to a `Sendable` protocol opts a type out
/// of the target's default isolation.
@MainActor
@Observable
final class LibrarySync: CKSyncEngineDelegate {
    static let shared = LibrarySync()

    enum Status: Equatable {
        /// Turned off in Settings.
        case off
        /// Turned off because Strobe's data was deleted from iCloud.
        case offAfterICloudDeletion
        /// Not available in this process (tests and previews).
        case unavailable
        case signedOut
        case restricted
        case temporarilyUnavailable
        case storageFull
        case syncing
        case upToDate
    }

    private(set) var isEnabled = false
    private(set) var stoppedAfterICloudDeletion = false
    private(set) var accountStatus: CKAccountStatus?
    private(set) var isStorageFull = false
    private var activeOperations = 0

    var status: Status {
        guard isEnabled else { return stoppedAfterICloudDeletion ? .offAfterICloudDeletion : .off }
        guard Self.isCloudKitAvailable else { return .unavailable }
        switch accountStatus {
        case .noAccount: return .signedOut
        case .restricted: return .restricted
        case .temporarilyUnavailable, .couldNotDetermine: return .temporarilyUnavailable
        default: break
        }
        if isStorageFull { return .storageFull }
        return activeOperations > 0 ? .syncing : .upToDate
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var cloudContainer: CKContainer?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var ledger = CloudSyncLedger()
    @ObservationIgnored private var openDocuments: [UUID: Int] = [:]
    @ObservationIgnored private var recentlyClosed: [UUID: Date] = [:]
    /// Records not to send again before a time, after a failure that
    /// retrying right away wouldn't fix. Keyed by record name.
    @ObservationIgnored private var heldRecords: [String: Date] = [:]
    /// No saves before this time, after iCloud reported the storage full.
    @ObservationIgnored private var storageFullUntil: Date?
    @ObservationIgnored private var lastFetchRequest = Date.distantPast
    @ObservationIgnored private var isReconcileScheduled = false
    @ObservationIgnored private var didRefetchAfterSaveFailure = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe",
        category: "CloudSync"
    )

    /// A document closed this recently still counts as open. Covers the
    /// moment between one view closing and the next opening during
    /// navigation.
    private static let closeGracePeriod: TimeInterval = 2
    /// Caps on one send batch, so a first sync of a large library doesn't
    /// write every book's words out for upload at once.
    private static let maxRecordsPerBatch = 200
    private static let maxAssetBytesPerBatch = 40_000_000

    /// Test hosts and previews run without the app's iCloud entitlement, and
    /// creating a `CKContainer` there crashes.
    static let isCloudKitAvailable: Bool = {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        return !environment.keys.contains { $0.hasPrefix("XCTest") }
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Starts sync for the app's library if it's turned on. Later calls do nothing.
    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        observers.append(NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccountStatus() }
        })
        // After launch finishes: starting reads the ledger and the library.
        Task { updateEnabled() }
    }

    /// Starts or stops sync to match the Settings toggle.
    func updateEnabled() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: ReaderSettings.Keys.iCloudSyncEnabled) as? Bool
            ?? ReaderSettings.Defaults.iCloudSyncEnabled
        stoppedAfterICloudDeletion = defaults.bool(forKey: ReaderSettings.Keys.iCloudSyncStoppedAfterDeletion)
        guard container != nil, Self.isCloudKitAvailable else { return }
        if isEnabled {
            if stoppedAfterICloudDeletion {
                defaults.set(false, forKey: ReaderSettings.Keys.iCloudSyncStoppedAfterDeletion)
                stoppedAfterICloudDeletion = false
            }
            if engine == nil { startEngine() }
        } else if engine != nil {
            engine = nil
            activeOperations = 0
            saveLedger()
        }
    }

    /// Fetches when the app comes forward, so another device's reading shows
    /// up without waiting for a push.
    func sceneDidBecomeActive() {
        guard engine != nil else { return }
        refreshAccountStatus()
        scheduleReconcile()
        fetchChanges(unlessFetchedWithin: 10)
    }

    /// Sends the last reading position before the app is suspended.
    func sceneDidEnterBackground() {
        guard let engine else { return }
        reconcile()
        #if os(iOS)
        let backgroundTask = BackgroundTask(name: "iCloud Sync")
        #endif
        Task {
            do {
                try await engine.sendChanges()
            } catch {
                logger.info("Send on backgrounding failed: \(error.localizedDescription, privacy: .public)")
            }
            #if os(iOS)
            backgroundTask.end()
            #endif
        }
    }

    // MARK: - Open documents

    func documentDidOpen(_ id: UUID) {
        let wasClosed = openDocuments[id] == nil
        openDocuments[id, default: 0] += 1
        // Opening a book is when reading done on another device matters.
        if wasClosed {
            fetchChanges(unlessFetchedWithin: 15)
        }
    }

    /// A document deleted on another device while open here leaves once it
    /// closes.
    func documentDidClose(_ id: UUID) {
        guard let count = openDocuments[id] else { return }
        guard count <= 1 else {
            openDocuments[id] = count - 1
            return
        }
        openDocuments[id] = nil
        recentlyClosed[id] = .now
        Task {
            try? await Task.sleep(for: .seconds(Self.closeGracePeriod + 0.5))
            recentlyClosed = recentlyClosed.filter { Date.now.timeIntervalSince($0.value) < Self.closeGracePeriod }
            scheduleReconcile()
        }
    }

    /// Keeps a document an alert or menu refers to while it's up.
    func documentReferenceChanged(from old: UUID?, to new: UUID?) {
        guard old != new else { return }
        if let new { documentDidOpen(new) }
        if let old { documentDidClose(old) }
    }

    private func isOpen(_ id: UUID, now: Date) -> Bool {
        if openDocuments[id] != nil { return true }
        guard let closedAt = recentlyClosed[id] else { return false }
        return now.timeIntervalSince(closedAt) < Self.closeGracePeriod
    }

    // MARK: - Engine

    private func startEngine() {
        ledger = CloudSyncLedger.load()
        checkStoreIdentity()
        checkLedgerStillDescribesLibrary()
        BookUpload.removeAllFiles()
        let cloudContainer = CKContainer(identifier: CloudSyncSchema.containerIdentifier)
        let configuration = CKSyncEngine.Configuration(
            database: cloudContainer.privateCloudDatabase,
            stateSerialization: ledger.engineState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        if ledger.engineState == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSyncSchema.zoneID))])
        }
        self.cloudContainer = cloudContainer
        self.engine = engine
        activeOperations = 0
        heldRecords = [:]
        storageFullUntil = nil
        refreshAccountStatus()
        reconcile()
        registerForRemoteNotifications()
        lastFetchRequest = .distantPast
        fetchChanges(unlessFetchedWithin: 0)
    }

    /// Starts over with a new engine from `ledger` as it now stands.
    private func restartEngine() {
        engine = nil
        activeOperations = 0
        saveLedger()
        guard isEnabled else { return }
        Task { if engine == nil && isEnabled { startEngine() } }
    }

    private func fetchChanges(unlessFetchedWithin interval: TimeInterval) {
        guard let engine, Date.now.timeIntervalSince(lastFetchRequest) >= interval else { return }
        lastFetchRequest = .now
        Task {
            do {
                try await engine.fetchChanges()
                // Only a fetch that returns without error has seen all of
                // iCloud. (`didFetchChanges` also follows failed fetches,
                // such as with no account signed in.)
                if engine === self.engine {
                    finishFirstFetchIfNeeded()
                }
            } catch {
                logger.info("Fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Forgets the ledger if it describes a different SwiftData store: a
    /// reset or replaced library must not read as every book deleted. The
    /// library then merges with iCloud as if syncing for the first time.
    private func checkStoreIdentity() {
        guard let url = container?.configurations.first?.url,
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url),
              let identifier = metadata[NSStoreUUIDKey] as? String else { return }
        if let known = ledger.storeIdentifier, known != identifier {
            logger.notice("The library store changed; syncing it as a new library")
            ledger = CloudSyncLedger()
        }
        ledger.storeIdentifier = identifier
    }

    /// Forgets the ledger if many documents it saw vanished while sync
    /// wasn't running, as when an older copy of the store is restored.
    /// Sending those as deletions would remove them from every device.
    private func checkLedgerStillDescribesLibrary() {
        guard let context = container?.mainContext,
              let documents = try? context.fetch(FetchDescriptor<Document>()) else { return }
        if ledger.hasLostTrack(ofLibraryWith: Set(documents.map(\.id))) {
            logger.notice("Many synced documents are missing; syncing the library as new instead of deleting them")
            ledger = CloudSyncLedger(storeIdentifier: ledger.storeIdentifier)
        }
    }

    private func refreshAccountStatus() {
        guard let cloudContainer else { return }
        Task {
            do {
                accountStatus = try await cloudContainer.accountStatus()
            } catch {
                logger.info("Couldn't read the iCloud account status: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Lets iCloud wake the app with changes from other devices. Needs the
    /// Push Notifications capability; without it sync still runs, fetching
    /// when the app comes forward and when a book opens.
    private func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private func saveLedger() {
        do {
            try ledger.save()
        } catch {
            logger.error("Couldn't save the sync ledger: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Local changes

    private func scheduleReconcile() {
        guard engine != nil, !isReconcileScheduled else { return }
        isReconcileScheduled = true
        Task {
            isReconcileScheduled = false
            reconcile()
        }
    }

    /// Queues whatever changed in the library since iCloud last confirmed it.
    private func reconcile() {
        guard let engine, let context = container?.mainContext else { return }
        let documents: [Document]
        do {
            documents = try context.fetch(FetchDescriptor<Document>())
        } catch {
            logger.error("Couldn't read the library to sync: \(error.localizedDescription, privacy: .public)")
            return
        }
        let now = Date.now
        let plan = ledger.reconcile(documents.map { snapshot(of: $0, now: now) }, now: now)
        if !plan.removals.isEmpty || !plan.positionUpdates.isEmpty {
            let byID = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, position) in plan.positionUpdates {
                byID[id]?.applyReadingPosition(position)
            }
            for id in plan.removals {
                if let document = byID[id] { context.delete(document) }
            }
            saveContext(context)
        }
        enqueue(saves: plan.saves, deletes: plan.deletes, on: engine)
        saveLedger()
    }

    private func snapshot(of document: Document, now: Date) -> LocalDocumentSnapshot {
        LocalDocumentSnapshot(
            id: document.id,
            title: document.title,
            position: document.readingPosition,
            dateAdded: document.dateAdded,
            isOpen: isOpen(document.id, now: now)
        )
    }

    private func enqueue(saves: [CloudRecordKey], deletes: [CloudRecordKey], on engine: CKSyncEngine) {
        let now = Date.now
        // Nothing uploads until a full fetch has shown what iCloud has, or
        // while iCloud storage is full.
        let canSave = ledger.hasFetchedEverything && (storageFullUntil.map { $0 <= now } ?? true)
        let sendableSaves = canSave
            ? saves.filter { (heldRecords[$0.recordName] ?? .distantPast) <= now }
            : []
        var pending = Set(engine.state.pendingRecordZoneChanges.compactMap(Self.identity(of:)))
        let changes = sendableSaves.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0.recordID) }
            + deletes.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord($0.recordID) }
        let additions = changes.filter { change in
            guard let identity = Self.identity(of: change) else { return false }
            return pending.insert(identity).inserted
        }
        if !additions.isEmpty {
            engine.state.add(pendingRecordZoneChanges: additions)
        }
    }

    private static func identity(of change: CKSyncEngine.PendingRecordZoneChange) -> String? {
        switch change {
        case .saveRecord(let recordID): "save/\(recordID.recordName)"
        case .deleteRecord(let recordID): "delete/\(recordID.recordName)"
        @unknown default: nil
        }
    }

    /// Holds a record back until `date`, then reconciles so it's sent again.
    private func hold(_ key: CloudRecordKey, until date: Date) {
        heldRecords[key.recordName] = date
        if date < .distantFuture {
            reconcile(after: date)
        }
    }

    private func reconcile(after date: Date) {
        Task {
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow) + 1))
            scheduleReconcile()
        }
    }

    @discardableResult
    private func saveContext(_ context: ModelContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            logger.error("Couldn't save synced changes: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func localDocument(_ id: UUID) -> Document? {
        guard let context = container?.mainContext else { return nil }
        var descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Identical copies

    /// SHA-256 of a document's words, from the ledger or computed once and kept.
    private func contentHash(of document: Document) -> String {
        if let known = ledger.entry(for: document.id)?.contentHash { return known }
        let words = document.wordsBlob.flatMap { $0.isEmpty ? nil : $0 } ?? WordStorage.encode(document.words)
        let hash = ContentFingerprint.of(words)
        ledger.setContentHash(hash, for: document.id)
        return hash
    }

    /// Another document with the same title, word count, and words, that
    /// isn't leaving. Title and word count narrow it down before any words
    /// are read.
    private func identicalCopy(of document: Document, among candidates: some Sequence<Document>) -> Document? {
        candidates
            .filter { candidate in
                candidate.id != document.id
                    && candidate.title == document.title
                    && candidate.wordCount == document.wordCount
                    && ledger.entry(for: candidate.id)?.removal == nil
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first { contentHash(of: $0) == contentHash(of: document) }
    }

    /// After the first full fetch: local copies never uploaded, of books
    /// iCloud already has, fold into those books rather than uploading a
    /// second copy. This is what merges a book imported on two devices
    /// before they synced. Only copies iCloud has never had are removed.
    private func mergeUnsentCopies() {
        guard let context = container?.mainContext,
              let documents = try? context.fetch(FetchDescriptor<Document>()) else { return }
        let inICloud = documents.filter { ledger.isInICloud($0.id) }
        guard !inICloud.isEmpty else { return }
        for document in documents where !ledger.isInICloud(document.id) && ledger.entry(for: document.id)?.removal == nil {
            if let keeper = identicalCopy(of: document, among: inICloud) {
                logger.info("Merging a local copy into the same book from iCloud")
                ledger.markMerged(document.id, into: keeper.id)
            }
        }
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            ledger.engineState = update.stateSerialization
            saveLedger()
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            handleZoneDeletions(changes.deletions)
        case .fetchedRecordZoneChanges(let changes):
            await applyRemoteChanges(
                records: changes.modifications.map(\.record),
                deletions: changes.deletions.map(\.recordID),
                engine: syncEngine
            )
        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                logger.error("Couldn't create the iCloud zone: \(failure.error.localizedDescription, privacy: .public)")
                if failure.error.code == .quotaExceeded { isStorageFull = true }
            }
        case .sentRecordZoneChanges(let sent):
            await handleSentRecords(sent, engine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            activeOperations += 1
        case .didFetchChanges:
            activeOperations = max(0, activeOperations - 1)
        case .didSendChanges:
            activeOperations = max(0, activeOperations - 1)
            BookUpload.removeAllFiles()
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    /// Uploads begin once a full fetch has shown what iCloud already has.
    /// Runs after a successful `fetchChanges()`.
    private func finishFirstFetchIfNeeded() {
        guard !ledger.hasFetchedEverything else { return }
        mergeUnsentCopies()
        ledger.hasFetchedEverything = true
        saveLedger()
        reconcile()
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        let scope = context.options.scope
        // Books before reading states, so a new book lands with or before
        // its position.
        let changes = syncEngine.state.pendingRecordZoneChanges
            .filter { scope.contains($0) }
            .sorted { Self.sendOrder(of: $0) < Self.sendOrder(of: $1) }
        var records: [CKRecord.ID: CKRecord] = [:]
        var batch: [CKSyncEngine.PendingRecordZoneChange] = []
        var assetBytes = 0
        for change in changes {
            switch change {
            case .saveRecord(let recordID):
                guard let built = await record(toSave: recordID, engine: syncEngine) else { continue }
                records[recordID] = built.record
                assetBytes += built.assetBytes
            case .deleteRecord:
                break
            @unknown default:
                continue
            }
            batch.append(change)
            if batch.count >= Self.maxRecordsPerBatch || assetBytes >= Self.maxAssetBytesPerBatch { break }
        }
        guard syncEngine === engine else { return nil }
        let recordsToSave = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { recordsToSave[$0] }
    }

    private static func sendOrder(of change: CKSyncEngine.PendingRecordZoneChange) -> Int {
        switch change {
        case .saveRecord(let recordID): CloudRecordKey(recordID: recordID)?.kind == .book ? 0 : 1
        case .deleteRecord: 2
        @unknown default: 3
        }
    }

    /// The record to send for a queued save, built from the document as it
    /// is now.
    private func record(toSave recordID: CKRecord.ID, engine: CKSyncEngine) async -> (record: CKRecord, assetBytes: Int)? {
        guard let key = CloudRecordKey(recordID: recordID),
              let document = localDocument(key.documentID),
              let entry = ledger.entry(for: key.documentID), entry.removal == nil else {
            // Deleted, or leaving, since the save was queued.
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        switch key.kind {
        case .state:
            let record = entry.stateSystemFields.flatMap(CloudRecordArchive.record(fromSystemFields:))
                ?? CKRecord(recordType: key.recordType, recordID: recordID)
            ledger.stamped(
                key.documentID,
                position: document.readingPosition,
                dateAdded: document.dateAdded,
                now: .now
            ).write(to: record)
            return (record, 0)
        case .book:
            let record = entry.bookSystemFields.flatMap(CloudRecordArchive.record(fromSystemFields:))
                ?? CKRecord(recordType: key.recordType, recordID: recordID)
            record.encryptedValues[CloudSyncSchema.BookField.title] = document.title
            // Already in iCloud: the title is the only part that changes.
            guard entry.bookSystemFields == nil else { return (record, 0) }

            // First upload: the whole book. Read everything before the
            // await; the document may not outlive it.
            let documentID = document.id
            let words = document.wordsBlob.flatMap { $0.isEmpty ? nil : $0 } ?? WordStorage.encode(document.words)
            let complexity = document.complexityBlob
            let chapters = document.chapters
            var fields = BookRecordFields(
                title: document.title,
                fileName: document.fileName,
                dateAdded: document.dateAdded,
                wordCount: document.wordCount,
                chapters: chapters,
                contentHash: ""
            )
            let upload: BookUpload
            do {
                upload = try await Task.detached(priority: .utility) {
                    try BookUpload.prepare(documentID: documentID, words: words, complexity: complexity, chapters: chapters)
                }.value
            } catch {
                logger.error("Couldn't prepare a book for upload: \(error.localizedDescription, privacy: .public)")
                hold(key, until: .now.addingTimeInterval(600))
                return nil
            }
            fields.contentHash = upload.contentHash
            fields.write(to: record)
            if let url = upload.wordsURL {
                record[CloudSyncSchema.BookField.words] = CKAsset(fileURL: url)
            }
            if let url = upload.complexityURL {
                record[CloudSyncSchema.BookField.complexity] = CKAsset(fileURL: url)
            }
            if let url = upload.chaptersURL {
                record[CloudSyncSchema.BookField.chaptersAsset] = CKAsset(fileURL: url)
            }
            ledger.setContentHash(upload.contentHash, for: documentID)
            return (record, upload.byteCount)
        }
    }

    // MARK: - Account and zone

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            scheduleReconcile()
            // Uploads wait for a fetch that succeeds, which can only happen
            // now.
            fetchChanges(unlessFetchedWithin: 0)
        case .signOut, .switchAccounts:
            // The library stays on this device. It's matched against
            // whichever account signs in next, then uploaded to it.
            logger.notice("The iCloud account changed; starting sync over")
            ledger = CloudSyncLedger(storeIdentifier: ledger.storeIdentifier)
            restartEngine()
        @unknown default:
            break
        }
        refreshAccountStatus()
    }

    private func handleZoneDeletions(_ deletions: [CKDatabase.DatabaseChange.Deletion]) {
        for deletion in deletions where deletion.zoneID.zoneName == CloudSyncSchema.zoneName {
            switch deletion.reason {
            case .deleted, .purged:
                turnOffAfterICloudDeletion()
                return
            case .encryptedDataReset:
                logger.notice("Encrypted iCloud data was reset; uploading the library again")
                ledger.forgetServerRecords()
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSyncSchema.zoneID))])
                saveLedger()
                scheduleReconcile()
            @unknown default:
                break
            }
        }
    }

    /// Strobe's data was deleted from iCloud, most likely in iCloud settings.
    /// The library stays on this device and sync turns off, so it isn't
    /// uploaded again until the user turns sync back on.
    private func turnOffAfterICloudDeletion() {
        logger.notice("Strobe's iCloud data was deleted; turning sync off and keeping the library")
        engine = nil
        activeOperations = 0
        ledger = CloudSyncLedger(storeIdentifier: ledger.storeIdentifier)
        saveLedger()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ReaderSettings.Keys.iCloudSyncEnabled)
        defaults.set(true, forKey: ReaderSettings.Keys.iCloudSyncStoppedAfterDeletion)
        isEnabled = false
        stoppedAfterICloudDeletion = true
    }

    // MARK: - Send results

    private func handleSentRecords(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async {
        let now = Date.now
        var touched: [CloudRecordKey] = []
        var retries: [CloudRecordKey] = []
        var conflicts: [CKRecord] = []
        var needsZone = false
        var hitQuota = false

        for record in sent.savedRecords {
            guard let key = CloudRecordKey(recordID: record.recordID) else { continue }
            ledger.confirmSaved(
                key,
                systemFields: CloudRecordArchive.systemFields(of: record),
                title: key.kind == .book ? BookRecordFields.title(in: record) : nil,
                state: key.kind == .state ? StampedReadingPosition(record: record) : nil
            )
            heldRecords[key.recordName] = nil
            touched.append(key)
        }

        for failure in sent.failedRecordSaves {
            guard let key = CloudRecordKey(recordID: failure.record.recordID) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device saved first. Its record is merged in below,
                // then whatever this device has that it doesn't is sent.
                if let serverRecord = failure.error.serverRecord {
                    conflicts.append(serverRecord)
                }
                touched.append(key)
            case .zoneNotFound:
                // The zone is made again, and the record in it: its change
                // tag belonged to the old zone.
                needsZone = true
                ledger.forgetServerRecord(key)
                retries.append(key)
            case .unknownItem:
                // Gone from iCloud while this device still has it: upload it
                // again. Re-uploading can bring back a book deleted elsewhere
                // a moment earlier, but it never loses one.
                ledger.forgetServerRecord(key)
                retries.append(key)
            case .assetFileNotFound, .assetFileModified:
                // An upload file changed mid-send; it's written again.
                retries.append(key)
            case .userDeletedZone:
                turnOffAfterICloudDeletion()
                return
            case .quotaExceeded:
                hitQuota = true
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                // CKSyncEngine retries these itself.
                break
            case .limitExceeded, .invalidArguments, .permissionFailure, .serverRejectedRequest,
                 .incompatibleVersion, .badContainer, .missingEntitlement, .constraintViolation:
                // Sending it again won't help; try again next launch.
                logger.error("iCloud rejected \(key.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
                hold(key, until: .distantFuture)
            default:
                logger.error("Couldn't save \(key.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
                hold(key, until: now.addingTimeInterval(600))
            }
        }

        for recordID in sent.deletedRecordIDs {
            if let key = CloudRecordKey(recordID: recordID) { ledger.confirmDeleted(key) }
        }
        for (recordID, error) in sent.failedRecordDeletes {
            guard let key = CloudRecordKey(recordID: recordID) else { continue }
            switch error.code {
            case .unknownItem, .zoneNotFound:
                // Already gone.
                ledger.confirmDeleted(key)
            default:
                logger.error("Couldn't delete \(key.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if hitQuota {
            // Nothing is saved for a while, rather than re-uploading books
            // on every change while iCloud is full.
            isStorageFull = true
            let retryDate = now.addingTimeInterval(900)
            storageFullUntil = retryDate
            reconcile(after: retryDate)
        } else if !sent.savedRecords.isEmpty {
            isStorageFull = false
            storageFullUntil = nil
        }
        if needsZone {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSyncSchema.zoneID))])
        }
        if !conflicts.isEmpty {
            await applyRemoteChanges(records: conflicts, deletions: [], engine: engine)
        }
        guard engine === self.engine else { return }

        // Send again what changed while a save was in flight or lost a
        // conflict.
        var resend = retries
        for key in touched where needsSend(key) {
            resend.append(key)
        }
        enqueue(saves: resend, deletes: [], on: engine)
        saveLedger()
    }

    /// Whether the document's current state differs from what iCloud has.
    private func needsSend(_ key: CloudRecordKey) -> Bool {
        guard let document = localDocument(key.documentID),
              let entry = ledger.entry(for: key.documentID), entry.removal == nil else { return false }
        switch key.kind {
        case .book:
            return entry.bookSystemFields == nil || entry.syncedTitle != document.title
        case .state:
            return entry.stateSystemFields == nil || entry.syncedState?.position != document.readingPosition
        }
    }

    // MARK: - Remote changes

    /// Merges records fetched from iCloud (or returned by a conflict) into
    /// the store and saves them on the main context.
    private func applyRemoteChanges(records: [CKRecord], deletions: [CKRecord.ID], engine: CKSyncEngine) async {
        guard let context = container?.mainContext else { return }
        let books = records.filter { $0.recordType == CloudSyncSchema.RecordType.book }
        let states = records.filter { $0.recordType == CloudSyncSchema.RecordType.readingState }

        // Words of books new to this device, read off the main actor while
        // CloudKit's downloaded files still exist.
        var contents: [UUID: BookContent] = [:]
        for record in books {
            guard let key = CloudRecordKey(recordID: record.recordID),
                  ledger.entry(for: key.documentID)?.hasLocalDocument != true,
                  let fields = BookRecordFields(record: record) else { continue }
            let wordsURL = (record[CloudSyncSchema.BookField.words] as? CKAsset)?.fileURL
            let complexityURL = (record[CloudSyncSchema.BookField.complexity] as? CKAsset)?.fileURL
            let chaptersURL = (record[CloudSyncSchema.BookField.chaptersAsset] as? CKAsset)?.fileURL
            contents[key.documentID] = await Task.detached(priority: .utility) {
                BookContent.load(wordsURL: wordsURL, complexityURL: complexityURL, chaptersURL: chaptersURL, fields: fields)
            }.value
            // Sync stopped or started over meanwhile (an account change):
            // these records belong to a ledger that's gone.
            guard engine === self.engine else { return }
        }

        let documents: [Document]
        do {
            documents = try context.fetch(FetchDescriptor<Document>())
        } catch {
            logger.error("Couldn't read the library to merge synced changes: \(error.localizedDescription, privacy: .public)")
            refetchEverything()
            return
        }
        let ledgerBefore = ledger
        var byID = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var inserted: [UUID] = []
        let now = Date.now

        for record in books {
            applyBook(record, contents: contents, documents: &byID, inserted: &inserted, context: context)
        }
        for record in states {
            applyState(record, documents: byID, now: now)
        }
        for recordID in deletions {
            guard let key = CloudRecordKey(recordID: recordID) else { continue }
            applyDeletion(of: key, documents: &byID, context: context, now: now)
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                ledger = ledgerBefore
                logger.error("Couldn't save changes from iCloud: \(error.localizedDescription, privacy: .public)")
                refetchEverything()
                return
            }
        }
        // Only now, with the store saved, do new books count as part of the
        // library; a failed save can never read as a local deletion.
        for id in inserted {
            ledger.markLocal(id)
        }
        saveLedger()
    }

    private func applyBook(
        _ record: CKRecord,
        contents: [UUID: BookContent],
        documents: inout [UUID: Document],
        inserted: inout [UUID],
        context: ModelContext
    ) {
        guard let key = CloudRecordKey(recordID: record.recordID), key.kind == .book,
              let fields = BookRecordFields(record: record) else { return }
        let id = key.documentID
        // Deleted here, with the deletion on its way.
        guard !ledger.isPendingDelete(id) else { return }
        let systemFields = CloudRecordArchive.systemFields(of: record)

        if let document = documents[id] {
            if let title = ledger.receiveBook(fields, systemFields: systemFields, for: id, localTitle: document.title) {
                document.title = title
            }
            return
        }
        guard fields.format <= CloudSyncSchema.bookFormat else {
            logger.notice("Skipping a book saved by a newer version of Strobe")
            return
        }
        guard let content = contents[id] else {
            logger.error("A book arrived without readable words; skipping it")
            return
        }

        let document = Document(
            title: fields.title,
            fileName: fields.fileName,
            bookmarkData: Data(),
            wordsBlob: content.words,
            wordCount: fields.wordCount,
            complexityBlob: content.complexity,
            chapters: content.chapters ?? fields.chapters,
            wordsPerMinute: UserDefaults.standard.object(forKey: ReaderSettings.Keys.defaultWPM) as? Int
                ?? ReaderSettings.Defaults.defaultWPM
        )
        document.id = id
        document.dateAdded = fields.dateAdded
        _ = ledger.receiveBook(fields, systemFields: systemFields, for: id, localTitle: nil)
        // Its reading state may have arrived first.
        if let waiting = ledger.entry(for: id)?.syncedState {
            document.applyReadingPosition(waiting.position)
        }
        context.insert(document)
        documents[id] = document
        inserted.append(id)

        // Copies of this book here that were never uploaded (it was imported
        // on this device too) fold into it instead of uploading again. During
        // the first fetch a copy's own record may still be on its way, so
        // those wait for `mergeUnsentCopies`.
        guard ledger.hasFetchedEverything else { return }
        let unsentCopies = documents.values.filter { copy in
            copy.id != id
                && copy.title == fields.title
                && copy.wordCount == fields.wordCount
                && !ledger.isInICloud(copy.id)
                && ledger.entry(for: copy.id)?.removal == nil
                && contentHash(of: copy) == fields.contentHash
        }
        for copy in unsentCopies {
            logger.info("Merging a local copy into the same book from iCloud")
            ledger.markMerged(copy.id, into: id)
        }
    }

    private func applyState(_ record: CKRecord, documents: [UUID: Document], now: Date) {
        guard let key = CloudRecordKey(recordID: record.recordID), key.kind == .state,
              let remote = StampedReadingPosition(record: record) else { return }
        let id = key.documentID
        guard !ledger.isPendingDelete(id) else { return }
        let document = documents[id]
        let position = ledger.receiveState(
            remote,
            systemFields: CloudRecordArchive.systemFields(of: record),
            for: id,
            local: document.map { ($0.readingPosition, $0.dateAdded) },
            now: now
        )
        if let document, let position {
            document.applyReadingPosition(position)
        }
    }

    /// A book deleted on another device leaves this one too, or once it
    /// closes if it's open. Reading not yet sent goes to an identical copy
    /// here, if there is one: the other device may have deleted this copy
    /// in favor of that one.
    private func applyDeletion(of key: CloudRecordKey, documents: inout [UUID: Document], context: ModelContext, now: Date) {
        guard key.kind == .book, let document = documents[key.documentID] else {
            _ = ledger.receiveDeletion(of: key, isOpen: false)
            return
        }
        let keeper = ledger.entry(for: document.id)?.hasLocalDocument == true
            ? identicalCopy(of: document, among: documents.values)
            : nil
        let open = isOpen(document.id, now: now)
        if let keeper, !open,
           let position = ledger.mergeReading(from: snapshot(of: document, now: now), into: snapshot(of: keeper, now: now), now: now) {
            keeper.applyReadingPosition(position)
        }
        if ledger.receiveDeletion(of: key, isOpen: open, foldInto: keeper?.id) {
            context.delete(document)
            documents[key.documentID] = nil
        }
    }

    /// Starts over from a full fetch after changes from iCloud couldn't be
    /// saved, so none are skipped. Once per launch; after that sync stops
    /// until the next launch rather than refetching in a loop.
    private func refetchEverything() {
        guard !didRefetchAfterSaveFailure else {
            logger.error("Stopping sync until the next launch after repeated save failures")
            engine = nil
            activeOperations = 0
            return
        }
        didRefetchAfterSaveFailure = true
        ledger.engineState = nil
        restartEngine()
    }
}

// MARK: - Documents

extension Document {
    /// The parts of the document that iCloud sync carries in its reading state.
    var readingPosition: ReadingPosition {
        ReadingPosition(
            currentWordIndex: currentWordIndex,
            furthestWordIndex: furthestWordIndex,
            wordsPerMinute: wordsPerMinute,
            lastReadDate: lastReadDate
        )
    }

    /// Writes a synced position, kept inside this document's words. Only
    /// values that differ are set, so an unchanged document stays clean.
    func applyReadingPosition(_ position: ReadingPosition) {
        let position = position.clamped(toWordCount: wordCount)
        if currentWordIndex != position.currentWordIndex { currentWordIndex = position.currentWordIndex }
        if furthestWordIndex != position.furthestWordIndex { furthestWordIndex = position.furthestWordIndex }
        if wordsPerMinute != position.wordsPerMinute { wordsPerMinute = position.wordsPerMinute }
        if lastReadDate != position.lastReadDate { lastReadDate = position.lastReadDate }
    }
}

// MARK: - Views

extension View {
    /// Runs iCloud sync for the library: fetches when the app comes forward
    /// and sends before it goes to the background.
    func libraryCloudSync(_ container: ModelContainer) -> some View {
        modifier(LibraryCloudSyncModifier(container: container))
    }

    /// Keeps a document deleted on another device while this view shows it
    /// until the view closes.
    func marksDocumentOpen(_ id: UUID) -> some View {
        modifier(OpenDocumentMarker(id: id))
    }
}

private struct LibraryCloudSyncModifier: ViewModifier {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                LibrarySync.shared.start(container: container)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    LibrarySync.shared.sceneDidBecomeActive()
                case .background:
                    LibrarySync.shared.sceneDidEnterBackground()
                default:
                    break
                }
            }
    }
}

private struct OpenDocumentMarker: ViewModifier {
    let id: UUID

    func body(content: Content) -> some View {
        content
            .onAppear { LibrarySync.shared.documentDidOpen(id) }
            .onDisappear { LibrarySync.shared.documentDidClose(id) }
    }
}

#if os(iOS)
/// Keeps the app running for a moment after it leaves the screen, so a
/// send can finish.
private final class BackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // UIKit calls this on the main thread.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
