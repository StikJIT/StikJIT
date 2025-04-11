//
//  ConsoleLogsView.swift
//  StikJIT
//
//  Created by neoarz on 3/29/25.
//

import SwiftUI
import UIKit

struct ConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var logManager = LogManager.shared
    @State private var autoScroll = true
    @State private var scrollView: ScrollViewProxy? = nil
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    // Alert handling
    @State private var showingCustomAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isError = false
    
    // Timer to check for log updates
    @State private var logCheckTimer: Timer? = nil
    
    // Track if the view is active (visible)
    @State private var isViewActive = false
    @State private var lastProcessedLineCount = 0  // Track last processed line count
    @State private var isLoadingLogs = false  // Track loading state
    @State private var isAtBottom = true  // Track if user is at bottom of logs
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .blue
        } else {
            return Color(hex: customAccentColorHex) ?? .blue
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Use system background color instead of fixed black
                Color(colorScheme == .dark ? .black : .white)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Terminal logs area with theme support
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Device Information
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("=== DEVICE INFORMATION ===")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .padding(.vertical, 4)
                                    
                                    Text("iOS Version: \(UIDevice.current.systemVersion)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("Device: \(UIDevice.current.name)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("Model: \(UIDevice.current.model)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("=== LOG ENTRIES ===")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .padding(.vertical, 4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                
                                // Log entries
                                ForEach(logManager.logs) { logEntry in
                                    Text(AttributedString(createLogAttributedString(logEntry)))
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 1)
                                        .padding(.horizontal, 4)
                                        .id(logEntry.id)
                                }
                            }
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scroll")).minY
                                    )
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                            // Consider user is at bottom if they're within 20 points of the bottom
                            // This gives a small buffer for slight scroll movements
                            isAtBottom = offset > -20
                        }
                        .onChange(of: logManager.logs.count) { _ in
                            if isAtBottom {
                                withAnimation {
                                    if let lastLog = logManager.logs.last {
                                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            scrollView = proxy
                            isViewActive = true
                            // Load logs asynchronously
                            Task {
                                await loadIdeviceLogsAsync()
                            }
                            startLogCheckTimer()
                        }
                        .onDisappear {
                            isViewActive = false
                            stopLogCheckTimer()
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons section - update to be theme aware
                    VStack(spacing: 16) {
                        // Error count with red theme
                        HStack {
                            Text("\(logManager.errorCount) Errors")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        // Action buttons with theme-appropriate background
                        VStack(spacing: 1) {
                            // Export button
                            ShareLink(
                                item: {
                                    // Get the path to the idevice log file
                                    let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
                                    
                                    // Check if the file exists
                                    guard FileManager.default.fileExists(atPath: logPath.path) else {
                                        alertTitle = "Export Failed"
                                        alertMessage = "No idevice logs found"
                                        isError = true
                                        showingCustomAlert = true
                                        return URL.documentsDirectory.appendingPathComponent("empty.txt")
                                    }
                                    
                                    return logPath
                                }(),
                                preview: SharePreview(
                                    "idevice_log.txt",
                                    image: Image(systemName: "doc.text")
                                )
                            ) {
                                HStack {
                                    Text("Export Logs")
                                        .foregroundColor(accentColor)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundColor(accentColor)
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 20)
                                .contentShape(Rectangle())
                            }
                            .background(colorScheme == .dark ?
                                Color(red: 0.1, green: 0.1, blue: 0.1) :
                                Color(UIColor.secondarySystemBackground))
                            
                            Divider()
                                .background(colorScheme == .dark ?
                                    Color(red: 0.15, green: 0.15, blue: 0.15) :
                                    Color(UIColor.separator))
                            
                            // Copy button
                            Button(action: {
                                // Existing code for copying logs
                                var logsContent = "=== DEVICE INFORMATION ===\n"
                                logsContent += "Version: \(UIDevice.current.systemVersion)\n"
                                logsContent += "Name: \(UIDevice.current.name)\n"
                                logsContent += "Model: \(UIDevice.current.model)\n"
                                logsContent += "StikJIT Version: App Version: 1.0\n\n"
                                logsContent += "=== LOG ENTRIES ===\n"
                                
                                logsContent += logManager.logs.map {
                                    "[\(formatTime(date: $0.timestamp))] [\($0.type.rawValue)] \($0.message)"
                                }.joined(separator: "\n")
                                
                                UIPasteboard.general.string = logsContent
                                
                                alertTitle = "Logs Copied"
                                alertMessage = "Logs have been copied to clipboard."
                                isError = false
                                showingCustomAlert = true
                            }) {
                                HStack {
                                    Text("Copy Logs")
                                        .foregroundColor(accentColor)
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(accentColor)
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 20)
                                .contentShape(Rectangle())
                            }
                            .background(colorScheme == .dark ?
                                Color(red: 0.1, green: 0.1, blue: 0.1) :
                                Color(UIColor.secondarySystemBackground))
                        }
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                    .padding(.bottom, 8)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Console")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 2) {
                                Text("Done")
                                    .fontWeight(.regular)
                            }
                            .foregroundColor(accentColor)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button(action: {
                                // Load the logs again
                                Task {
                                    await loadIdeviceLogsAsync()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(accentColor)
                            }
                            
                            Button(action: {
                                logManager.clearLogs()
                            }) {
                                Text("Clear")
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                }
            }
            .overlay(
                Group {
                    if showingCustomAlert {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                            .overlay(
                                CustomErrorView(
                                    title: alertTitle,
                                    message: alertMessage,
                                    onDismiss: {
                                        showingCustomAlert = false
                                    },
                                    showButton: true,
                                    primaryButtonText: "OK",
                                    messageType: isError ? .error : .success
                                )
                            )
                    }
                }
            )
        }
    }
    
    // Update to use theme-aware colors
    private func createLogAttributedString(_ logEntry: LogManager.LogEntry) -> NSAttributedString {
        let fullString = NSMutableAttributedString()
        
        // Timestamp part
        let timestampString = "[\(formatTime(date: logEntry.timestamp))]"
        let timestampAttr = NSAttributedString(
            string: timestampString,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.gray : UIColor.darkGray]
        )
        fullString.append(timestampAttr)
        fullString.append(NSAttributedString(string: " "))
        
        // Log type part
        let typeString = "[\(logEntry.type.rawValue)]"
        let typeColor = UIColor(colorForLogType(logEntry.type))
        let typeAttr = NSAttributedString(
            string: typeString,
            attributes: [.foregroundColor: typeColor]
        )
        fullString.append(typeAttr)
        fullString.append(NSAttributedString(string: " "))
        
        // Message part
        let messageAttr = NSAttributedString(
            string: logEntry.message,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black]
        )
        fullString.append(messageAttr)
        
        return fullString
    }
    
    private func timeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func colorForLogType(_ type: LogManager.LogEntry.LogType) -> Color {
        switch type {
        case .info:
            return .green
        case .error:
            return .red
        case .debug:
            return accentColor
        case .warning:
            return .orange
        }
    }
    
    // Function to load idevice logs from file asynchronously
    private func loadIdeviceLogsAsync() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        // Get the path to the idevice log file
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: logPath) else {
            await MainActor.run {
                logManager.addInfoLog("No idevice logs found (Restart the app to continue reading)")
                isLoadingLogs = false
            }
            return
        }
        
        do {
            // Read the file content
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            // Only take the last 500 lines
            let maxLines = 500
            let startIndex = max(0, lines.count - maxLines)
            let recentLines = Array(lines[startIndex..<lines.count])
            
            // Update the last processed line count
            lastProcessedLineCount = lines.count
            
            await MainActor.run {
                // Clear existing logs
                logManager.clearLogs()
                
                // Process recent lines
                for line in recentLines {
                    if line.isEmpty { continue }
                    
                    // Skip device information lines that we already show in the header
                    if line.contains("=== DEVICE INFORMATION ===") ||
                       line.contains("Version:") ||
                       line.contains("Name:") ||
                       line.contains("Model:") ||
                       line.contains("=== LOG ENTRIES ===") {
                        continue
                    }
                    
                    if line.contains("ERROR") || line.contains("Error") {
                        logManager.addErrorLog(line)
                    } else if line.contains("WARNING") || line.contains("Warning") {
                        logManager.addWarningLog(line)
                    } else if line.contains("DEBUG") {
                        logManager.addDebugLog(line)
                    } else {
                        logManager.addInfoLog(line)
                    }
                }
            }
        } catch {
            await MainActor.run {
                logManager.addErrorLog("Failed to read idevice logs: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            isLoadingLogs = false
        }
    }
    
    // Update the timer function to use async loading
    private func startLogCheckTimer() {
        logCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            if isViewActive {
                Task {
                    await checkForNewLogs()
                }
            }
        }
    }
    
    // Function to check for new logs
    private func checkForNewLogs() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        
        guard FileManager.default.fileExists(atPath: logPath) else {
            isLoadingLogs = false
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            // Only process new lines
            if lines.count > lastProcessedLineCount {
                let newLines = Array(lines[lastProcessedLineCount..<lines.count])
                lastProcessedLineCount = lines.count
                
                await MainActor.run {
                    for line in newLines {
                        if line.isEmpty { continue }
                        
                        if line.contains("ERROR") || line.contains("Error") {
                            logManager.addErrorLog(line)
                        } else if line.contains("WARNING") || line.contains("Warning") {
                            logManager.addWarningLog(line)
                        } else if line.contains("DEBUG") {
                            logManager.addDebugLog(line)
                        } else {
                            logManager.addInfoLog(line)
                        }
                    }
                    
                    // Keep only the last 300 lines
                    let maxLines = 500
                    if logManager.logs.count > maxLines {
                        let excessCount = logManager.logs.count - maxLines
                        logManager.removeOldestLogs(count: excessCount)
                    }
                }
            }
        } catch {
            await MainActor.run {
                logManager.addErrorLog("Failed to read new logs: \(error.localizedDescription)")
            }
        }
        
        isLoadingLogs = false
    }
    
    // Function to stop the timer
    private func stopLogCheckTimer() {
        logCheckTimer?.invalidate()
        logCheckTimer = nil
    }
}

struct ConsoleLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleView()
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
