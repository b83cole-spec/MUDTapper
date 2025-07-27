import Foundation

protocol LoggableWorld {
    var name: String? { get }
    var hostname: String? { get }
    var port: Int32 { get }
}

class SessionLogger {
    
    // MARK: - Properties
    
    private var _isLogging: Bool = false
    private var currentLogFileURL: URL?
    private var fileHandle: FileHandle?
    private var worldInfo: (name: String?, hostname: String?, port: Int32)?
    private var startTime: Date?
    
    // User preferences
    private var autoLoggingEnabled: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoLogging)
    }
    
    var isLogging: Bool {
        return _isLogging
    }
    
    var canStartLogging: Bool {
        return autoLoggingEnabled && !_isLogging
    }
    
    // MARK: - File Management
    
    static var logsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsPath = documentsPath.appendingPathComponent("MUDTapper/Logs")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsPath, withIntermediateDirectories: true, attributes: nil)
        
        return logsPath
    }
    
    // MARK: - Logging Control
    
    func startLogging(for world: LoggableWorld, force: Bool = false) {
        guard !_isLogging else { return }
        
        // Check if auto-logging is enabled or if forced
        guard force || autoLoggingEnabled else {
            print("📝 Auto-logging is disabled, skipping log start")
            return
        }
        
        self.worldInfo = (name: world.name, hostname: world.hostname, port: world.port)
        self.startTime = Date()
        
        // Create log file
        let filename = generateLogFilename(for: world)
        currentLogFileURL = Self.logsDirectory.appendingPathComponent(filename)
        
        guard let logFileURL = currentLogFileURL else { return }
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
        
        // Open file handle
        do {
            fileHandle = try FileHandle(forWritingTo: logFileURL)
            fileHandle?.seekToEndOfFile()
            _isLogging = true
            
            // Write session header
            let header = """
            =====================================
            MUDTapper Session Log
            World: \(world.name ?? "Unknown")
            Host: \(world.hostname ?? "Unknown"):\(world.port)
            Started: \(ISO8601DateFormatter().string(from: Date()))
            =====================================
            
            """
            writeToLog(header)
            
            print("📝 Session logging started: \(filename)")
            
        } catch {
            print("❌ Failed to start logging: \(error.localizedDescription)")
            _isLogging = false
            fileHandle = nil
        }
    }
    
    func stopLogging() {
        guard _isLogging else { return }
        
        // Write session footer
        if let startTime = startTime {
            let duration = Date().timeIntervalSince(startTime)
            let footer = """
            
            =====================================
            Session ended: \(ISO8601DateFormatter().string(from: Date()))
            Duration: \(formatDuration(duration))
            =====================================
            """
            writeToLog(footer)
        }
        
        fileHandle?.closeFile()
        fileHandle = nil
        _isLogging = false
        worldInfo = nil
        startTime = nil
        currentLogFileURL = nil
        
        print("📝 Session logging stopped")
    }
    
    func writeToLog(_ text: String) {
        guard _isLogging, let fileHandle = fileHandle else { return }
        
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        
        // Ensure text ends with a newline if it doesn't already have one
        let cleanText = text.hasSuffix("\n") ? text : text + "\n"
        let logEntry = "[\(timestamp)] \(cleanText)"
        
        if let data = logEntry.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
    
    func writeCommand(_ command: String) {
        guard _isLogging else { return }
        writeToLog("> \(command)")
    }
    
    func writeReceivedText(_ text: String) {
        guard _isLogging else { return }
        
        // Split text by lines and log each line separately to ensure proper formatting
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if !line.isEmpty {
                writeToLog(line)
            }
        }
    }
    
    // MARK: - File Management
    
    private func generateLogFilename(for world: LoggableWorld) -> String {
        let worldName = world.name?.replacingOccurrences(of: " ", with: "_") ?? "Unknown"
        let safeWorldName = worldName.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let timestamp = DateFormatter.filename.string(from: Date())
        return "\(safeWorldName)_\(timestamp).log"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Static Utilities
    
    static func getAllLogFiles() -> [URL] {
        let logsDir = logsDirectory
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
            return files.filter { $0.pathExtension == "log" }.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2 // Most recent first
            }
        } catch {
            print("❌ Failed to list log files: \(error.localizedDescription)")
            return []
        }
    }
    
    static func deleteLogFile(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            print("❌ Failed to delete log file: \(error.localizedDescription)")
            return false
        }
    }
    
    static func getLogFileInfo(_ url: URL) -> (size: String, date: String)? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int64 ?? 0
            let date = attributes[.creationDate] as? Date ?? Date()
            
            let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            let dateString = DateFormatter.display.string(from: date)
            
            return (size: sizeString, date: dateString)
        } catch {
            return nil
        }
    }
    
    // MARK: - Log Rotation for Large Files
    
    func checkAndRotateLogIfNeeded() {
        guard _isLogging, let logFileURL = currentLogFileURL else { return }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let maxSize: Int64 = 50 * 1024 * 1024 // 50MB limit
            
            if fileSize > maxSize {
                print("📝 Log file size (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))) exceeds limit, rotating...")
                rotateCurrentLog()
            }
        } catch {
            print("❌ Failed to check log file size: \(error.localizedDescription)")
        }
    }
    
    private func rotateCurrentLog() {
        guard let worldInfo = worldInfo, let currentURL = currentLogFileURL else { return }
        
        // Close current log
        stopLogging()
        
        // Rename current log with rotation suffix
        let rotatedURL = currentURL.appendingPathExtension("rotated")
        do {
            try FileManager.default.moveItem(at: currentURL, to: rotatedURL)
            print("📝 Rotated log file to: \(rotatedURL.lastPathComponent)")
        } catch {
            print("❌ Failed to rotate log file: \(error.localizedDescription)")
        }
        
        // Start new log
        let world = SimpleWorld(name: worldInfo.name, hostname: worldInfo.hostname, port: worldInfo.port)
        startLogging(for: world, force: true)
    }
}

