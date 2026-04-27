//
//  ContentView.swift
//  Synapse Server
//
//  Main dashboard — Full Liquid Glass Design Language
//

import SwiftUI
import AppKit

// MARK: - Liquid Glass Design System

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    var body: some View {
        content
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.03), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.7
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

struct GlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
            LinearGradient(colors: [Color(white: 0.12), Color(white: 0.08)], startPoint: .top, endPoint: .bottom).opacity(0.5)
        }.ignoresSafeArea()
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject private var viewModel = SynapseViewModel.shared
    @State private var selection: SidebarSelection = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            DashboardView(viewModel: viewModel, selection: $selection)
                .frame(minWidth: 600, minHeight: 500)
        }
        .onAppear { viewModel.startDiscovery() }
        .sheet(isPresented: $viewModel.showPairingRequest) {
            PairingRequestView(viewModel: viewModel)
        }
        .overlay {
            if viewModel.connectionStatus == .pairing {
                PairingProgressOverlay()
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    SynapseLogoIcon()
                    Text("Synapse")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 24)

                Spacer()

                // Phone Mockup
                if viewModel.connectionStatus == .connected || viewModel.connectionStatus == .connecting {
                    PhoneMockupView(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("Cihaz Bekleniyor")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                }

                Spacer()

                // Disconnect
                if viewModel.connectionStatus == .connected {
                    Button(action: { viewModel.disconnect() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "power")
                            Text("Bağlantıyı Kes")
                        }
                        .fontWeight(.semibold).font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(
                        ZStack {
                            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            Color.red.opacity(0.1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.red.opacity(0.3), lineWidth: 0.6))
                    .foregroundStyle(.red)
                    .padding(20)
                }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @Binding var selection: SidebarSelection

    var body: some View {
        ZStack(alignment: .top) {
            GlassBackground()

            VStack(spacing: 0) {
                if viewModel.connectionStatus == .connected {
                    // Liquid Glass Tab Bar
                    VStack(spacing: 14) {
                        HStack(spacing: 4) {
                            ForEach(SidebarSelection.allCases, id: \.self) { item in
                                GlassTabButton(item: item, isSelected: selection == item) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item }
                                }
                            }
                        }
                        .padding(5)
                        .background(
                            ZStack {
                                VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)
                                    .clipShape(Capsule())
                                Capsule().fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.03), .cyan.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Capsule().stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                            }
                        )
                        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                        .padding(.top, 24)

                        HStack {
                            Text(selection.rawValue)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Spacer()
                        }.padding(.horizontal, 32)
                    }
                    .padding(.bottom, 8)
                    .zIndex(10)
                }

                ScrollView {
                    VStack(spacing: 24) {
                        if viewModel.connectionStatus != .connected {
                            PairingCard(viewModel: viewModel).padding(.top, 50)
                        } else {
                            VStack(spacing: 0) {
                                switch selection {
                                case .dashboard: DashboardMainContent(viewModel: viewModel)
                                case .calls: CallsView(viewModel: viewModel)
                                case .messages: MessagesView(viewModel: viewModel)
                                case .notifications: NotificationsView(viewModel: viewModel)
                                case .mirroring: ScreenMirroringView(viewModel: viewModel)
                                }
                            }.padding(.top, 10)
                        }
                    }.padding(.bottom, 32)
                }
            }
        }
    }
}

// MARK: - Glass Tab Button

struct GlassTabButton: View {
    let item: SidebarSelection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.icon).font(.system(size: 11, weight: .bold))
                Text(item.rawValue).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        ZStack {
                            Capsule().fill(Color.accentColor.opacity(0.15))
                            Capsule().fill(LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phone Mockup

struct PhoneMockupView: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.3), .gray.opacity(0.2), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                    .frame(width: 180, height: 360)
                    .shadow(color: .white.opacity(0.05), radius: 8, x: -2, y: -2)

                ZStack {
                    if let img = viewModel.deviceWallpaper {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 168, height: 348).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    } else {
                        LinearGradient(colors: [.blue.opacity(0.25), .purple.opacity(0.25), .cyan.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: 168, height: 348).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }

                    VStack {
                        Capsule().fill(Color.black).frame(width: 56, height: 16).padding(.top, 8)
                        Spacer()
                    }

                    VStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white)
                            Text(viewModel.connectedDeviceName ?? "Bağlı")
                                .font(.caption2.bold()).foregroundStyle(.white)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 30)
                    }
                }.frame(width: 168, height: 348)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        }
    }
}

