//
//  Synapse_ServerApp.swift
//  Synapse Server
//

import SwiftUI
import AppKit
import Combine

@main
struct Synapse_ServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var viewModel = SynapseViewModel.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        WindowGroup(id: "mirroring") {
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
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
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
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
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
                Circle().fill(color.opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundStyle(color)
            }
            Text("\(count)").font(.system(size: 16, weight: .bold))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
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
                    .background(.ultraThinMaterial, in: Capsule())
                    
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
                                        let x = Double(value.startLocation.x / geo.size.width)
                                        let y = Double(value.startLocation.y / geo.size.height)
                                        
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
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Görüntü Bekleniyor...")
                            .font(.headline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if viewModel.isMirroring {
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
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 640)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .onDisappear {
            // Stop mirroring process when the window is closed
            if viewModel.isMirroring {
                viewModel.toggleScreenMirroring()
            }
        }
    }
}
