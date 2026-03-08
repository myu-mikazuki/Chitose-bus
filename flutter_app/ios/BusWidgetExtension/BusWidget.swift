import WidgetKit
import SwiftUI

// MARK: - Data model

struct BusWidgetData {
    var nextBusTime: String
    var nextBusDirection: String
    var nextBusDestination: String
    var updatedAt: String

    static let placeholder = BusWidgetData(
        nextBusTime: "--:--",
        nextBusDirection: "千歳駅発",
        nextBusDestination: "大学",
        updatedAt: ""
    )
}

// MARK: - Timeline Provider

struct BusWidgetProvider: TimelineProvider {
    private let appGroupId = "group.com.example.chitoseBus"

    func placeholder(in context: Context) -> BusWidgetEntry {
        BusWidgetEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BusWidgetEntry) -> Void) {
        completion(BusWidgetEntry(date: Date(), data: loadData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BusWidgetEntry>) -> Void) {
        let data = loadData()
        let entry = BusWidgetEntry(date: Date(), data: data)
        // 30分後に再フェッチ
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadData() -> BusWidgetData {
        let defaults = UserDefaults(suiteName: appGroupId)
        return BusWidgetData(
            nextBusTime: defaults?.string(forKey: "nextBusTime") ?? "--:--",
            nextBusDirection: defaults?.string(forKey: "nextBusDirection") ?? "読み込み中...",
            nextBusDestination: defaults?.string(forKey: "nextBusDestination") ?? "",
            updatedAt: formattedTime(from: defaults?.string(forKey: "updatedAt") ?? "")
        )
    }

    private func formattedTime(from isoString: String) -> String {
        guard !isoString.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "HH:mm"
        display.locale = Locale(identifier: "ja_JP")
        display.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return "更新: \(display.string(from: date))"
    }
}

// MARK: - Timeline Entry

struct BusWidgetEntry: TimelineEntry {
    let date: Date
    let data: BusWidgetData
}

// MARK: - Widget View

struct BusWidgetEntryView: View {
    var entry: BusWidgetProvider.Entry

    var body: some View {
        VStack(spacing: 2) {
            Text(entry.data.nextBusDirection)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(Color(red: 0, green: 1, blue: 0.53))
                .tracking(1)

            Text(entry.data.nextBusTime)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            if !entry.data.nextBusDestination.isEmpty {
                Text(entry.data.nextBusDestination)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            if !entry.data.updatedAt.isEmpty {
                Text(entry.data.updatedAt)
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.25))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.07, blue: 0.07))
    }
}

// MARK: - Widget Configuration

struct BusWidget: Widget {
    let kind: String = "BusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BusWidgetProvider()) { entry in
            BusWidgetEntryView(entry: entry)
                .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.07), for: .widget)
        }
        .configurationDisplayName("CISTバスウィジェット")
        .description("次のバスの出発時刻を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    BusWidget()
} timeline: {
    BusWidgetEntry(date: Date(), data: BusWidgetData(
        nextBusTime: "08:45",
        nextBusDirection: "千歳駅発",
        nextBusDestination: "大学",
        updatedAt: ""
    ))
}
