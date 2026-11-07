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
    /// Last text seen or set. Some apps bump changeCount without changing the text
    /// (clipboard managers, etc.), which would otherwise resend the same text every tick.
    private var lastText: String?

    /// Callback invoked when clipboard content changes.
    var onClipboardChanged: ((String) -> Void)?

    /// Start monitoring the clipboard.
    func startMonitoring(interval: TimeInterval = 1.0) {
        lastChangeCount = NSPasteboard.general.changeCount
        lastText = NSPasteboard.general.string(forType: .string)

        timer?.invalidate() // never run two timers
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

            if let text = pasteboard.string(forType: .string), !text.isEmpty, text != lastText {
                lastText = text
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
        lastText = text
        DispatchQueue.main.async {
            self.currentContent = text
        }
    }

    deinit {
        stopMonitoring()
    }
}
