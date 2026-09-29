import SwiftUI

/// iCloud sync on or off, and what it's doing.
struct SyncSettingsSection: View {
    @AppStorage(ReaderSettings.Keys.iCloudSyncEnabled) private var iCloudSyncEnabled = ReaderSettings.Defaults.iCloudSyncEnabled
    private let sync = LibrarySync.shared

    var body: some View {
        Section {
            Toggle(isOn: $iCloudSyncEnabled) {
                Text("iCloud Sync")
                Text("Your library and reading positions on all your devices")
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(footer)
        }
        .onChange(of: iCloudSyncEnabled) {
            sync.updateEnabled()
        }
    }

    private var footer: String {
        switch sync.status {
        case .off:
            "Books and reading positions stay on this device."
        case .offAfterICloudDeletion:
            "Strobe's data was deleted from iCloud, so sync turned off. Your library is still on this device. Turn sync on to upload it again."
        case .unavailable:
            "iCloud sync isn't available in this build."
        case .signedOut:
            signedOutFooter
        case .restricted:
            "iCloud is restricted on this device."
        case .temporarilyUnavailable:
            "iCloud isn't available right now. Changes will sync when it's back."
        case .storageFull:
            "Your iCloud storage is full, so new changes aren't syncing."
        case .syncing:
            "Syncing…"
        case .upToDate:
            "Up to date."
        }
    }

    private var signedOutFooter: String {
        #if os(macOS)
        "Sign in to iCloud in System Settings to sync your library."
        #else
        "Sign in to iCloud in the Settings app to sync your library."
        #endif
    }
}
