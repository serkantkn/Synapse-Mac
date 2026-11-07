import Foundation
import SwiftUI
import Combine
import ServiceManagement

/// Model to hold a known device's information
struct KnownDevice: Codable, Identifiable, Hashable {
    var id: String // Same as senderId
    var name: String
    var lastConnectedAt: Date
    /// Pairing token derived at the first PIN pairing; nil for entries saved by older versions,
    /// which then have to pair with the PIN again.
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
        
        setupSubscriptions()
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

    /// Saves/updates a device. A nil `token` keeps the one already stored.
    func addKnownDevice(id: String, name: String, token: String? = nil) {
        let existingToken = knownDevices[id]?.token
        knownDevices[id] = KnownDevice(id: id, name: name, lastConnectedAt: Date(), token: token ?? existingToken)
    }

    func pairingToken(for id: String) -> String? {
        return knownDevices[id]?.token
    }

    func removeKnownDevice(id: String) {
        knownDevices.removeValue(forKey: id)
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
