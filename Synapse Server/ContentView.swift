//
//  ContentView.swift
//  Synapse Server
//
//  Main window: native sidebar (a floating glass panel on macOS 26) and glass content pages.
//

import SwiftUI
import AppKit

// MARK: - Navigation

enum SidebarItem: String, Hashable, Identifiable {
    case dashboard, calls, messages, notifications, photos, mirroring
    case pairing, settings

    var id: String { rawValue }

    /// Pages that need a connected phone.
    static let phoneItems: [SidebarItem] = [.dashboard, .calls, .messages, .notifications, .photos, .mirroring]

    var title: String {
        switch self {
        case .dashboard: return "Pano"
        case .calls: return "Çağrılar"
        case .messages: return "Mesajlar"
        case .notifications: return "Bildirimler"
        case .photos: return "Fotoğraflar"
        case .mirroring: return "Ekran Yansıtma"
        case .pairing: return "Eşleşme"
        case .settings: return "Ayarlar"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .calls: return "phone"
        case .messages: return "message"
        case .notifications: return "bell.badge"
        case .photos: return "photo.on.rectangle.angled"
        case .mirroring: return "rectangle.on.rectangle"
        case .pairing: return "link"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject private var viewModel = SynapseViewModel.shared
    @State private var selection: SidebarItem?

    private var isConnected: Bool { viewModel.connectionStatus == .connected }

    /// A phone page needs a phone; fall back while the selection catches up.
    private var currentItem: SidebarItem {
        let item = selection ?? (isConnected ? .dashboard : .pairing)
        if !isConnected && SidebarItem.phoneItems.contains(item) { return .pairing }
        return item
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            DetailView(viewModel: viewModel, item: currentItem)
        }
        .frame(minWidth: 880, minHeight: 600)
        .onAppear {
            if selection == nil { selection = isConnected ? .dashboard : .pairing }
            viewModel.startDiscovery()
        }
        .onChange(of: isConnected) { _, connected in
            if connected, selection == nil || selection == .pairing {
                selection = .dashboard
            } else if !connected, let current = selection, SidebarItem.phoneItems.contains(current) {
                selection = .pairing
            }
        }
        .overlay {
            if viewModel.connectionStatus == .pairing {
                PairingProgressOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: viewModel.connectionStatus)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var viewModel: SynapseViewModel
    @Binding var selection: SidebarItem?

    private var isConnected: Bool { viewModel.connectionStatus == .connected }

    var body: some View {
        List(selection: $selection) {
            if isConnected {
                Section("Telefon") {
                    ForEach(SidebarItem.phoneItems) { item in
                        Label(item.title, systemImage: item.icon)
                            .badge(item == .notifications ? viewModel.notifications.count : 0)
                            .tag(item)
                    }
                }
            } else {
                Section("Bağlantı") {
                    Label(SidebarItem.pairing.title, systemImage: SidebarItem.pairing.icon)
                        .tag(SidebarItem.pairing)
                }
            }
            Section("Synapse") {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.icon)
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarBrandHeader(status: viewModel.connectionStatus)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isConnected {
                SidebarDeviceFooter(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: isConnected)
    }
}

struct SidebarBrandHeader: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 10) {
            SynapseMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Synapse").font(.headline)
                HStack(spacing: 5) {
                    StatusDot(color: status.tint, size: 6)
                    Text(status.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct SidebarDeviceFooter: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "smartphone")
                    .font(.title2)
                    .foregroundStyle(.synapseGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.connectedDeviceName ?? "Android cihaz")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let battery = viewModel.batteryLevel {
                        Label("%\(battery)", systemImage: batterySymbol(battery))
                            .font(.caption)
                            .foregroundStyle(battery > 20 ? Color.secondary : Color.red)
                    }
                }
                Spacer(minLength: 0)
            }
            Button(role: .destructive) {
                viewModel.disconnect()
            } label: {
                Label("Bağlantıyı Kes", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
            .controlSize(.large)
            .foregroundStyle(.red)
        }
        .padding(14)
        .insetRow(cornerRadius: 16)
        .padding(12)
    }
}

func batterySymbol(_ level: Int) -> String {
    switch level {
    case 90...: return "battery.100"
    case 65..<90: return "battery.75"
    case 40..<65: return "battery.50"
    case 15..<40: return "battery.25"
    default: return "battery.0"
    }
}

// MARK: - Detail

struct DetailView: View {
    @ObservedObject var viewModel: SynapseViewModel
    let item: SidebarItem

    var body: some View {
        page
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { AmbientBackground().extendsUnderSidebar() }
            .navigationTitle(item.title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbarContent }
            .sendsDroppedFiles(to: viewModel)
    }

    @ViewBuilder
    private var page: some View {
        switch item {
        case .dashboard: PageScroll { DashboardPage(viewModel: viewModel) }
        case .calls: PageScroll { CallsPage(viewModel: viewModel) }
        case .messages: PageScroll { MessagesPage(viewModel: viewModel) }
        case .notifications: PageScroll { NotificationsPage(viewModel: viewModel) }
        case .photos: PhotoLibraryView(viewModel: viewModel)
        case .mirroring: PageScroll { MirroringPage(viewModel: viewModel) }
        case .pairing: PageScroll { PairingPage(viewModel: viewModel) }
        case .settings: PageScroll { SettingsCard() }
        }
    }

    private var subtitle: String {
        switch item {
        case .dashboard, .calls, .messages, .photos, .mirroring:
            return viewModel.connectedDeviceName ?? ""
        case .notifications:
            return viewModel.notifications.isEmpty ? "" : "\(viewModel.notifications.count) bildirim"
        case .pairing:
            return viewModel.connectionStatus.title
        case .settings:
            return ""
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.connectionStatus == .connected {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.toggleFindPhone()
                } label: {
                    Label(viewModel.isFindingPhone ? "Çalmayı Durdur" : "Telefonu Bul",
                          systemImage: viewModel.isFindingPhone ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        .symbolEffect(.variableColor.iterative, isActive: viewModel.isFindingPhone)
                }
                .foregroundStyle(viewModel.isFindingPhone ? Color.red : Color.primary)
                .help(viewModel.isFindingPhone ? "Telefonun çalmasını durdur" : "Telefonu sessizde bile çaldır")

                Button {
                    viewModel.pickAndSendFile()
                } label: {
                    Label("Dosya Gönder", systemImage: "doc.badge.arrow.up")
                }
                .help("Telefona dosya gönder")

                Button {
                    viewModel.sendClipboardLinkToPhone()
                } label: {
                    Label("Linki Gönder", systemImage: "link")
                }
                .help("Panodaki linki telefonda aç")
            }
        }
    }
}

/// Scrollable, width-limited column for the content pages.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) { content }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Dashboard

struct DashboardPage: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        DeviceHeroCard(viewModel: viewModel)

        GlassGroup(spacing: 14) {
            HStack(spacing: 14) {
                StatTile(title: "Son arama", value: viewModel.calls.first?.number ?? "—",
                         icon: "phone.fill", tint: .green)
                StatTile(title: "Son mesaj", value: viewModel.messages.first?.sender ?? "—",
                         icon: "message.fill", tint: .synapseBlue)
                StatTile(title: "Bildirim", value: "\(viewModel.notifications.count)",
                         icon: "bell.badge.fill", tint: .orange)
            }
        }

        if viewModel.media != nil {
            GlassCard(padding: 6) { NowPlayingCard(viewModel: viewModel) }
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        SendToPhoneCard(viewModel: viewModel)
        ClipboardSyncCard(viewModel: viewModel)
    }
}

struct DeviceHeroCard: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        GlassCard(cornerRadius: 26, padding: 24) {
            HStack(spacing: 28) {
                PhoneMockup(wallpaper: viewModel.deviceWallpaper)

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.connectedDeviceName ?? "Android cihaz")
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusDot(color: .green)
                        Text("Bağlı · uçtan uca şifreli")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let battery = viewModel.batteryLevel {
                            MetricChip(icon: batterySymbol(battery), text: "%\(battery)",
                                       tint: battery > 20 ? .green : .red)
                        }
                        MetricChip(icon: "doc.on.clipboard",
                                   text: viewModel.isClipboardSyncEnabled ? "Pano eşitleniyor" : "Pano kapalı",
                                   tint: .synapseCyan)
                        if viewModel.isFindingPhone {
                            MetricChip(icon: "speaker.wave.3.fill", text: "Çalıyor", tint: .red)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct PhoneMockup: View {
    let wallpaper: NSImage?
    var width: CGFloat = 96

    var body: some View {
        let height = width * 2.05
        let shape = RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
        ZStack(alignment: .top) {
            Group {
                if let wallpaper {
                    Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [.synapseCyan.opacity(0.6), .synapseBlue.opacity(0.6), .synapseIndigo.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: width, height: height)
            .clipShape(shape)

            Capsule()
                .fill(.black)
                .frame(width: width * 0.3, height: width * 0.085)
                .padding(.top, width * 0.06)
        }
        .overlay { shape.stroke(Color.white.opacity(0.35), lineWidth: 2.5) }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
        .accessibilityHidden(true)
    }
}

struct MetricChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconTile(systemName: icon, color: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.semibold)).lineLimit(1)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SendToPhoneCard: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    IconTile(systemName: "arrow.down.doc.fill", color: .synapseBlue, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telefona dosya gönder").font(.headline)
                        Text("Dosyaları bu pencereye sürükleyip bırak ya da seç.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Dosya Seç…") { viewModel.pickAndSendFile() }
                        .glassButtonStyle()
                        .controlSize(.large)
                }
                TransferMessageBanner(viewModel: viewModel)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.transferMessage)
        }
    }
}

// MARK: - Clipboard

struct ClipboardSyncCard: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Pano Senkronizasyonu", icon: "doc.on.clipboard", tint: .synapseCyan) {
                    Toggle("Pano senkronizasyonu", isOn: $viewModel.isClipboardSyncEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if !viewModel.lastSentClipboard.isEmpty {
                    ClipboardItemView(direction: "Gönderilen", content: viewModel.lastSentClipboard,
                                      icon: "arrow.up.circle.fill", color: .green)
                }
                if let received = viewModel.lastReceivedClipboard {
                    ClipboardItemView(direction: "Alınan", content: received,
                                      icon: "arrow.down.circle.fill", color: .synapseBlue)
                }
                if viewModel.lastSentClipboard.isEmpty && viewModel.lastReceivedClipboard == nil {
                    Text("Bir metin kopyaladığında telefona otomatik gönderilir.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ClipboardItemView: View {
    let direction: String
    let content: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(direction).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(content).font(.callout).lineLimit(3).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .insetRow()
    }
}

// MARK: - Calls

struct CallsPage: View {
    @ObservedObject var viewModel: SynapseViewModel
    @State private var numberToCall = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone")
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            TextField("Numara yaz", text: $numberToCall)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit(call)
            Button(action: call) {
                Label("Ara", systemImage: "phone.fill")
                    .padding(.horizontal, 6)
            }
            .glassButtonStyle(prominent: true)
            .tint(.green)
            .controlSize(.large)
            .disabled(numberToCall.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
        .glassSurface(in: Capsule())

        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Arama Geçmişi", icon: "clock.fill", tint: .green)
                if viewModel.calls.isEmpty {
                    EmptyStateView(icon: "phone.badge.plus", title: "Arama kaydı yok",
                                   subtitle: "Telefona gelen aramalar burada görünür.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.calls.enumerated()), id: \.element.id) { index, call in
                            if index > 0 { Divider().padding(.leading, 50) }
                            CallRow(call: call) { viewModel.sendCall(number: call.number) }
                        }
                    }
                }
            }
        }
    }

    private func call() {
        let number = numberToCall.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return }
        viewModel.sendCall(number: number)
        numberToCall = ""
    }
}

