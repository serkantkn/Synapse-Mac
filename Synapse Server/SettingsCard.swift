import SwiftUI

struct SettingsCard: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.cyan)
                    Text("Ayarlar")
                        .font(.title2.bold())
                }
                .padding(.bottom, 8)

                // Genel Ayarlar
                VStack(alignment: .leading, spacing: 16) {
                    Text("Genel").font(.subheadline.bold()).foregroundStyle(.secondary)
                    
                    Toggle(isOn: $settings.launchAtLogin) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Otomatik Başlat")
                                Text("Mac açıldığında arka planda otomatik olarak başlar.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "macwindow.badge.plus").foregroundStyle(.blue)
                        }
                    }
                    .toggleStyle(.switch).tint(.cyan)

                    Toggle(isOn: $settings.muteNotifications) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bildirimleri Sessize Al")
                                Text("Gelen çağrı ve mesaj bildirimlerini Mac'te gösterme.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: settings.muteNotifications ? "bell.slash.fill" : "bell.fill")
                                .foregroundStyle(settings.muteNotifications ? .red : .green)
                        }
                    }
                    .toggleStyle(.switch).tint(.cyan)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(GlassRowBackground(cornerRadius: 14))

                // Güvenlik Ayarları
                VStack(alignment: .leading, spacing: 16) {
                    Text("Güvenlik").font(.subheadline.bold()).foregroundStyle(.secondary)
                    
                    Toggle(isOn: $settings.requirePinForKnownDevices) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Otomatik Eşleşmeyi Kapat")
                                Text("Bilinen cihazlar bile her bağlandığında PIN girmek zorunda kalsın.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                        }
                    }
                    .toggleStyle(.switch).tint(.cyan)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(GlassRowBackground(cornerRadius: 14))

                // Bilinen Cihazlar
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bilinen Cihazlar").font(.subheadline.bold()).foregroundStyle(.secondary)
                    
                    if settings.knownDevices.isEmpty {
                        GlassEmptyState(icon: "memorychip", title: "Cihaz Bulunamadı", subtitle: "Daha önce eşleştiğiniz cihazlar burada listelenir.")
                    } else {
                        ForEach(Array(settings.knownDevices.values), id: \.id) { device in
                            HStack {
                                Image(systemName: "candybarphone").font(.title3).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).font(.headline)
                                    Text("Son Bağlantı: \(device.lastConnectedAt.formatted(.dateTime.day().month().hour().minute()))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    withAnimation { settings.removeKnownDevice(id: device.id) }
                                } label: {
                                    Image(systemName: "trash.fill").foregroundStyle(.red.opacity(0.8))
                                        .padding(8).background(Color.red.opacity(0.1), in: Circle())
                                }.buttonStyle(.plain)
                            }
                            .padding(12)
                            .modifier(GlassRowBackground(cornerRadius: 10))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(GlassRowBackground(cornerRadius: 14))
            }
            .padding(32).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
    }
}
