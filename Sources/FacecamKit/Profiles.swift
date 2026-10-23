import Foundation

/// Named control snapshots stored as `{"control": "value"}` JSON, one file per profile.
public struct ProfileStore: Sendable {
    public let directory: URL

    public static var standard: ProfileStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ProfileStore(directory: support.appending(path: "Facecam/profiles", directoryHint: .isDirectory))
    }

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(_ name: String) -> URL {
        directory.appending(path: "\(name).json")
    }

    public func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public func save(_ name: String, values: [String: ControlValue]) throws {
        var entries: [String: String] = [:]
        for (key, value) in values {
            entries[key] = Controls.named(key)?.label(for: value) ?? value.description
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: url(name), options: .atomic)
    }

    public func load(_ name: String) throws -> [String: ControlValue] {
        let entries = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url(name)))
        var values: [String: ControlValue] = [:]
        for (key, text) in entries {
            guard let control = Controls.named(key), let value = control.parse(text) else {
                throw ProfileError.invalidEntry(profile: name, control: key, value: text)
            }
            values[key] = value
        }
        return values
    }

    public func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: url(name))
    }
}

public enum ProfileError: Error, CustomStringConvertible {
    case invalidEntry(profile: String, control: String, value: String)

    public var description: String {
        switch self {
        case .invalidEntry(let profile, let control, let value):
            "profile \(profile): invalid value \(value) for \(control)"
        }
    }
}
