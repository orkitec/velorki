import CloudKit
import os
import Flutter
import Foundation

/// iCloud sync of the library and of a few settings, for
/// `lib/features/sync/data/cloud_sync_bridge.dart`.
///
/// Routes and rides go through CKSyncEngine (iOS 17 and later) into one
/// zone of the rider's private database; the rows themselves live in Dart's
/// database, so every record is asked of Dart when it is sent and every
/// change fetched is handed to Dart, which answers once it is written.
/// Settings go through the iCloud key-value store. Nothing runs until Dart
/// calls `start`, which it only does with the switch on.
final class CloudSync: NSObject, FlutterStreamHandler, @unchecked Sendable {
  static let channelName = "velorki/cloud_sync"
  static let statusChannelName = "velorki/cloud_sync/status"
  static let containerIdentifier = "iCloud.com.orkitec.velorki"

  /// When a sync last went through, kept across launches.
  private static let lastSyncedKey = "velorki.cloudSync.lastSyncedAt"

  private let channel: FlutterMethodChannel
  private let statusChannel: FlutterEventChannel
  private var sink: FlutterEventSink?

  /// The CKSyncEngine side, an `Any` because the type exists only on iOS 17.
  private var engine: AnyObject?
  private var running = false

  private var account = "unknown"
  private var syncing = false
  private var error: String?
  private var lastSyncedAt: Int64? = {
    let value = UserDefaults.standard.double(forKey: CloudSync.lastSyncedKey)
    return value > 0 ? Int64(value) : nil
  }()

  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: CloudSync.channelName, binaryMessenger: messenger)
    statusChannel = FlutterEventChannel(
      name: CloudSync.statusChannelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    statusChannel.setStreamHandler(self)
  }

  // MARK: Dart → native

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isSupported":
      if #available(iOS 17.0, *) {
        result(true)
      } else {
        result(false)
      }
    case "start":
      start()
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "enqueue":
      if #available(iOS 17.0, *), let engine = engine as? CloudSyncEngine {
        engine.enqueue(
          saves: args["saves"] as? [String] ?? [],
          deletes: args["deletes"] as? [String] ?? [])
      }
      result(nil)
    case "fetchNow":
      if #available(iOS 17.0, *), let engine = engine as? CloudSyncEngine {
        // Answers when the fetch is done, so a pull to refresh spins as
        // long as it runs.
        Task {
          await engine.fetchNow()
          result(nil)
        }
      } else {
        result(nil)
      }
    case "readSettings":
      result(readSettings(args["keys"] as? [String] ?? []))
    case "writeSettings":
      writeSettings(args["values"] as? [String: Any] ?? [:])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start() {
    guard !running else { return }
    running = true
    if #available(iOS 17.0, *) {
      engine = CloudSyncEngine(sync: self)
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: .CKAccountChanged, object: nil, queue: .main
      ) { [weak self] _ in self?.checkAccount() })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: NSUbiquitousKeyValueStore.default, queue: .main
      ) { [weak self] note in self?.settingsChangedExternally(note) })
    NSUbiquitousKeyValueStore.default.synchronize()
    checkAccount()
  }

  private func stop() {
    guard running else { return }
    running = false
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
    if #available(iOS 17.0, *), let engine = engine as? CloudSyncEngine {
      engine.shutDown()
    }
    engine = nil
    syncing = false
    sendStatus()
  }

  private func checkAccount() {
    CKContainer(identifier: CloudSync.containerIdentifier).accountStatus {
      [weak self] status, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        switch status {
        case .available: self.account = "available"
        case .noAccount: self.account = "noAccount"
        case .restricted: self.account = "restricted"
        case .temporarilyUnavailable: self.account = "temporarilyUnavailable"
        default: self.account = "unknown"
        }
        self.sendStatus()
      }
    }
  }

  // MARK: Settings

  private func readSettings(_ keys: [String]) -> [String: Any] {
    let store = NSUbiquitousKeyValueStore.default
    var values: [String: Any] = [:]
    for key in keys {
      if let value = store.object(forKey: key) { values[key] = value }
    }
    return values
  }

  private func writeSettings(_ values: [String: Any]) {
    let store = NSUbiquitousKeyValueStore.default
    for (key, value) in values {
      let current = store.object(forKey: key) as? NSObject
      if value is NSNull {
        if current != nil { store.removeObject(forKey: key) }
      } else if let value = value as? NSObject, current != value {
        store.set(value, forKey: key)
      }
    }
    store.synchronize()
  }

  private func settingsChangedExternally(_ note: Notification) {
    guard running,
      let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
    else { return }
    let store = NSUbiquitousKeyValueStore.default
    var values: [String: Any] = [:]
    for key in keys {
      values[key] = store.object(forKey: key) ?? NSNull()
    }
    channel.invokeMethod("settingsChanged", arguments: ["values": values])
  }

  // MARK: Status

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    sendStatus()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func sendStatus() {
    var status: [String: Any] = ["account": account, "syncing": syncing]
    if let lastSyncedAt { status["lastSyncedAt"] = lastSyncedAt }
    if let error { status["error"] = error }
    sink?(status)
  }

  /// Called by the engine, from any thread.
  func update(syncing: Bool? = nil, synced: Bool = false, error: String?? = nil) {
    DispatchQueue.main.async {
      if let syncing { self.syncing = syncing }
      if synced {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        self.lastSyncedAt = now
        UserDefaults.standard.set(Double(now), forKey: CloudSync.lastSyncedKey)
      }
      if let error { self.error = error }
      self.sendStatus()
    }
  }

  func accountChecked() {
    DispatchQueue.main.async { self.checkAccount() }
  }

  // MARK: Native → Dart

  /// Calls [method] in Dart and waits for its answer; nil when nothing in
  /// Dart answered.
  func callDart(_ method: String, _ arguments: Any?) async -> Any? {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        self.channel.invokeMethod(method, arguments: arguments) { answer in
          if answer is FlutterError || (answer as? NSObject) === FlutterMethodNotImplemented {
            continuation.resume(returning: nil)
          } else {
            continuation.resume(returning: answer)
          }
        }
      }
    }
  }
}

