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
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Window("Ekran Yansıtma", id: "mirroring") {
            MirroringStandaloneView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 360, height: 720)

        MenuBarExtra {
            StatusMenuView(viewModel: viewModel)
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
    @State private var showQuitAlert = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                SynapseLogoIcon().scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.connectionStatus == .connected ? "Bağlı: \(viewModel.connectedDeviceName ?? "Android")" : "Bağlantı Yok")
                        .font(.system(size: 14, weight: .bold))
                    
                    if viewModel.connectionStatus == .connected, let battery = viewModel.batteryLevel {
                        HStack(spacing: 4) {
                            Image(systemName: battery > 20 ? "battery.75" : "battery.25")
                                .foregroundStyle(battery > 20 ? .green : .red)
                            Text("%\(battery) Şarj")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                
                Circle()
                    .fill(viewModel.connectionStatus == .connected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // Stats
            HStack(spacing: 20) {
                StatItem(icon: "phone.fill", count: viewModel.calls.count, label: "Çağrı", color: .green)
                StatItem(icon: "message.fill", count: viewModel.messages.count, label: "SMS", color: .blue)
                StatItem(icon: "bell.fill", count: viewModel.notifications.count, label: "Bildirim", color: .orange)
            }

            // Last Notification
            VStack(alignment: .leading, spacing: 6) {
                Text("Son Bildirim")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                
                if let lastNotif = viewModel.notifications.first {
                    HStack(spacing: 10) {
                        if let image = lastNotif.icon {
                            Image(nsImage: image).resizable().frame(width: 28, height: 28).cornerRadius(6)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(lastNotif.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(lastNotif.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                } else {
                    Text("Yeni bildirim yok")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                }
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    dismiss()
                }) {
                    Label("Paneli Aç", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { 
                    let alert = NSAlert()
                    alert.messageText = "Synapse'den Çıkılsın mı?"
                    alert.informativeText = "Bağlantı kesilecek ve bildirim senkronizasyonu duracaktır."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Çıkış Yap")
                    alert.addButton(withTitle: "İptal")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSApp.terminate(nil)
                    }
                }) {
                    Image(systemName: "power")
                        .foregroundStyle(.red)
                        .padding(10)
                        .modifier(GlassTintedBackground(cornerRadius: 10, tint: .red))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
    }
}

struct StatItem: View {
    let icon: String; let count: Int; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if #available(macOS 26.0, *) {
                    Circle().fill(.clear).frame(width: 40, height: 40)
                        .glassEffect(.regular, in: .circle)
                        .tint(color)
                } else {
                    Circle().fill(color.opacity(0.1)).frame(width: 40, height: 40)
                }
                Image(systemName: icon).foregroundStyle(color)
            }
            Text("\(count)").font(.system(size: 16, weight: .bold))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
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

struct SynapseLogoIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 32, height: 32)
            ZStack {
                Group {
                    Rectangle().frame(width: 2, height: 10).offset(y: -5)
                    Rectangle().frame(width: 2, height: 10).rotationEffect(.degrees(120)).offset(x: 4, y: 3)
                    Rectangle().frame(width: 2, height: 10).rotationEffect(.degrees(-120)).offset(x: -4, y: 3)
                }.foregroundStyle(.white.opacity(0.8))
                Circle().frame(width: 6, height: 6)
                Circle().frame(width: 6, height: 6).offset(y: -10)
                Circle().frame(width: 6, height: 6).offset(x: 8.5, y: 5)
                Circle().frame(width: 6, height: 6).offset(x: -8.5, y: 5)
            }.foregroundStyle(.white).scaleEffect(0.8)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = material; v.blendingMode = blendingMode; v.state = .active; return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material; nsView.blendingMode = blendingMode
    }
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
                    HStack(spacing: 12) {
                        Circle().fill(viewModel.isMirroring ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(viewModel.connectedDeviceName ?? "Cihaz").font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .modifier(GlassNavBarBackground())
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.toggleScreenMirroring()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                
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
                        guard let provider = providers.first else { return false }
                        let _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url = url {
                                Task { @MainActor in
                                    viewModel.sendFile(url: url)
                                }
                            }
                        }
                        return true
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
                        HStack(spacing: 40) {
                            Button(action: { viewModel.sendRemoteInput(x: 0, y: 0, action: "RECENTS") }) {
                                Image(systemName: "square.fill").font(.system(size: 16))
                            }.buttonStyle(.plain)
                            
                            Button(action: { viewModel.sendRemoteInput(x: 0, y: 0, action: "HOME") }) {
                                Image(systemName: "circle.fill").font(.system(size: 20))
                            }.buttonStyle(.plain)
                            
                            Button(action: { viewModel.sendRemoteInput(x: 0, y: 0, action: "BACK") }) {
                                Image(systemName: "triangle.fill").font(.system(size: 16)).rotationEffect(.degrees(-90))
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 32)
                        .modifier(GlassNavBarBackground())
                        
                        if showAccessibilityWarning && !viewModel.isRemoteAccessibilityEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("Kontrollerin çalışması için telefonda 'Synapse' Erişilebilirlik Servisi etkin olmalıdır.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Button(action: { showAccessibilityWarning = false }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .modifier(GlassTintedBackground(cornerRadius: 8, tint: .yellow))
                            .padding(.bottom, 12)
                        }
                    }
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


    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 51 { // Delete / Backspace
            viewModel.sendKeyboardInput(key: "BACKSPACE", type: "SPECIAL")
        } else if event.keyCode == 36 { // Return / Enter
            viewModel.sendKeyboardInput(key: "ENTER", type: "SPECIAL")
        } else if event.keyCode == 49 { // Space
            viewModel.sendKeyboardInput(key: " ", type: "STRING")
        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            viewModel.sendKeyboardInput(key: chars, type: "STRING")
        }
    }
}