struct CallRow: View {
    let call: CallRecord
    let callBack: () -> Void

    private var isRinging: Bool { call.state == "RINGING" }

    private var stateText: String {
        switch call.state {
        case "RINGING": return "Gelen arama"
        case "OFFHOOK": return "Görüşmede"
        case "IDLE": return "Sona erdi"
        default: return call.state
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: isRinging ? "phone.arrow.down.left.fill" : "phone.fill",
                     color: isRinging ? .synapseBlue : .green, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.number).font(.body.weight(.semibold)).monospacedDigit()
                Text(stateText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(call.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
            Button(action: callBack) {
                Image(systemName: "phone.fill")
            }
            .glassButtonStyle()
            .tint(.green)
            .help("Geri ara")
            .accessibilityLabel("Geri ara")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Messages

struct MessagesPage: View {
    @ObservedObject var viewModel: SynapseViewModel
    @State private var number = ""
    @State private var messageBody = ""

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Yeni Mesaj", icon: "square.and.pencil", tint: .synapseBlue)
                TextField("Alıcı numarası", text: $number)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .insetRow(cornerRadius: 10)
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Mesaj yaz…", text: $messageBody, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .insetRow(cornerRadius: 10)
                    Button {
                        viewModel.sendSms(number: number, body: messageBody)
                        messageBody = ""
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .disabled(number.isEmpty || messageBody.isEmpty)
                    .help("Gönder")
                    .accessibilityLabel("Gönder")
                }
            }
        }

        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Mesajlar", icon: "message.fill", tint: .synapseBlue)
                if viewModel.messages.isEmpty {
                    EmptyStateView(icon: "message", title: "Mesaj yok",
                                   subtitle: "Telefona gelen SMS'ler burada görünür.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            if index > 0 { Divider().padding(.leading, 52) }
                            MessageRow(message: message) { number = message.sender }
                        }
                    }
                }
            }
        }
    }
}

