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

    private let bootstrapResult = Self.bootstrapModelContainer()

    var body: some Scene {
        WindowGroup {
            if let container = bootstrapResult.container {
                ContentView()
                    .modelContainer(container)
                    .preferredColorScheme(.dark)
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

        let summary = diagnostics.joined(separator: "\n")
        UserDefaults.standard.set(summary, forKey: diagnosticsKey)
        return BootstrapResult(container: nil, diagnostics: summary)
    }

    private static func makePersistentContainer(schema: Schema) throws -> ModelContainer {
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
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

                Text("SwiftData failed to initialize. The app is blocked to prevent data loss.")
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
