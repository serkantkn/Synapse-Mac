//
//  ClipboardMonitor.swift
//  Synapse Server
//
//  Monitors NSPasteboard for changes and notifies when new content is copied.
//

import Foundation
import AppKit
import Combine

/// Polls NSPasteboard at regular intervals to detect clipboard changes.
/// macOS doesn't provide a clipboard change notification API, so polling is necessary.
final class ClipboardMonitor: ObservableObject {

    @Published var currentContent: String = ""

    private var timer: Timer?
    private var lastChangeCount: Int = 0

    /// Callback invoked when clipboard content changes.
    var onClipboardChanged: ((String) -> Void)?

    /// Start monitoring the clipboard.
    func startMonitoring(interval: TimeInterval = 1.0) {
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    /// Stop monitoring.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        if changeCount != lastChangeCount {
            lastChangeCount = changeCount

            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                DispatchQueue.main.async {
                    self.currentContent = text
                }
                onClipboardChanged?(text)
            }
        }
    }

    /// Set the clipboard content (when receiving from the other device).
    func setClipboardContent(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount // Prevent echo
        DispatchQueue.main.async {
            self.currentContent = text
        }
    }

    deinit {
        stopMonitoring()
    }
}
