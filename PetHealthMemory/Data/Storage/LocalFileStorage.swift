import Foundation

protocol LocalFileStorageProtocol {
    func saveFile(data: Data, fileName: String, subdirectory: String) throws -> String
    func resolveURL(relativePath: String) -> URL
    func deleteFile(relativePath: String) throws
}

/// Stores original veterinary documents and pet photos in app-private Application Support storage.
final class LocalFileStorage: LocalFileStorageProtocol {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("PetHealthMemoryFiles", isDirectory: true)
    }

    func saveFile(data: Data, fileName: String, subdirectory: String = "documents") throws -> String {
        let dir = baseDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let sanitized = fileName.replacingOccurrences(of: "/", with: "_")
        let relativePath = "\(subdirectory)/\(UUID().uuidString)_\(sanitized)"
        let destination = baseDirectory.appendingPathComponent(relativePath)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return relativePath
    }

    func resolveURL(relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    func deleteFile(relativePath: String) throws {
        let target = resolveURL(relativePath: relativePath)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }
}
