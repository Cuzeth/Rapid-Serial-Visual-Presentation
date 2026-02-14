//
//  StrobeApp.swift
//  Strobe
//
//  Created by CZTH on 2/13/26.
//

import SwiftUI
import SwiftData
import os

@main
struct StrobeApp: App {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe",
        category: "ModelContainer"
    )
    private static let diagnosticsKey = "last_model_container_bootstrap_diagnostics"

    @AppStorage("appearance") private var appearance: Int = 0

    private let bootstrapResult = Self.bootstrapModelContainer()

    private var colorScheme: ColorScheme? {
        switch appearance {
        case 1: .light
        case 2: .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = bootstrapResult.container {
                ContentView()
                    .modelContainer(container)
                    .preferredColorScheme(colorScheme)
            } else {
                StartupFailureView(diagnostics: bootstrapResult.diagnostics)
            }
        }
    }

    private struct BootstrapResult {
        let container: ModelContainer?
        let diagnostics: String
    }

    private static func bootstrapModelContainer() -> BootstrapResult {
        let schema = Schema([Document.self])
        var diagnostics: [String] = []

        func append(_ message: String) {
            diagnostics.append(message)
            logger.error("\(message, privacy: .public)")
        }

        do {
            let container = try makePersistentContainer(schema: schema)
            return BootstrapResult(container: container, diagnostics: "")
        } catch {
            append("Persistent init failed: \(describe(error: error))")
        }

        do {
            try resetDefaultSwiftDataStore()
            logger.notice("Reset default SwiftData store after init failure; retrying persistent container.")
            let container = try makePersistentContainer(schema: schema)
            return BootstrapResult(container: container, diagnostics: "")
        } catch {
            append("Persistent retry after reset failed: \(describe(error: error))")
        }

        do {
            logger.notice("Trying in-memory ModelContainer fallback.")
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            return BootstrapResult(container: container, diagnostics: diagnostics.joined(separator: "\n"))
        } catch {
            append("In-memory fallback failed: \(describe(error: error))")
            let summary = diagnostics.joined(separator: "\n")
            UserDefaults.standard.set(summary, forKey: diagnosticsKey)
            return BootstrapResult(container: nil, diagnostics: summary)
        }
    }

    private static func makePersistentContainer(schema: Schema) throws -> ModelContainer {
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    private static func resetDefaultSwiftDataStore() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let storeURL = appSupportURL.appendingPathComponent("default.store", isDirectory: false)
        let relatedFiles = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]

        for fileURL in relatedFiles where fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    private static func describe(error: Error) -> String {
        let nsError = error as NSError
        var components: [String] = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]

        if !nsError.userInfo.isEmpty {
            components.append("userInfo=\(nsError.userInfo)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            components.append("underlying=\(underlying.domain)(\(underlying.code)): \(underlying.localizedDescription)")
        }

        return components.joined(separator: " | ")
    }
}

private struct StartupFailureView: View {
    let diagnostics: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Startup Error")
                    .font(.title2.weight(.semibold))

                Text("SwiftData failed to initialize, including in-memory fallback.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("Please share the diagnostics below.")
                    .font(.body)

                Text(diagnostics.isEmpty ? "No diagnostics available." : diagnostics)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
        }
    }
}
