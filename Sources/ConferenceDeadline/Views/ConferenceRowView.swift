import SwiftUI

struct ConferenceRowView: View {
    let conference: Conference
    @State private var isExpanded = false

    private func urgencyColor(
        for summary: DeadlineSummary,
        relativeTo now: Date
    ) -> Color {
        switch summary.urgency(relativeTo: now) {
        case .past: .gray
        case .withinSevenDays: .red
        case .withinThirtyDays: .orange
        case .later: .primary
        }
    }

    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "CCF-A": return .red
        case "CCF-B": return .orange
        case "CCF-C": return .blue
        default: return .gray
        }
    }

    private func summaryText(
        for summary: DeadlineSummary,
        relativeTo now: Date
    ) -> String {
        let entry = summary.entry
        let interval = entry.date.timeIntervalSince(now)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2

        let timeString = interval < 0
            ? (formatter.string(from: -interval).map { "\($0)前" } ?? "已过期")
            : (formatter.string(from: interval).map { "\($0)后" } ?? "即将")

        return "\(entry.kind.displayName) · \(timeString)"
    }

    var body: some View {
        let now = Date()
        let summary = conference.deadlineLifecycle.summary(relativeTo: now)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(conference.name) \(String(conference.year))")
                            .font(.system(size: 13, weight: .semibold))

                        HStack(spacing: 2) {
                            ForEach(conference.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 8, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(tagColor(for: tag).opacity(0.15))
                                    .foregroundStyle(tagColor(for: tag))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    Text(summaryText(for: summary, relativeTo: now))
                        .font(.system(size: 11))
                        .foregroundStyle(urgencyColor(for: summary, relativeTo: now))
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(conference.deadlineLifecycle.entries) { entry in
                        detailRow(label: entry.kind.displayName, date: entry.date)
                    }
                    if let location = conference.location {
                        detailInfoRow(label: "Location", value: location)
                    }
                    if let venue = conference.venue {
                        detailInfoRow(label: "Venue", value: venue)
                    }
                    if let website = conference.website, let url = URL(string: website) {
                        Link("官网", destination: url)
                            .font(.system(size: 11))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }

    private func detailRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(Conference.displayFormatter.string(from: date))
                .font(.system(size: 11))
            Spacer()
        }
    }

    private func detailInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
            Spacer()
        }
    }
}
