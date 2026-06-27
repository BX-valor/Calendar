import SwiftUI

struct InlineEditView: View {
    @ObservedObject var viewModel: ConferenceListViewModel
    let onDone: () -> Void

    @State private var selectedID: String?
    @State private var draft: Conference?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("返回") {
                    saveDraftIfNeeded()
                    onDone()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))

                Spacer()

                if viewModel.conferences.count > 1 {
                    Picker("", selection: $selectedID) {
                        ForEach(viewModel.conferences) { conference in
                            Text("\(conference.name) \(String(conference.year))")
                                .tag(conference.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if let draft {
                ScrollView {
                    ConferenceInlineFormView(conference: binding(for: draft))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            } else {
                Text("暂无会议可编辑")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }

            Divider()

            HStack {
                Button("新增") {
                    addConference()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))

                Spacer()

                if draft != nil {
                    Button("删除") {
                        deleteSelectedConference()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .frame(minHeight: 380, maxHeight: 520)
        .onAppear {
            if selectedID == nil, let first = viewModel.conferences.first {
                selectedID = first.id
                draft = first
            }
        }
        .onChange(of: selectedID) { _, newID in
            saveDraftIfNeeded()
            if let newID, let conference = viewModel.conferences.first(where: { $0.id == newID }) {
                draft = conference
            } else {
                draft = nil
            }
        }
    }

    private func binding(for conference: Conference) -> Binding<Conference> {
        Binding(
            get: { conference },
            set: { newValue in
                self.draft = newValue
                viewModel.updateConference(newValue)
            }
        )
    }

    private func addConference() {
        saveDraftIfNeeded()

        let newConference = Conference(
            id: UUID().uuidString,
            name: "New Conference",
            year: Calendar.current.component(.year, from: Date()) + 1,
            category: nil,
            abstractDeadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            paperDeadline: Date().addingTimeInterval(37 * 24 * 60 * 60),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil,
            location: nil,
            venue: nil,
            website: nil,
            timezone: nil,
            tags: ["CCF-A"]
        )
        viewModel.addConference(newConference)
        selectedID = newConference.id
        draft = newConference
    }

    private func deleteSelectedConference() {
        if let draft {
            viewModel.deleteConference(draft)
            self.draft = nil
            selectedID = viewModel.conferences.first?.id
            if let first = viewModel.conferences.first {
                self.draft = first
            }
        }
    }

    private func saveDraftIfNeeded() {
        if let draft, let original = viewModel.conferences.first(where: { $0.id == draft.id }), draft != original {
            viewModel.updateConference(draft)
        }
    }
}

struct ConferenceInlineFormView: View {
    @Binding var conference: Conference

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            formField("名称") {
                TextField("", text: $conference.name)
            }

            HStack {
                formField("年份") {
                    TextField("", value: $conference.year, formatter: NumberFormatter())
                }
                formField("领域") {
                    TextField("", text: binding(for: \.category))
                }
            }

            TagEditorView(tags: $conference.tags)

            formField("官网") {
                TextField("", text: binding(for: \.website))
            }

            formField("时区") {
                TextField("", text: binding(for: \.timezone))
            }

            HStack {
                formField("Location") {
                    TextField("", text: binding(for: \.location))
                }
                formField("Venue") {
                    TextField("", text: binding(for: \.venue))
                }
            }

            Divider()
                .padding(.vertical, 4)

            DatePicker("摘要截止", selection: $conference.abstractDeadline)
                .datePickerStyle(.compact)

            DatePicker("投稿截止", selection: $conference.paperDeadline)
                .datePickerStyle(.compact)

            OptionalInlineDatePicker(title: "Rebuttal", date: binding(for: \.rebuttalDeadline))
            OptionalInlineDatePicker(title: "Final Decision", date: binding(for: \.finalDecisionDate))
            OptionalInlineDatePicker(title: "会议召开", date: binding(for: \.conferenceDate))
        }
    }

    @ViewBuilder
    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for keyPath: WritableKeyPath<Conference, String?>) -> Binding<String> {
        Binding(
            get: { conference[keyPath: keyPath] ?? "" },
            set: { conference[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func binding(for keyPath: WritableKeyPath<Conference, Date?>) -> Binding<Date?> {
        Binding(
            get: { conference[keyPath: keyPath] },
            set: { conference[keyPath: keyPath] = $0 }
        )
    }
}

struct TagEditorView: View {
    @Binding var tags: [String]
    @State private var newTag: String = ""

    private let predefinedTags = ["CCF-A", "CCF-B", "CCF-C", "国内", "顶会", "推荐"]

    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "CCF-A": return .red
        case "CCF-B": return .orange
        case "CCF-C": return .blue
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(predefinedTags, id: \.self) { tag in
                    let isSelected = tags.contains(tag)
                    Button(tag) {
                        if isSelected {
                            tags.removeAll { $0 == tag }
                        } else {
                            tags.append(tag)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? tagColor(for: tag).opacity(0.2) : Color.gray.opacity(0.1))
                    .foregroundStyle(isSelected ? tagColor(for: tag) : .secondary)
                    .clipShape(Capsule())
                }

                ForEach(customTags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Text(tag)
                            .font(.system(size: 10))
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tagColor(for: tag).opacity(0.15))
                    .foregroundStyle(tagColor(for: tag))
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 4) {
                TextField("自定义 tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("添加") {
                    let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !tags.contains(trimmed) {
                        tags.append(trimmed)
                    }
                    newTag = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var customTags: [String] {
        tags.filter { !predefinedTags.contains($0) }
    }
}

struct OptionalInlineDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        HStack(alignment: .center) {
            Toggle("", isOn: Binding(
                get: { date != nil },
                set: { isOn in
                    date = isOn ? Date() : nil
                }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 20)

            if let bindingDate = Binding($date) {
                DatePicker(title, selection: bindingDate)
                    .datePickerStyle(.compact)
            } else {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

// Simple flow layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
