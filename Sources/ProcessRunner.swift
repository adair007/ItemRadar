import Foundation

/// 同步运行一个外部命令，返回 stdout 文本（失败返回 nil）。
/// 统一封装 Process+Pipe 样板，避免散落各处。
enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}