struct MessageRow: View {
    let message: SmsRecord
    let reply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InitialsAvatar(name: message.sender, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.sender).font(.body.weight(.semibold))
                    Spacer()
                    Text(message.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Button("Yanıtla", action: reply)
                    .buttonStyle(.link)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 10)
    }
}

struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 38

    private static let palettes: [[Color]] = [
        [.synapseCyan, .synapseBlue], [.synapseBlue, .synapseIndigo], [.purple, .pink],
        [.orange, .pink], [.mint, .teal], [.indigo, .purple]
    ]

    var body: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        let initials = letters.isEmpty || name.first?.isNumber == true ? "#" : String(letters).uppercased(with: .turkish)
        // Stable across launches (String.hashValue is not).
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let colors = Self.palettes[seed % Self.palettes.count]
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Notifications

struct NotificationsPage: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        if viewModel.notifications.isEmpty {
            GlassCard {
                EmptyStateView(icon: "bell.slash", title: "Henüz bildirim yok",
                               subtitle: "Android cihazından gelen bildirimler burada görünür.")
            }
        } else {
            HStack {
                Text("En yeni üstte")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Tümünü Temizle") {
                    withAnimation(.smooth) { viewModel.notifications.removeAll() }
                }
                .glassButtonStyle()
            }
            LazyVStack(spacing: 10) {
                ForEach(viewModel.notifications) { notification in
                    NotificationRow(notification: notification, viewModel: viewModel)
                }
            }
        }
    }
}