// MARK: - Dashboard Main Content

struct DashboardMainContent: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                GlassInfoCard(title: "Son Arama", value: viewModel.calls.first?.number ?? "—", icon: "phone.fill", tint: .green)
                GlassInfoCard(title: "Yeni Mesaj", value: viewModel.messages.first?.sender ?? "—", icon: "message.fill", tint: .blue)
                GlassInfoCard(title: "Bildirimler", value: "\(viewModel.notifications.count)", icon: "bell.fill", tint: .orange)
            }.padding(.horizontal, 32)

            ClipboardSyncCard(viewModel: viewModel)
        }
    }
}

struct GlassInfoCard: View {
    let title: String; let value: String; let icon: String; let tint: Color

    var body: some View {
        GlassCard(cornerRadius: 14) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                    .foregroundStyle(tint.opacity(0.9))
                Text(value).font(.headline.bold()).lineLimit(1)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(16)
        }
    }
}

// MARK: - Pairing Card

struct PairingCard: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        GlassCard(cornerRadius: 24) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 36)).foregroundStyle(.cyan)
                    Text("Cihazınızı Bağlayın")
                        .font(.title2.bold())
                    Text("Android uygulamasından QR kodu tarayın")
                        .foregroundStyle(.secondary).font(.subheadline)
                }

                if !viewModel.qrCodeString.isEmpty {
                    QRCodeView(content: viewModel.qrCodeString)
                        .frame(width: 200, height: 200).padding(12)
                        .background(.white).cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 10)
                }

                if !viewModel.pairingCode.isEmpty {
                    VStack(spacing: 6) {
                        Text("PIN Kodu").font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.pairingCode)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .tracking(8)
                    }

                    GlassCard(cornerRadius: 10) {
                        VStack(spacing: 4) {
                            Text("Yerel IP Adresi").font(.caption2).foregroundStyle(.secondary)
                            Text(viewModel.getIPAddress())
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }.padding(10)
                    }
                }
            }
            .padding(32).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Calls View

