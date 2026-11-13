import WidgetKit
import SwiftUI

struct SynapseEntry: TimelineEntry {
    let date: Date
    let deviceName: String
    let isConnected: Bool
    let batteryLevel: Int
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SynapseEntry {
        SynapseEntry(date: Date(), deviceName: "Android Cihaz", isConnected: true, batteryLevel: 85)
    }

    func getSnapshot(in context: Context, completion: @escaping (SynapseEntry) -> ()) {
        let entry = readData()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = readData()
        // App'ten tetikleme geldiğinde güncellenmesi için policy .never olarak ayarlandı
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }

    private func readData() -> SynapseEntry {
        let suiteName = "group.com.serkantkn.Synapse-Server"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return SynapseEntry(date: Date(), deviceName: "Yetki Yok", isConnected: false, batteryLevel: 0)
        }
        
        defaults.synchronize() // Force read from disk
        
        let deviceName = defaults.string(forKey: "deviceName") ?? "Bağlantı Yok ⏳"
        let isConnected = defaults.bool(forKey: "isConnected")
        let batteryLevel = defaults.integer(forKey: "batteryLevel")
        
        return SynapseEntry(
            date: Date(),
            deviceName: deviceName,
            isConnected: isConnected,
            batteryLevel: batteryLevel
        )
    }
}

struct SynapseWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(entry.isConnected ? .cyan : .gray.opacity(0.6))
                    .font(.system(size: 14, weight: .semibold))
                Text("Synapse")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                Spacer()
                if entry.isConnected {
                    Circle().fill(Color.green.gradient)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.6), radius: 4)
                }
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.deviceName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if entry.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(level: entry.batteryLevel))
                            .foregroundStyle(batteryColor(level: entry.batteryLevel).gradient)
                            .font(.system(size: 12))
                        Text("%\(entry.batteryLevel)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Bağlantı Kesildi")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
        }
        .padding(14)
        .containerBackground(.regularMaterial, for: .widget)
    }
    
    func batteryIcon(level: Int) -> String {
        if level >= 90 { return "battery.100" }
        if level >= 65 { return "battery.75" }
        if level >= 40 { return "battery.50" }
        if level >= 15 { return "battery.25" }
        return "battery.0"
    }
    
    func batteryColor(level: Int) -> Color {
        if level >= 20 { return .green }
        return .red
    }
}

@main
struct SynapseWidget: Widget {
    let kind: String = "SynapseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SynapseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Synapse Durumu")
        .description("Android cihazınızın bağlantı ve pil durumunu masaüstünden takip edin.")
        .supportedFamilies([.systemSmall])
    }
}