struct NotificationRow: View {
    let notification: NotificationRecord
    @ObservedObject var viewModel: SynapseViewModel
    @State private var showReply = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let icon = notification.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.badge.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.accentColor.opacity(0.15))
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notification.appName.uppercased(with: .turkish))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(notification.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !notification.title.isEmpty {
                    Text(notification.title).font(.body.weight(.semibold)).lineLimit(1)
                }
                if !notification.body.isEmpty {
                    Text(notification.body).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                if viewModel.replyStatus[notification.key] == .sent {
                    Label("Yanıtlandı", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                } else if notification.canReply {
                    if showReply {
                        NotificationReplyField(viewModel: viewModel, notificationKey: notification.key)
                            .padding(.top, 6)
                    } else {
                        Button {
                            withAnimation(.smooth) { showReply = true }
                        } label: {
                            Label("Yanıtla", systemImage: "arrowshape.turn.up.left.fill")
                        }
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Screen mirroring

struct MirroringPage: View {
    @ObservedObject var viewModel: SynapseViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassCard(cornerRadius: 26, padding: 36) {
            VStack(spacing: 20) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.synapseGradient)
                    .frame(width: 112, height: 112)
                    .glassSurface(in: Circle(), tint: Color.synapseBlue.opacity(0.1))
                VStack(spacing: 8) {
                    Text("Telefon ekranını yansıt").font(.title2.bold())
                    Text("Telefonun ekranı ayrı bir pencerede açılır. Pencereyi istediğin yere taşıyabilir, fare ve klavyeyle telefonu kontrol edebilirsin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                Button {
                    if !viewModel.isMirroring { viewModel.toggleScreenMirroring() }
                    openWindow(id: "mirroring")
                } label: {
                    Label(viewModel.isMirroring ? "Pencereyi Göster" : "Yansıtmayı Başlat",
                          systemImage: "arrow.up.forward.app.fill")
                        .padding(.horizontal, 8)
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.extraLarge)
            }
            .frame(maxWidth: .infinity)
        }

        GlassCard {
            HStack(spacing: 14) {
                IconTile(systemName: viewModel.isRemoteAccessibilityEnabled ? "hand.tap.fill" : "exclamationmark.triangle.fill",
                         color: viewModel.isRemoteAccessibilityEnabled ? .green : .yellow, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isRemoteAccessibilityEnabled ? "Uzaktan kontrol hazır" : "Uzaktan kontrol kapalı")
                        .font(.headline)
                    Text("Dokunma ve klavye için telefonda Synapse erişilebilirlik servisi açık olmalı.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Pairing

struct PairingPage: View {
    @ObservedObject var viewModel: SynapseViewModel

    var body: some View {
        GlassCard(cornerRadius: 26, padding: 28) {
            HStack(alignment: .center, spacing: 32) {
                if !viewModel.qrCodeString.isEmpty {
                    QRCodeView(content: viewModel.qrCodeString)
                        .frame(width: 176, height: 176)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                        .accessibilityLabel("Eşleşme QR kodu")
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Telefonunu bağla").font(.title2.bold())
                            if viewModel.connectionStatus == .discovering {
                                ProgressView().controlSize(.small)
                            }
                        }
                        Text("Android'de Synapse'i aç, MacBook'u seç ve QR kodu tara ya da PIN'i gir.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !viewModel.pairingCode.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PIN KODU").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            PinCodeView(code: viewModel.pairingCode)
                        }
                    }

                    HStack(spacing: 8) {
                        MetricChip(icon: "network", text: viewModel.getIPAddress(), tint: .synapseBlue)
                        MetricChip(icon: "lock.fill", text: "Uçtan uca şifreli", tint: .green)
                    }
                }
                Spacer(minLength: 0)
            }
        }

        if case .error(let message) = viewModel.connectionStatus {
            GlassCard {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }

        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Nasıl bağlanır?").font(.headline)
                StepRow(number: 1, title: "Android'de Synapse'i aç", detail: "\"MacBook\" seçeneğine dokun.")
                StepRow(number: 2, title: "QR kodu tara ya da PIN'i gir", detail: "Telefon bu Mac'i yerel ağda bulur.")
                StepRow(number: 3, title: "Hazır", detail: "Sonraki bağlantılarda PIN sorulmaz.")
            }
        }
    }
}

/// Six digits in two groups of three, like a verification code.
struct PinCodeView: View {
    let code: String

    var body: some View {
        let digits = Array(code)
        HStack(spacing: 12) {
            digitGroup(digits.prefix(3))
            digitGroup(digits.dropFirst(3))
        }
        .accessibilityElement()
        .accessibilityLabel("PIN kodu \(digits.map(String.init).joined(separator: " "))")
    }

    private func digitGroup(_ digits: ArraySlice<Character>) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(width: 38, height: 48)
                    .insetRow(cornerRadius: 10)
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.synapseGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PairingProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Eşleşme tamamlanıyor…").font(.headline)
                Text("Güvenli bağlantı kuruluyor").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(36)
            .glassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Utility

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