struct CallsView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @State private var numberToCall = ""

    var body: some View {
        VStack(spacing: 20) {
            GlassCard(cornerRadius: 14) {
                HStack(spacing: 12) {
                    TextField("Numara Ara veya Gir", text: $numberToCall)
                        .textFieldStyle(.plain).font(.title3).padding(10)
                    Button {
                        viewModel.sendCall(number: numberToCall); numberToCall = ""
                    } label: {
                        Image(systemName: "phone.fill.arrow.up.right")
                            .font(.title3).foregroundStyle(.white)
                            .padding(10).background(Color.green.gradient, in: Circle())
                    }
                    .buttonStyle(.plain).disabled(numberToCall.isEmpty)
                }.padding(8)
            }

            GlassCard(cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Arama Geçmişi", systemImage: "clock.fill")
                        .font(.headline).padding(.horizontal, 4)

                    if viewModel.calls.isEmpty {
                        GlassEmptyState(icon: "phone.badge.plus", title: "Arama Kaydı Yok")
                    } else {
                        ForEach(viewModel.calls) { call in
                            GlassListRow {
                                HStack(spacing: 12) {
                                    Image(systemName: call.state == "RINGING" ? "phone.arrow.down.left.fill" : "phone.fill")
                                        .foregroundStyle(call.state == "RINGING" ? .blue : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(call.number).font(.subheadline.bold())
                                        Text(call.state).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(call.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                                    Button { viewModel.sendCall(number: call.number) } label: {
                                        Image(systemName: "phone.fill").foregroundStyle(.green)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.padding(16)
            }
        }.padding(.horizontal, 32)
    }
}

// MARK: - Messages View

struct MessagesView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @State private var number = ""
    @State private var messageBody = ""

    var body: some View {
        VStack(spacing: 20) {
            GlassCard(cornerRadius: 14) {
                VStack(spacing: 12) {
                    TextField("Numara", text: $number)
                        .textFieldStyle(.plain).padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 8) {
                        TextField("Mesaj yazın...", text: $messageBody)
                            .textFieldStyle(.plain).padding(8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        Button {
                            viewModel.sendSms(number: number, body: messageBody); messageBody = ""
                        } label: {
                            Image(systemName: "paperplane.fill").foregroundStyle(.white)
                                .padding(10).background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain).disabled(number.isEmpty || messageBody.isEmpty)
                    }
                }.padding(14)
            }

            GlassCard(cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Mesajlar", systemImage: "message.fill").font(.headline).padding(.horizontal, 4)

                    if viewModel.messages.isEmpty {
                        GlassEmptyState(icon: "message.badge.filled.fill", title: "Mesaj Yok")
                    } else {
                        ForEach(viewModel.messages) { msg in
                            GlassListRow {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(msg.sender).font(.subheadline.bold()).foregroundStyle(.cyan)
                                        Spacer()
                                        Text(msg.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(msg.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                    Button("Yanıtla") { number = msg.sender }.buttonStyle(.link).font(.caption)
                                }
                            }
                        }
                    }
                }.padding(16)
            }
        }.padding(.horizontal, 32)
    }
}

// MARK: - Notifications View

struct NotificationsView: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Bildirimler", systemImage: "bell.fill").font(.title3.bold())
                Spacer()
                if !viewModel.notifications.isEmpty {
                    Button("Temizle") { viewModel.notifications.removeAll() }
                        .buttonStyle(.borderless).foregroundColor(.secondary).font(.caption)
                }
            }.padding(.horizontal, 32)

            if viewModel.notifications.isEmpty {
                Spacer()
                GlassEmptyState(icon: "bell.slash", title: "Henüz bildirim yok", subtitle: "Android cihazınızdan gelen bildirimler burada görünecek")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.notifications) { notif in
                            NotificationRow(notification: notif)
                        }
                    }.padding(.horizontal, 32)
                }
            }
        }.padding(.vertical)
    }
}

struct NotificationRow: View {
    let notification: NotificationRecord

    var body: some View {
        GlassCard(cornerRadius: 12) {
            HStack(spacing: 12) {
                if let icon = notification.icon {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                        .overlay(Image(systemName: "app.fill").foregroundColor(.accentColor).font(.caption))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(notification.appName).font(.caption).foregroundStyle(.cyan).fontWeight(.semibold)
                        Spacer()
                        Text(notification.timestamp, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !notification.title.isEmpty { Text(notification.title).font(.subheadline.bold()).lineLimit(1) }
                    if !notification.body.isEmpty { Text(notification.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                }
            }.padding(12)
        }
    }
}

// MARK: - Clipboard Sync Card

struct ClipboardSyncCard: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Pano Senkronizasyonu", systemImage: "doc.on.clipboard").font(.headline)

                if !viewModel.lastSentClipboard.isEmpty {
                    ClipboardItemView(direction: "Gönderilen", content: viewModel.lastSentClipboard, icon: "arrow.up.circle.fill", color: .green)
                }
                if let received = viewModel.lastReceivedClipboard {
                    ClipboardItemView(direction: "Alınan", content: received, icon: "arrow.down.circle.fill", color: .blue)
                }
                if viewModel.lastSentClipboard.isEmpty && viewModel.lastReceivedClipboard == nil {
                    Text("Bir metin kopyaladığınızda otomatik olarak senkronize edilecek")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }.padding(.horizontal, 32)
    }
}

struct ClipboardItemView: View {
    let direction: String; let content: String; let icon: String; let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(direction).font(.caption.bold()).foregroundStyle(color)
                Text(content).font(.callout).lineLimit(3)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Shared Glass Components

struct GlassListRow<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.4))
    }
}