/// One line in the device log (`idevicesyslog -p Runner | grep velorki`):
/// record names and outcomes only, never what a record holds.
private let syncLogger = Logger(subsystem: "com.orkitec.velorki", category: "sync")

/// Record names and outcomes only, never a route's name or content.
private func syncLog(_ message: String) {
  syncLogger.notice("velorki: iCloud \(message, privacy: .public)")
}

/// CKSyncEngine over the private database's `Library` zone.
@available(iOS 17.0, *)
final class CloudSyncEngine: CKSyncEngineDelegate, @unchecked Sendable {
  private static let zoneID = CKRecordZone.ID(
    zoneName: "Library", ownerName: CKCurrentUserDefaultName)
  private static let recordTypes: Set<String> = ["Route", "Ride"]

  /// How many records are asked of Dart for one batch: each comes with its
  /// track as a file, so a batch stays well within what one request takes.
  private static let batchSize = 25

  private weak var sync: CloudSync?
  private var engine: CKSyncEngine?
  private let database: CKDatabase
  private let stateURL: URL
  private let incomingDir: URL
  private let lock = NSLock()
  private var stopped = false

  /// What went wrong in the fetch or send under way; nil while all goes
  /// through, so its end counts as synced.
  private var roundError: String?

  /// iCloud was full on the last save; stays said until a save goes
  /// through, whatever fetches do meanwhile.
  private var quotaFull = false

  /// The body file sent with each record still on its way, deleted once
  /// the save is done.
  private var outgoingFiles: [String: URL] = [:]

  init(sync: CloudSync) {
    self.sync = sync
    let fm = FileManager.default
    let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("cloud_sync", isDirectory: true)
    try? fm.createDirectory(at: support, withIntermediateDirectories: true)
    stateURL = support.appendingPathComponent("engine_state.json")
    incomingDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("cloud_sync_in", isDirectory: true)
    try? fm.createDirectory(at: incomingDir, withIntermediateDirectories: true)

    let database = CKContainer(identifier: CloudSync.containerIdentifier).privateCloudDatabase
    self.database = database
    let state = loadState()
    let configuration = CKSyncEngine.Configuration(
      database: database, stateSerialization: state, delegate: self)
    let engine = CKSyncEngine(configuration)
    self.engine = engine
    // Record names only in the device log, never what a record holds.
    syncLog(
      "engine started, state \(state == nil ? "new" : "loaded"), "
        + "pending \(Self.names(engine.state.pendingRecordZoneChanges))")
    if state == nil {
      // The first start on this device: the zone may not be there yet.
      engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
    }
  }

  func shutDown() {
    lock.withLock { stopped = true }
    let engine = self.engine
    self.engine = nil
    Task { await engine?.cancelOperations() }
  }

  private var isStopped: Bool { lock.withLock { stopped } }

