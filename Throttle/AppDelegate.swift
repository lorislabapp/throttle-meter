import AppKit
import GRDB
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private let database: DatabasePool
    private let coordinator: DataLayerCoordinator
    private let savingsIngester: SavingsIngester
    private let logger = AppLogger.app

    override init() {
        do {
            self.database = try Self.openDatabaseSync()
            self.appState = AppState(database: database)
            self.coordinator = DataLayerCoordinator(database: database)
            self.savingsIngester = SavingsIngester(database: database)
            super.init()
            self.coordinator.onUsageChanged = { [weak self] in
                self?.appState.refresh()
            }
        } catch {
            // Fail-fast: if we can't open the DB, the app is non-functional.
            fatalError("Failed to initialize database: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isRunningTests {
            guard Self.acquireSingletonLock() else {
                logger.notice("Another Throttle Meter instance is already running. Quitting.")
                NSApp.terminate(nil)
                return
            }
        }

        logger.notice("Throttle Meter launched (\(Bundle.main.shortVersion, privacy: .public))")
        AppLogger.appendToFile("Throttle Meter launched (\(Bundle.main.shortVersion))")

        savingsIngester.onIngest = { [weak self] in
            self?.appState.refresh()
        }
        savingsIngester.start()

        Task { @MainActor in
            await coordinator.start()
            appState.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        savingsIngester.stop()
        logger.notice("Throttle Meter quitting")
    }

    private static func openDatabaseSync() throws -> DatabasePool {
        let url = try DatabaseManager.databaseURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try Migrations.register(on: pool)
        return pool
    }

    private static func acquireSingletonLock() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lorislab.throttle.meter"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return running.count == 1
    }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