struct GlassEmptyState: View {
    let icon: String; let title: String; var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary.opacity(0.4))
            Text(title).font(.headline).foregroundStyle(.secondary)
            if let sub = subtitle { Text(sub).font(.subheadline).foregroundStyle(.secondary.opacity(0.6)) }
        }.padding(40)
    }
}

// MARK: - Pairing Request View

struct PairingRequestView: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "iphone.badge.plus")
                        .font(.system(size: 48)).foregroundStyle(.cyan)
                    Text("Bağlantı İsteği")
                        .font(.title.bold())
                    Text("\(viewModel.incomingPairingPacket?.payload["device_name"]?.value as? String ?? "Android Cihaz") bağlanmak istiyor")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                if let code = viewModel.incomingPairingPacket?.payload["pairing_code"]?.value as? String {
                    VStack(spacing: 8) {
                        Text("Cihazdaki PIN ile eşleştiğinden emin olun")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .tracking(10)
                            .padding(.vertical, 12).padding(.horizontal, 24)
                            .background(Color.white.opacity(0.05)).cornerRadius(12)
                    }
                }

                HStack(spacing: 20) {
                    Button(action: { viewModel.rejectPairing() }) {
                        Text("Reddet")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1)).cornerRadius(12)
                    }
                    .buttonStyle(.plain).foregroundStyle(.red)

                    Button(action: { viewModel.acceptPairing() }) {
                        Text("Onayla ve Bağlan")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)).cornerRadius(12)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                }
            }
            .padding(40)
            .frame(width: 400, height: 450)
        }
    }
}

struct PairingProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                Text("Eşleşme Tamamlanıyor...")
                    .font(.headline).foregroundStyle(.secondary)
            }
            .padding(40)
            .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 20)
        }
    }
}

// MARK: - Enums

enum SidebarSelection: String, CaseIterable {
    case dashboard = "Pano"
    case calls = "Çağrılar"
    case messages = "Mesajlar"
    case notifications = "Bildirimler"
    case mirroring = "Ekran"

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .calls: return "phone.fill"
        case .messages: return "message.fill"
        case .notifications: return "bell.fill"
        case .mirroring: return "macwindow"
        }
    }
}

// MARK: - Screen Mirroring View

struct ScreenMirroringView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 20) {
            GlassCard(cornerRadius: 24) {
                VStack(spacing: 24) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    
                    VStack(spacing: 12) {
                        Text("Ayrı Pencerede İzle")
                            .font(.title2.bold())
                        Text("Telefon ekranını ayrı bir pencerede açarak Mac'inizin istediğiniz yerine konumlandırabilirsiniz.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }

                    Button(action: { 
                        if !viewModel.isMirroring {
                            viewModel.toggleScreenMirroring()
                        }
                        openWindow(id: "mirroring")
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text("Pencereyi Aç")
                        }
                        .font(.headline)
                        .padding(.horizontal, 32).padding(.vertical, 16)
                        .background(Color.accentColor.gradient)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            
            GlassInfoCard(title: "İpucu", value: "Pencereyi dilediğiniz gibi boyutlandırabilir veya her zaman üstte kalacak şekilde ayarlayabilirsiniz.", icon: "lightbulb.fill", tint: .yellow)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Utility Views

struct QRCodeView: View {
    let content: String
    private let context = CIContext()
    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(nsImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "qrcode").resizable().foregroundStyle(.secondary)
        }
    }
    private func generateQRCode(from string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        if let output = filter.outputImage, let cg = context.createCGImage(output, from: output.extent) {
            return NSImage(cgImage: cg, size: NSSize(width: 200, height: 200))
        }
        return nil
    }
}

#Preview { ContentView() }

#Preview { ContentView() }
