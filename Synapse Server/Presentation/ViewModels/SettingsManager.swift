import Foundation
import SwiftUI
import Combine
import ServiceManagement

/// Model to hold a known device's information
struct KnownDevice: Codable, Identifiable, Hashable {
    var id: String // Same as senderId
    var name: String
    var lastConnectedAt: Date
    /// Only read to migrate tokens saved by older builds; tokens now live in the Keychain
    /// (see PairingTokenStore).
    var token: String? = nil
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var requirePinForKnownDevices: Bool
    @Published var muteNotifications: Bool
    @Published var knownDevices: [String: KnownDevice]
    @Published var launchAtLogin: Bool
    
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.requirePinForKnownDevices = UserDefaults.standard.bool(forKey: "requirePinForKnownDevices")
        self.muteNotifications = UserDefaults.standard.bool(forKey: "muteNotifications")
        
        // Migrate from old set to new dict if needed
        if let data = UserDefaults.standard.data(forKey: "knownDevicesDict"),
           let decoded = try? JSONDecoder().decode([String: KnownDevice].self, from: data) {
            self.knownDevices = decoded
        } else {
            // Check if there's old set data
            let oldSet = Set(UserDefaults.standard.stringArray(forKey: "knownDeviceIds") ?? [])
            var migrated = [String: KnownDevice]()
            for id in oldSet {
                migrated[id] = KnownDevice(id: id, name: "Bilinmeyen Cihaz", lastConnectedAt: Date())
            }
            self.knownDevices = migrated
        }

        // Initialize launch at login
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        }

        migrateLegacyTokens()
        pruneOrphanTokens()
        setupSubscriptions()
    }

    /// Earlier builds kept tokens inside knownDevicesDict; move them to the Keychain.
    private func migrateLegacyTokens() {
        guard knownDevices.values.contains(where: { $0.token != nil }) else { return }
        for (id, device) in knownDevices {
            guard let token = device.token, PairingTokenStore.set(token, for: id) else { continue }
            knownDevices[id]?.token = nil
        }
        if let encoded = try? JSONEncoder().encode(knownDevices) {
            UserDefaults.standard.set(encoded, forKey: "knownDevicesDict")
        }
    }

    /// Tokens whose device is no longer in the known list (e.g. prefs were reset) must not keep working.
    private func pruneOrphanTokens() {
        for id in PairingTokenStore.allDeviceIds() where knownDevices[id] == nil {
            PairingTokenStore.remove(id)
        }
    }
    
    private func setupSubscriptions() {
        $requirePinForKnownDevices
            .dropFirst()
            .sink { newValue in
                UserDefaults.standard.set(newValue, forKey: "requirePinForKnownDevices")
            }
            .store(in: &cancellables)
            
        $muteNotifications
            .dropFirst()
            .sink { newValue in
                UserDefaults.standard.set(newValue, forKey: "muteNotifications")
            }
            .store(in: &cancellables)
            
        $knownDevices
            .dropFirst()
            .sink { newValue in
                if let encoded = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(encoded, forKey: "knownDevicesDict")
                }
            }
            .store(in: &cancellables)
            
        $launchAtLogin
            .dropFirst()
            .sink { [weak self] newValue in
                self?.toggleLaunchAtLogin(enabled: newValue)
                UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            }
            .store(in: &cancellables)
    }

    /// Saves/updates a device. A nil `token` keeps the one already stored (in the Keychain).
    func addKnownDevice(id: String, name: String, token: String? = nil) {
        if let token = token { PairingTokenStore.set(token, for: id) }
        knownDevices[id] = KnownDevice(id: id, name: name, lastConnectedAt: Date())
    }

    func pairingToken(for id: String) -> String? {
        guard knownDevices[id] != nil else { return nil }
        return PairingTokenStore.get(id)
    }

    func removeKnownDevice(id: String) {
        knownDevices.removeValue(forKey: id)
        PairingTokenStore.remove(id)
    }

    func isDeviceKnown(id: String) -> Bool {
        return knownDevices.keys.contains(id)
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("Launch at login error: \(error.localizedDescription)")
            }
        }
    }
}
