//
//  Synapse_ServerApp.swift
//  Synapse Server
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@main
struct Synapse_ServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var viewModel = SynapseViewModel.shared

    var body: some Scene {
        Window("Synapse", id: "main") {
            ContentView()
                .environment(\.locale, .turkish)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Window("Ekran Yansıtma", id: "mirroring") {
            MirroringStandaloneView(viewModel: viewModel)
                .environment(\.locale, .turkish)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 360, height: 720)

        MenuBarExtra {
            StatusMenuView(viewModel: viewModel)
                .environment(\.locale, .turkish)
        } label: {
            HStack(spacing: 4) {
                if viewModel.connectionStatus == .connected {
                    Image(systemName: "iphone")
                    if let battery = viewModel.batteryLevel {
                        Text("%\(battery)")
                    }
                } else if viewModel.connectionStatus == .connecting || viewModel.connectionStatus == .pairing {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                } else {
                    Image(systemName: "iphone.slash")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct StatusMenuView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private var isConnected: Bool { viewModel.connectionStatus == .connected }

    var body: some View {
        VStack(spacing: 14) {
            header

            if isConnected {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        StatItem(icon: "phone.fill", count: viewModel.calls.count, label: "Çağrı", color: .green)
                        StatItem(icon: "message.fill", count: viewModel.messages.count, label: "SMS", color: .synapseBlue)
                        StatItem(icon: "bell.fill", count: viewModel.notifications.count, label: "Bildirim", color: .orange)
                    }
                }

                if viewModel.media != nil {
                    NowPlayingCard(viewModel: viewModel, compact: true)
                        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                lastNotification

                QuickActionsRow(viewModel: viewModel, compact: true)
                TransferMessageBanner(viewModel: viewModel)
            } else {
                waitingCard
            }

            HStack(spacing: 10) {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    dismiss()
                } label: {
                    Label("Paneli Aç", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)

                Button(action: confirmQuit) {
                    Image(systemName: "power")
                }
                .glassButtonStyle()
                .foregroundStyle(.red)
                .help("Synapse'den çık")
                .accessibilityLabel("Synapse'den çık")
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 340)
        .sendsDroppedFiles(to: viewModel)
        .animation(.smooth, value: viewModel.connectionStatus)
    }

    private var header: some View {
        HStack(spacing: 12) {
            SynapseMark(size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(isConnected ? (viewModel.connectedDeviceName ?? "Android") : "Synapse")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    StatusDot(color: viewModel.connectionStatus.tint, size: 6)
                    Text(viewModel.connectionStatus.title)
                    if isConnected, let battery = viewModel.batteryLevel {
                        Text("·")
                        Image(systemName: batterySymbol(battery))
                            .foregroundStyle(battery > 20 ? Color.green : Color.red)
                        Text("%\(battery)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var lastNotification: some View {
        if let last = viewModel.notifications.first {
            HStack(spacing: 10) {
                if let image = last.icon {
                    Image(nsImage: image).resizable().frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    IconTile(systemName: "bell.fill", color: .orange, size: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(last.title.isEmpty ? last.appName : last.title)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(last.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(last.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var waitingCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.synapseGradient)
                .symbolEffect(.variableColor.iterative.reversing,
                              isActive: viewModel.connectionStatus == .discovering)
            Text("Telefon bekleniyor").font(.system(size: 13, weight: .semibold))
            if !viewModel.pairingCode.isEmpty {
                Text("PIN \(viewModel.pairingCode)")
                    .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Synapse'den çıkılsın mı?"
        alert.informativeText = "Bağlantı kesilecek ve bildirim senkronizasyonu duracak."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Çıkış Yap")
        alert.addButton(withTitle: "İptal")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

struct StatItem: View {
    let icon: String; let count: Int; let label: String; let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)").font(.system(size: 16, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tekilleştirme (Single Instance) Kontrolü
        if let bundleID = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if runningApps.count > 1 {
                // Diğer çalışan kopyayı bul
                if let existingApp = runningApps.first(where: { $0 != NSRunningApplication.current }) {
                    if #available(macOS 14.0, *) {
                        existingApp.activate()
                    } else {
                        existingApp.activate(options: [.activateAllWindows])
                    }
                }
                // Bu yeni kopyayı derhal sonlandır
                NSApp.terminate(nil)
                return
            }
        }
        
        updateActivationPolicy()
        
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateActivationPolicy()
        }
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
            }
        }
    }

    private func updateActivationPolicy() {
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.className != "NSStatusBarWindow" }
        let currentPolicy = NSApp.activationPolicy()
        
        if hasVisibleWindows && currentPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        } else if !hasVisibleWindows && currentPolicy != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }
}

struct MirroringStandaloneView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyMonitor: Any? = nil
    @State private var showAccessibilityWarning = true

    var body: some View {
        ZStack {
            VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // Top Header
                HStack {
                    HStack(spacing: 8) {
                        StatusDot(color: viewModel.isMirroring ? .green : .red, size: 7)
                        Text(viewModel.connectedDeviceName ?? "Cihaz").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassSurface(in: Capsule())

                    Spacer()

                    Button(action: {
                        viewModel.toggleScreenMirroring()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .glassButtonStyle()
                    .help("Yansıtmayı durdur")
                    .accessibilityLabel("Yansıtmayı durdur")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Screen Image
                if let frame = viewModel.screenFrame {
                    GeometryReader { geo in
                        Image(nsImage: frame)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let imageWidth = frame.size.width
                                        let imageHeight = frame.size.height
                                        
                                        guard imageWidth > 0 && imageHeight > 0 else { return }
                                        
                                        let imageRatio = imageWidth / imageHeight
                                        let containerRatio = geo.size.width / geo.size.height
                                        
                                        var fittedWidth = geo.size.width
                                        var fittedHeight = geo.size.height
                                        var offsetX: CGFloat = 0
                                        var offsetY: CGFloat = 0
                                        
                                        if imageRatio > containerRatio {
                                            fittedWidth = geo.size.width
                                            fittedHeight = geo.size.width / imageRatio
                                            offsetY = (geo.size.height - fittedHeight) / 2
                                        } else {
                                            fittedWidth = geo.size.height * imageRatio
                                            fittedHeight = geo.size.height
                                            offsetX = (geo.size.width - fittedWidth) / 2
                                        }
                                        
                                        let relativeX = (value.startLocation.x - offsetX) / fittedWidth
                                        let relativeY = (value.startLocation.y - offsetY) / fittedHeight
                                        
                                        let x = max(0.0, min(1.0, Double(relativeX)))
                                        let y = max(0.0, min(1.0, Double(relativeY)))
                                        
                                        if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                                            viewModel.sendRemoteInput(x: x, y: y, action: "CLICK")
                                        } else {
                                            if abs(value.translation.height) > abs(value.translation.width) {
                                                viewModel.sendRemoteInput(x: x, y: y, action: value.translation.height < 0 ? "SWIPE_UP" : "SWIPE_DOWN")
                                            } else {
                                                viewModel.sendRemoteInput(x: x, y: y, action: value.translation.width < 0 ? "SWIPE_LEFT" : "SWIPE_RIGHT")
                                            }
                                        }
                                    }
                            )
                    }
                    .transition(.opacity)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        viewModel.handleFileDrop(providers)
                    }
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Görüntü Bekleniyor...")
                            .font(.headline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if viewModel.isMirroring {
                    VStack(spacing: 10) {
                        GlassGroup(spacing: 12) {
                            HStack(spacing: 12) {
                                navButton("square.on.square", action: "RECENTS", help: "Son uygulamalar")
                                navButton("circle", action: "HOME", help: "Ana ekran")
                                navButton("chevron.backward", action: "BACK", help: "Geri")
                            }
                        }
                        .padding(.top, 10)
                        
                        if showAccessibilityWarning && !viewModel.isRemoteAccessibilityEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("Kontroller için telefonda Synapse erişilebilirlik servisi açık olmalı.")
                                    .font(.system(size: 11, weight: .medium))
                                
                                Button(action: { showAccessibilityWarning = false }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassSurface(in: Capsule(), tint: Color.yellow.opacity(0.2))
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 640)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Allow Cmd keyboard combinations to pass through (e.g. Cmd+W, Cmd+Q)
                if event.modifierFlags.contains(.command) {
                    return event
                }
                handleKeyEvent(event)
                return nil // Prevent system alert sound/beep
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            // Stop mirroring process when the window is closed
            if viewModel.isMirroring {
                viewModel.toggleScreenMirroring()
            }
        }
    }


    private func navButton(_ symbol: String, action: String, help: String) -> some View {
        Button {
            viewModel.sendRemoteInput(x: 0, y: 0, action: action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Capsule(), interactive: true)
        .help(help)
        .accessibilityLabel(help)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 51 { // Delete / Backspace
            viewModel.sendKeyboardInput(key: "BACKSPACE", type: "SPECIAL")
        } else if event.keyCode == 36 { // Return / Enter
            viewModel.sendKeyboardInput(key: "ENTER", type: "SPECIAL")
        } else if event.keyCode == 49 { // Space
            viewModel.sendKeyboardInput(key: " ", type: "STRING")
        } else if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            return // shortcuts (⌘W, ⌃C…) aren't text for the phone
        } else if let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0)
                      && !(0xF700...0xF8FF).contains($0.value) }) { // arrows and F-keys
            // `characters` keeps Shift and Option: ⇧A types "A", ⇧1 "!", ⌥2 "€".
            // A dead key (⌥E) gives an empty string here and the accented letter on the next key.
            viewModel.sendKeyboardInput(key: chars, type: "STRING")
        }
    }
}