  func enqueue(saves: [String], deletes: [String]) {
    guard let engine else { return }
    let pending = Set(engine.state.pendingRecordZoneChanges)
    var changes: [CKSyncEngine.PendingRecordZoneChange] = []
    for name in saves {
      let change = CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(name))
      if !pending.contains(change) { changes.append(change) }
    }
    for name in deletes {
      let id = recordID(name)
      let save = CKSyncEngine.PendingRecordZoneChange.saveRecord(id)
      if pending.contains(save) { engine.state.remove(pendingRecordZoneChanges: [save]) }
      let change = CKSyncEngine.PendingRecordZoneChange.deleteRecord(id)
      if !pending.contains(change) { changes.append(change) }
    }
    if !changes.isEmpty { engine.state.add(pendingRecordZoneChanges: changes) }
    syncLog(
      "enqueue saves \(saves) deletes \(deletes), "
        + "added \(Self.names(changes))")
    if saves.isEmpty && deletes.isEmpty { return }
    // Sent now rather than whenever the engine's own schedule gets to it,
    // which can be minutes.
    Task {
      do {
        try await engine.sendChanges()
      } catch {
        syncLog("send failed: \(error)")
      }
    }
  }

  /// Asks the server for this zone's changes. A plain fetchChanges() trusts
  /// the database subscription's pushes and, without one, asks nothing; the
  /// zone named here is always asked.
  func fetchNow() async {
    guard let engine else { return }
    do {
      try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
      syncLog("fetch done")
    } catch {
      syncLog("fetch failed: \(error)")
      if let error = error as? CKError {
        self.sync?.update(error: .some(Self.errorKind(error)))
      }
    }
  }

  /// Keeps the first error of a round; a full iCloud outranks the rest.
  private func setRoundError(_ kind: String) {
    lock.withLock {
      if roundError == nil || kind == "quotaExceeded" { roundError = kind }
    }
  }

  /// The record names of [changes], with what is to happen to each.
  private static func names(_ changes: [CKSyncEngine.PendingRecordZoneChange]) -> [String] {
    changes.map { change in
      switch change {
      case .saveRecord(let id): return "save:\(id.recordName)"
      case .deleteRecord(let id): return "delete:\(id.recordName)"
      @unknown default: return "?"
      }
    }
  }

  private func recordID(_ name: String) -> CKRecord.ID {
    CKRecord.ID(recordName: name, zoneID: Self.zoneID)
  }

  // MARK: State

  private func loadState() -> CKSyncEngine.State.Serialization? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
  }

  private func saveState(_ state: CKSyncEngine.State.Serialization) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: stateURL, options: .atomic)
  }

  // MARK: CKSyncEngineDelegate

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard !isStopped, let sync else { return }
    switch event {
    case .stateUpdate(let update):
      saveState(update.stateSerialization)

    case .accountChange(let change):
      sync.accountChecked()
      let name: String
      switch change.changeType {
      case .signIn: name = "signIn"
      case .signOut: name = "signOut"
      case .switchAccounts: name = "switchAccounts"
      @unknown default: return
      }
      if name != "signOut" {
        // A new account may have no zone yet.
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
      }
      _ = await sync.callDart("accountChanged", ["change": name])

    case .fetchedDatabaseChanges(let changes):
      for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
        let reason: String
        switch deletion.reason {
        case .purged: reason = "purged"
        case .encryptedDataReset: reason = "encryptedDataReset"
        default: reason = "deleted"
        }
        if reason != "purged" {
          syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        _ = await sync.callDart("zoneDeleted", ["reason": reason])
      }

    case .fetchedRecordZoneChanges(let changes):
      let modifications = changes.modifications
        .map(\.record)
        .filter { $0.recordID.zoneID == Self.zoneID && Self.recordTypes.contains($0.recordType) }
        .map(payload(of:))
      let deletions = changes.deletions
        .filter { $0.recordID.zoneID == Self.zoneID }
        .map(\.recordID.recordName)
      syncLog(
        "fetched modified \(modifications.compactMap { $0["name"] as? String }) "
          + "deleted \(deletions)")
      if modifications.isEmpty && deletions.isEmpty { return }
      _ = await sync.callDart(
        "remoteChanges", ["modifications": modifications, "deletions": deletions])

    case .sentRecordZoneChanges(let sent):
      await handleSent(sent, syncEngine: syncEngine, sync: sync)

    case .sentDatabaseChanges(let sent):
      for failure in sent.failedZoneSaves {
        syncLog("zone save failed: \(failure.error)")
      }

    case .didFetchChanges:
      syncLog("fetch done")
      finishRound(sync)

    case .didSendChanges:
      syncLog(
        "send done, pending "
          + "\(Self.names(syncEngine.state.pendingRecordZoneChanges))")
      finishRound(sync)

    case .willFetchChanges, .willSendChanges:
      lock.withLock { roundError = nil }
      sync.update(syncing: true)

    case .didFetchRecordZoneChanges(let done):
      if let error = done.error { setRoundError(Self.errorKind(error)) }

    default:
      break
    }
  }

  /// The end of a fetch or a send: synced unless something went wrong.
  private func finishRound(_ sync: CloudSync) {
    let (error, full) = lock.withLock { () -> (String?, Bool) in
      defer { roundError = nil }
      return (roundError, quotaFull)
    }
    sync.update(
      syncing: false, synced: error == nil,
      error: .some(error ?? (full ? "quotaExceeded" : nil)))
  }

  /// [server] with its body file: the copy a refused save brings has its
  /// asset without the file, and without it Dart cannot read the record
  /// (nor tell whether the server's change is the newer one), so the
  /// record is fetched whole.
  private func completeRecord(_ server: CKRecord) async -> CKRecord {
    if let url = (server["body"] as? CKAsset)?.fileURL,
      FileManager.default.fileExists(atPath: url.path)
    {
      return server
    }
    do {
      return try await database.record(for: server.recordID)
    } catch {
      syncLog(
        "could not fetch \(server.recordID.recordName) whole: \(error)")
      return server
    }
  }

  private func handleSent(
    _ sent: CKSyncEngine.Event.SentRecordZoneChanges,
    syncEngine: CKSyncEngine,
    sync: CloudSync
  ) async {
    var saved: [String: FlutterStandardTypedData] = [:]
    for record in sent.savedRecords {
      saved[record.recordID.recordName] = FlutterStandardTypedData(
        bytes: Self.systemFields(of: record))
    }
    var failedSaves: [[String: Any]] = []
    var quotaExceeded = false
    var otherFailed = false
    var zoneMissing: [CKRecord.ID] = []
    for failure in sent.failedRecordSaves {
      let name = failure.record.recordID.recordName
      var entry: [String: Any] = ["name": name]
      switch failure.error.code {
      case .serverRecordChanged:
        entry["failure"] = "conflict"
        if let server = failure.error.serverRecord {
          entry["serverRecord"] = payload(of: await completeRecord(server))
        }
      case .zoneNotFound, .userDeletedZone:
        // Made again, and the save with it, without asking Dart.
        zoneMissing.append(failure.record.recordID)
        continue
      case .unknownItem:
        entry["failure"] = "unknownItem"
      case .quotaExceeded:
        entry["failure"] = "quotaExceeded"
        quotaExceeded = true
      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
        .requestRateLimited, .notAuthenticated, .operationCancelled,
        .batchRequestFailed, .internalError, .accountTemporarilyUnavailable:
        entry["failure"] = "retrying"
      default:
        syncLog("save of \(name) failed: \(failure.error.code.rawValue)")
        entry["failure"] = "other"
        // Not tried again until the next launch or return to the app: not
        // synced, whatever else went through.
        otherFailed = true
      }
      failedSaves.append(entry)
    }
    syncLog(
      "sent saved \(sent.savedRecords.map(\.recordID.recordName)) "
        + "failed \(failedSaves.map { "\($0["name"] ?? "?"):\($0["failure"] ?? "?")" }) "
        + "zoneMissing \(zoneMissing.map(\.recordName)) "
        + "deleted \(sent.deletedRecordIDs.map(\.recordName)) "
        + "failedDeletes \(sent.failedRecordDeletes.keys.map(\.recordName))")
    if !zoneMissing.isEmpty {
      syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
      syncEngine.state.add(pendingRecordZoneChanges: zoneMissing.map { .saveRecord($0) })
    }
    // The body files of the records done with.
    let done = sent.savedRecords.map(\.recordID.recordName)
      + sent.failedRecordSaves.map(\.record.recordID.recordName)
    let files: [URL] = lock.withLock {
      done.compactMap { outgoingFiles.removeValue(forKey: $0) }
    }
    for file in files { try? FileManager.default.removeItem(at: file) }

    lock.withLock {
      if quotaExceeded {
        quotaFull = true
      } else if !sent.savedRecords.isEmpty {
        quotaFull = false
      }
    }
    if quotaExceeded {
      setRoundError("quotaExceeded")
    } else if failedSaves.contains(where: { $0["failure"] as? String == "retrying" }) {
      setRoundError("network")
    } else if otherFailed {
      setRoundError("other")
    }
    _ = await sync.callDart(
      "sentChanges",
      [
        "saved": saved,
        "failedSaves": failedSaves,
        "deleted": sent.deletedRecordIDs.map(\.recordName),
        "failedDeletes": Array(sent.failedRecordDeletes.keys.map(\.recordName)),
      ])
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard !isStopped, let sync else { return nil }
    let scope = context.options.scope
    let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
    var saves: [CKRecord.ID] = []
    var changes: [CKSyncEngine.PendingRecordZoneChange] = []
    for change in pending {
      switch change {
      case .saveRecord(let id):
        if saves.count < Self.batchSize {
          saves.append(id)
          changes.append(change)
        }
      case .deleteRecord:
        changes.append(change)
      @unknown default:
        break
      }
    }
    if changes.isEmpty { return nil }

    var records: [String: CKRecord] = [:]
    if !saves.isEmpty {
      guard
        let answer = await sync.callDart(
          "recordsToSave", ["names": saves.map(\.recordName)]) as? [[String: Any]]
      else {
        // Nothing in Dart answered: leave everything pending.
        return nil
      }
      for entry in answer {
        if let record = makeRecord(entry) { records[record.recordID.recordName] = record }
      }
      // What Dart left out is not to be saved (deleted since, or a route
      // that stays on the phone).
      let dropped = saves.filter { records[$0.recordName] == nil }
      syncLog(
        "batch saves \(records.keys.sorted()) dropped \(dropped.map(\.recordName)) "
          + "deletes \(Self.names(changes.filter { if case .deleteRecord = $0 { return true }; return false }))")
      if !dropped.isEmpty {
        syncEngine.state.remove(pendingRecordZoneChanges: dropped.map { .saveRecord($0) })
      }
    }
    let batch = changes.filter {
      if case .saveRecord(let id) = $0 { return records[id.recordName] != nil }
      return true
    }
    if batch.isEmpty {
      return await nextRecordZoneChangeBatch(context, syncEngine: syncEngine)
    }
    let provided = records
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { id in
      provided[id.recordName]
    }
  }

  // MARK: Records

  private func makeRecord(_ entry: [String: Any]) -> CKRecord? {
    guard let name = entry["name"] as? String, let type = entry["type"] as? String else {
      return nil
    }
    let id = recordID(name)
    var record = CKRecord(recordType: type, recordID: id)
    if let data = (entry["systemFields"] as? FlutterStandardTypedData)?.data,
      let known = Self.record(fromSystemFields: data), known.recordID == id
    {
      record = known
    }
    for (key, value) in entry["fields"] as? [String: Any] ?? [:] {
      switch value {
      case is NSNull: record[key] = nil
      case let string as String: record[key] = string as CKRecordValue
      case let number as NSNumber: record[key] = number
      default: continue
      }
    }
    if let path = entry["asset"] as? String {
      let url = URL(fileURLWithPath: path)
      record["body"] = CKAsset(fileURL: url)
      lock.withLock { outgoingFiles[name] = url }
    }
    return record
  }

  /// [record] as Dart reads it: its fields, its body copied out of
  /// CloudKit's cache (which may drop it any time) and its system fields.
  private func payload(of record: CKRecord) -> [String: Any] {
    var fields: [String: Any] = [:]
    for key in record.allKeys() {
      switch record[key] {
      case let string as String: fields[key] = string
      case let number as NSNumber: fields[key] = number
      case let date as Date: fields[key] = Int64(date.timeIntervalSince1970 * 1000)
      default: continue
      }
    }
    var entry: [String: Any] = [
      "name": record.recordID.recordName,
      "type": record.recordType,
      "fields": fields,
      "systemFields": FlutterStandardTypedData(bytes: Self.systemFields(of: record)),
    ]
    if let asset = record["body"] as? CKAsset, let source = asset.fileURL {
      let copy = incomingDir.appendingPathComponent(UUID().uuidString + ".json.gz")
      do {
        try FileManager.default.copyItem(at: source, to: copy)
        entry["asset"] = copy.path
      } catch {
        syncLog("could not copy the body of \(record.recordID.recordName): \(error)")
      }
    }
    return entry
  }

  private static func systemFields(of record: CKRecord) -> Data {
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder)
    coder.finishEncoding()
    return coder.encodedData
  }

  private static func record(fromSystemFields data: Data) -> CKRecord? {
    guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
    coder.requiresSecureCoding = true
    defer { coder.finishDecoding() }
    return CKRecord(coder: coder)
  }

  private static func errorKind(_ error: CKError) -> String {
    switch error.code {
    case .quotaExceeded: return "quotaExceeded"
    case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited,
      .zoneBusy:
      return "network"
    default: return "other"
    }
  }
}