// MARK: - Helper Structures

struct SimpleWorld: LoggableWorld {
    let name: String?
    let hostname: String?
    let port: Int32
}

// MARK: - Log Search Functionality

extension SessionLogger {
    
    struct SearchResult {
        let lineNumber: Int
        let line: String
        let context: [String] // Lines before and after for context
        let timestamp: String?
    }
    
    static func searchLogs(query: String, caseSensitive: Bool = false, regex: Bool = false, contextLines: Int = 2) -> [URL: [SearchResult]] {
        let logFiles = getAllLogFiles()
        var results: [URL: [SearchResult]] = [:]
        
        for logFile in logFiles {
            let fileResults = searchLogFile(logFile, query: query, caseSensitive: caseSensitive, regex: regex, contextLines: contextLines)
            if !fileResults.isEmpty {
                results[logFile] = fileResults
            }
        }
        
        return results
    }
    
    static func searchLogFile(_ fileURL: URL, query: String, caseSensitive: Bool = false, regex: Bool = false, contextLines: Int = 2) -> [SearchResult] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        
        let lines = content.components(separatedBy: .newlines)
        var results: [SearchResult] = []
        
        for (index, line) in lines.enumerated() {
            let matches: Bool
            
            if regex {
                // Regex search
                do {
                    let regexOptions: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
                    let regex = try NSRegularExpression(pattern: query, options: regexOptions)
                    let range = NSRange(location: 0, length: line.utf16.count)
                    matches = regex.firstMatch(in: line, options: [], range: range) != nil
                } catch {
                    continue // Invalid regex, skip this line
                }
            } else {
                // Simple text search
                let searchLine = caseSensitive ? line : line.lowercased()
                let searchQuery = caseSensitive ? query : query.lowercased()
                matches = searchLine.contains(searchQuery)
            }
            
            if matches {
                // Extract context lines
                let startIndex = max(0, index - contextLines)
                let endIndex = min(lines.count - 1, index + contextLines)
                let contextLines = Array(lines[startIndex...endIndex])
                
                // Extract timestamp if present
                let timestamp = extractTimestamp(from: line)
                
                let result = SearchResult(
                    lineNumber: index + 1,
                    line: line,
                    context: contextLines,
                    timestamp: timestamp
                )
                results.append(result)
            }
        }
        
        return results
    }
    
    private static func extractTimestamp(from line: String) -> String? {
        // Look for timestamp pattern [YYYY-MM-DD HH:MM:SS]
        let pattern = #"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: line.utf16.count)
            
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let timestampRange = Range(match.range(at: 1), in: line) {
                return String(line[timestampRange])
            }
        } catch {
            // Ignore regex errors
        }
        
        return nil
    }
}

// MARK: - Date Formatters

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    static let filename: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()
    
    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
} 