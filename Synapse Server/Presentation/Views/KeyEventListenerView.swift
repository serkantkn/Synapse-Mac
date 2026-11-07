//
//  KeyEventListenerView.swift
//  Synapse Server
//
//  Intercepts macOS keyboard events and forwards them.
//

import SwiftUI
import AppKit

struct KeyEventListenerView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyNSView {
        let view = KeyNSView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    class KeyNSView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
        
        // Suppress the system beep for unhandled keys
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            return true
        }
    }
}
