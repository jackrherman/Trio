import Foundation
import SwiftUI
import WidgetKit

private struct TrioHomeWidgetEntry: TimelineEntry {
    let date: Date
    let context: LiveActivityViewContext?
}

private struct TrioHomeWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioHomeWidgetEntry {
        TrioHomeWidgetEntry(date: .now, context: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioHomeWidgetEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioHomeWidgetEntry>) -> Void) {
        let entry = makeEntry(at: .now)
        let policy: TimelineReloadPolicy

        if let glucoseDate = entry.context?.state.latestGlucoseDate {
            let freshnessAnchor = min(glucoseDate, entry.date)
            policy = freshnessAnchor > entry.date.addingTimeInterval(-360)
                ? .after(freshnessAnchor.addingTimeInterval(360))
                : .never
        } else {
            policy = .never
        }

        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry(at date: Date) -> TrioHomeWidgetEntry {
        guard let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: LiveActivityAttributes.homeWidgetSnapshotKey),
              let state = try? JSONDecoder().decode(LiveActivityAttributes.ContentState.self, from: data)
        else {
            return TrioHomeWidgetEntry(date: date, context: nil)
        }

        let isStale = state.latestGlucoseDate
            .map { min($0, date) <= date.addingTimeInterval(-360) } ?? true
        return TrioHomeWidgetEntry(
            date: date,
            context: LiveActivityViewContext(state: state, isStale: isStale)
        )
    }
}

struct TrioHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LiveActivityAttributes.homeWidgetKind, provider: TrioHomeWidgetProvider()) { entry in
            Group {
                if let context = entry.context {
                    LiveActivityView(context: context, isHomeWidget: true)
                } else {
                    VStack(spacing: 6) {
                        Text("No glucose data")
                            .font(.headline)
                        Text("Open Trio to refresh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .containerBackground(BackgroundStyle.background.opacity(0.4), for: .widget)
                }
            }
            .widgetURL(widgetURL)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Trio Glucose")
        .description("Your latest Trio glucose and treatment data.")
        .supportedFamilies([.systemMedium])
    }

    private var widgetURL: URL? {
        let scheme = Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String ?? "Trio"
        return URL(string: "\(scheme)://")
    }
}
