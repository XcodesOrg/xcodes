import Path
import XcodesKit

/// Migrates any application support files from Xcodes < v0.4 if application support files from >= v0.4 don't exist
public func migrateApplicationSupportFiles() {
    let migrationService = ApplicationSupportMigrationService(
        fileExists: { path in Current.files.fileExists(atPath: path) },
        moveItem: { source, destination in
            try Current.files.moveItem(at: source, to: destination)
        },
        removeItem: { url in try Current.files.removeItem(at: url) }
    )

    switch migrationService.migrate(
        oldSupportPath: Path.oldXcodesApplicationSupport,
        newSupportPath: Path.xcodesApplicationSupport
    ) {
    case .removedOldSupportFiles:
        Current.logging.log("Removing old support files...")
        Current.logging.log("Done")
    case .migratedOldSupportFiles:
        Current.logging.log("Migrating old support files...")
        Current.logging.log("Done")
    case .noMigrationNeeded:
        break
    }
}
