//
//  DebugLogger.swift
//  Moonlight Vision
//
//  Debug logging utility that writes to a file for crash-surviving logs.
//  Only active in DEBUG builds - completely stripped from release/App Store builds.
//

import Foundation

#if DEBUG

/// A lightweight debug logger that writes to a file asynchronously.
/// Logs survive app crashes and can be retrieved via Xcode's Devices window.
class DebugLogger {
    static let shared = DebugLogger()
    
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.neovectorx.debuglogger", qos: .utility)
    private let dateFormatter: DateFormatter
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("debug_log.txt")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // Clear old log on app launch
        try? FileManager.default.removeItem(at: fileURL)
        
        // Write header
        let header = "=== Debug Log Started: \(Date()) ===\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    /// Log a message with automatic timestamp
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let entry = "[\(timestamp)] [\(fileName):\(line)] \(message)\n"
        
        // Write asynchronously to avoid blocking main thread
        queue.async {
            if let data = entry.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: self.fileURL)
                }
            }
        }
        
        // Also print for when debugger IS attached (on your device)
        print(entry, terminator: "")
    }
    
    /// Get the file URL for manual retrieval
    func getLogFileURL() -> URL {
        return fileURL
    }
    
    /// Read all logs (for in-app display if needed)
    func readLogs() -> String {
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "No logs available"
    }
}

/// Convenience global function for debug logging
func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    DebugLogger.shared.log(message, file: file, function: function, line: line)
}

#else

/// No-op in release builds - completely stripped by compiler
@inline(__always)
func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    // Does nothing in release builds
}

#endif
