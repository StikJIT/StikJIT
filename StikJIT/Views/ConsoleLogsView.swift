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
    @AppStorage("autoScroll") private var autoScroll: Bool = true
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
    @State private var isLoadingLogs = false        // Track loading state
    @State private var isAtBottom = true            // Track if user is at bottom of logs
    
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
                // Use system background color instead of a fixed black
                Color(colorScheme == .dark ? .black : .white)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Terminal logs area with theme support
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Device Information section
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
                            // Consider user is at bottom if within 20 points of bottom.
                            isAtBottom = offset > -20
                        }
                        .onChange(of: logManager.logs.count) { _ in
                            // Auto scroll if enabled
                            if autoScroll {
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
                            Task { await loadIdeviceLogsAsync() }
                            startLogCheckTimer()
                        }
                        .onDisappear {
                            isViewActive = false
                            stopLogCheckTimer()
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        // Red errors rectangle
                        Text("\(logManager.errorCount) Errors")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .cornerRadius(10)
                        
                        Menu {
                            Toggle("Auto Scroll", isOn: $autoScroll)
                            
                            Button(action: { copyLogs() }) {
                                Label("Copy Logs", systemImage: "doc.on.doc")
                            }
                        } label: {
                            HStack {
                                Text("Menu")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Console")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 2) { Text("Done").fontWeight(.regular) }
                                .foregroundColor(accentColor)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button(action: { Task { await loadIdeviceLogsAsync() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(accentColor)
                            }
                            
                            Button(action: { logManager.clearLogs() }) {
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
                                    onDismiss: { showingCustomAlert = false },
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
    
    // MARK: - Helper Functions
    
    private func createLogAttributedString(_ logEntry: LogManager.LogEntry) -> NSAttributedString {
        let fullString = NSMutableAttributedString()
        
        let timestampString = "[\(formatTime(date: logEntry.timestamp))]"
        let timestampAttr = NSAttributedString(
            string: timestampString,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.gray : UIColor.darkGray]
        )
        fullString.append(timestampAttr)
        fullString.append(NSAttributedString(string: " "))
        
        let typeString = "[\(logEntry.type.rawValue)]"
        let typeColor = UIColor(colorForLogType(logEntry.type))
        let typeAttr = NSAttributedString(
            string: typeString,
            attributes: [.foregroundColor: typeColor]
        )
        fullString.append(typeAttr)
        fullString.append(NSAttributedString(string: " "))
        
        let messageAttr = NSAttributedString(
            string: logEntry.message,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black]
        )
        fullString.append(messageAttr)
        
        return fullString
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
    
    private func loadIdeviceLogsAsync() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        guard FileManager.default.fileExists(atPath: logPath) else {
            await MainActor.run {
                logManager.addInfoLog("No idevice logs found (Restart the app to continue reading)")
                isLoadingLogs = false
            }
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            let maxLines = 500
            let startIndex = max(0, lines.count - maxLines)
            let recentLines = Array(lines[startIndex..<lines.count])
            lastProcessedLineCount = lines.count
            
            await MainActor.run {
                logManager.clearLogs()
                for line in recentLines {
                    if line.isEmpty { continue }
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
        
        await MainActor.run { isLoadingLogs = false }
    }
    
    private func startLogCheckTimer() {
        logCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            if isViewActive {
                Task { await checkForNewLogs() }
            }
        }
    }
    
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
    
    private func stopLogCheckTimer() {
        logCheckTimer?.invalidate()
        logCheckTimer = nil
    }
    
    // MARK: - Action Helpers
    
    private func exportLogs() {
        let logURL = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            alertTitle = "Export Failed"
            alertMessage = "No idevice logs found"
            isError = true
            showingCustomAlert = true
            return
        }
        // TODO: Present a share sheet to export the log file.
        alertTitle = "Export Logs"
        alertMessage = "Export functionality is not implemented."
        isError = false
        showingCustomAlert = true
    }
    
    private func copyLogs() {
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
