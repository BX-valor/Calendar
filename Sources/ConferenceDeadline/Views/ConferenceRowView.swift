import SwiftUI

struct ConferenceRowView: View {
    let conference: Conference
    @State private var isExpanded = false

    private var urgencyColor: Color {
        let interval = conference.timeUntilNextDeadline()
        if interval < 0 {
            return .gray
        } else if interval <= 7 * 24 * 60 * 60 {
            return .red
        } else if interval <= 30 * 24 * 60 * 60 {
            return .orange
        } else {
            return .primary
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

    private var nextDeadlineText: String {
        let (event, date) = conference.nextDeadline()
        let interval = date.timeIntervalSince(Date())
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2

        let timeString = interval < 0
            ? (formatter.string(from: -interval).map { "\($0)前" } ?? "已过期")
            : (formatter.string(from: interval).map { "\($0)后" } ?? "即将")

        return "\(event.rawValue) · \(timeString)"
    }

    var body: some View {
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
                    Text(nextDeadlineText)
                        .font(.system(size: 11))
                        .foregroundStyle(urgencyColor)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "摘要截止", date: conference.abstractDeadline)
                    detailRow(label: "投稿截止", date: conference.paperDeadline)
                    if let rebuttal = conference.rebuttalDeadline {
                        detailRow(label: "Rebuttal", date: rebuttal)
                    }
                    if let finalDecision = conference.finalDecisionDate {
                        detailRow(label: "Final Decision", date: finalDecision)
                    }
                    if let confDate = conference.conferenceDate {
                        detailRow(label: "会议召开", date: confDate)
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
