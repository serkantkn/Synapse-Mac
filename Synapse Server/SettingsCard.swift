import SwiftUI

/// Settings page: general, security and known devices, each in its own glass card.
struct SettingsCard: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Genel")
                SettingToggleRow(icon: "power", tint: .synapseBlue,
                                 title: "Otomatik başlat",
                                 detail: "Mac açıldığında arka planda başlar.",
                                 isOn: $settings.launchAtLogin)
                Divider().padding(.leading, 48)
                SettingToggleRow(icon: settings.muteNotifications ? "bell.slash.fill" : "bell.fill",
                                 tint: settings.muteNotifications ? .red : .orange,
                                 title: "Bildirimleri sessize al",
                                 detail: "Gelen çağrı ve mesajlar Mac'te bildirim olarak gösterilmez.",
                                 isOn: $settings.muteNotifications)
            }
        }

        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Güvenlik")
                SettingToggleRow(icon: "lock.shield.fill", tint: .green,
                                 title: "Her bağlantıda PIN iste",
                                 detail: "Daha önce eşleşmiş cihazlar da her seferinde PIN girer.",
                                 isOn: $settings.requirePinForKnownDevices)
            }
        }

        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Bilinen cihazlar")
                if settings.knownDevices.isEmpty {
                    EmptyStateView(icon: "smartphone", title: "Eşleşmiş cihaz yok",
                                   subtitle: "Eşleştiğin telefonlar burada listelenir.")
                } else {
                    let devices = settings.knownDevices.values.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Divider().padding(.leading, 48) }
                        HStack(spacing: 12) {
                            IconTile(systemName: "smartphone", color: .synapseBlue, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.body.weight(.semibold))
                                Text("Son bağlantı: \(device.lastConnectedAt.formatted(.dateTime.day().month().hour().minute().locale(.turkish)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                withAnimation(.smooth) { settings.removeKnownDevice(id: device.id) }
                            } label: {
                                Label("Unut", systemImage: "trash")
                            }
                            .glassButtonStyle()
                            .foregroundStyle(.red)
                            .help("Bu cihazı unut; bir sonraki bağlantıda PIN gerekir")
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased(with: .turkish))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }
}

private struct SettingToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, color: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }
}
