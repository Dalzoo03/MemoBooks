import Foundation

@main struct BackupFileChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let earlier = BackupRecord(id: UUID(), amount: 4500, category: "카페", memo: "커피", date: date,
            createdAt: date, isAiClassified: false, kind: .expense)
        let later = BackupRecord(id: UUID(), amount: 9000, category: "식비", memo: "점심", date: date.addingTimeInterval(86400),
            createdAt: date, isAiClassified: false, kind: .expense)
        let file = root.appendingPathComponent("backup.json")
        let data = try await BackupFiles.export([later, earlier], csv: false)
        try data.write(to: file)
        let backup = try await BackupFiles.read(file)
        precondition(backup.records == [earlier, later], "async file round trip preserves and sorts records")
        let csvData = try await BackupFiles.export([later, earlier], csv: true)
        precondition(csvData == Data(BackupCodec.csv([earlier, later]).utf8))
        try Data("invalid".utf8).write(to: file)
        do { _ = try await BackupFiles.read(file); preconditionFailure("corrupt file accepted") } catch { }
        try Data(repeating: 0, count: BackupCodec.maximumBytes + 1).write(to: file)
        do { _ = try await BackupFiles.read(file); preconditionFailure("oversized file accepted") } catch { }
        do { _ = try await BackupFiles.read(root.appendingPathComponent("missing.json")); preconditionFailure("missing file accepted") } catch { }
        let invalid = BackupRecord(id: UUID(), amount: -1, category: "기타", memo: "invalid", date: date,
            createdAt: date, isAiClassified: false, kind: .expense)
        do { _ = try await BackupFiles.export([invalid], csv: false); preconditionFailure("invalid export accepted") } catch { }
        print("Passed async backup file checks (JSON/CSV, sorting, invalid, oversized and missing files)")
    }
}
