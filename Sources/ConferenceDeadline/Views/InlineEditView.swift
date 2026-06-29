import SwiftUI

struct InlineEditView: View {
    @ObservedObject var session: ConferenceEditingSession
    let onDone: () -> Void

    @State private var showingHiddenConferences = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()

                if showingHiddenConferences {
                    hiddenConferencesView
                } else {
                    editorView
                }

                Divider()

                footer
            }
            .frame(width: 360)
            .frame(minHeight: 380, maxHeight: 520)
            .onChange(of: session.exitRequested) { _, exitRequested in
                if exitRequested {
                    onDone()
                }
            }
            if let navigation = session.pendingNavigation {
                navigationConfirmationOverlay(for: navigation)
            } else if showingDeleteConfirmation {
                deleteConfirmationOverlay
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(showingHiddenConferences ? "返回编辑" : "完成") {
                if showingHiddenConferences {
                    showingHiddenConferences = false
                } else {
                    _ = session.requestExit()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            if session.isDirty && !showingHiddenConferences {
                Text("未保存")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }

            Spacer()

            if !session.hiddenDefaultConferences.isEmpty {
                Button("已隐藏 \(session.hiddenDefaultConferences.count)") {
                    showingHiddenConferences.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            if !showingHiddenConferences, !session.conferences.isEmpty {
                Picker("", selection: selectedConferenceBinding) {
                    ForEach(session.conferences) { conference in
                        Text("\(conference.name) \(String(conference.year))")
                            .tag(conference.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var editorView: some View {
        if let draft = session.draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let feedback = commitFeedback {
                        Text(feedback.message)
                            .font(.system(size: 11))
                            .foregroundStyle(feedback.color)
                    }

                    ConferenceInlineFormView(
                        conference: Binding(
                            get: { session.draft ?? draft },
                            set: { session.updateDraft($0) }
                        ),
                        validationErrors: session.validationErrors
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } else {
            Text("暂无会议可编辑")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var hiddenConferencesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(session.hiddenDefaultConferences) { conference in
                    HStack {
                        Text("\(conference.name) \(String(conference.year))")
                            .font(.system(size: 12))
                        Spacer()
                        Button("恢复") {
                            Task { await session.restoreDefaultConference(id: conference.id) }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if showingHiddenConferences {
                Button("全部恢复") {
                    Task { await session.restoreAllDefaultConferences() }
                }
                .disabled(session.hiddenDefaultConferences.isEmpty || session.isCommitting)
                Spacer()
            } else {
                Button("新增") {
                    _ = session.requestNewConference()
                }

                Spacer()

                Button("取消修改") {
                    session.discardChanges()
                }
                .disabled(!session.isDirty || session.isCommitting)

                Button("保存") {
                    Task { await session.save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.isDirty || session.isCommitting)

                if session.draft != nil {
                    Button("删除") {
                        showingDeleteConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .disabled(session.isCommitting)
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var selectedConferenceBinding: Binding<String?> {
        Binding(
            get: { session.selectedID },
            set: { newID in
                guard let newID else { return }
                _ = session.requestSelection(id: newID)
            }
        )
    }

    private var commitFeedback: (message: String, color: Color)? {
        switch session.lastCommitResult {
        case .saved:
            return ("已保存", .green)
        case .savedWithNotificationWarning(let message):
            return ("已保存，但通知更新失败：\(message)", .orange)
        case .validationFailed:
            return ("请修正标记的字段", .red)
        case .persistenceFailed(let message):
            return ("保存失败：\(message)", .red)
        case .noDraft, .none:
            return nil
        }
    }

    private var deleteConfirmationOverlay: some View {
        InlineConfirmationOverlay(
            title: "确认删除会议",
            message: "Default Conference 将被隐藏；User Conference 将被永久删除。未保存的修改会丢失。",
            isBusy: session.isCommitting,
            onDismiss: {
                showingDeleteConfirmation = false
            }
        ) {
            Button("取消") {
                showingDeleteConfirmation = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 60)
            .keyboardShortcut(.cancelAction)

            Button("删除") {
                showingDeleteConfirmation = false
                Task { await session.deleteSelectedConference() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .frame(minWidth: 60)
        }
    }

    private func navigationConfirmationOverlay(
        for navigation: ConferenceEditingNavigation
    ) -> some View {
        let content = navigationConfirmationContent(for: navigation)

        return InlineConfirmationOverlay(
            title: content.title,
            message: content.message,
            isBusy: session.isCommitting,
            onDismiss: {
                session.cancelPendingNavigation()
            }
        ) {
            Button("继续编辑") {
                session.cancelPendingNavigation()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)

            Button(content.discardTitle) {
                session.discardChangesAndContinue()
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
            .controlSize(.small)

            Button(content.saveTitle) {
                Task { await session.saveChangesAndContinue() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func navigationConfirmationContent(
        for navigation: ConferenceEditingNavigation
    ) -> NavigationConfirmationContent {
        switch navigation {
        case .selectConference:
            return NavigationConfirmationContent(
                title: "切换会议前保存修改？",
                message: "当前 Conference Draft 有未保存的修改。",
                saveTitle: "保存并切换",
                discardTitle: "放弃并切换"
            )
        case .newConference:
            return NavigationConfirmationContent(
                title: "新建会议前保存修改？",
                message: "当前 Conference Draft 有未保存的修改。",
                saveTitle: "保存并新建",
                discardTitle: "放弃并新建"
            )
        case .exit:
            return NavigationConfirmationContent(
                title: "完成编辑前保存修改？",
                message: "当前 Conference Draft 有未保存的修改。",
                saveTitle: "保存并完成",
                discardTitle: "放弃并完成"
            )
        }
    }

    private struct NavigationConfirmationContent {
        let title: String
        let message: String
        let saveTitle: String
        let discardTitle: String
    }
}

struct ConferenceInlineFormView: View {
    @Binding var conference: Conference
    let validationErrors: [ConferenceEditingField: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            formField("名称", error: validationErrors[.name]) {
                TextField("", text: $conference.name)
            }

            HStack {
                formField("年份", error: validationErrors[.year]) {
                    TextField("", value: $conference.year, formatter: NumberFormatter())
                }
                formField("领域") {
                    TextField("", text: binding(for: \.category))
                }
            }

            TagEditorView(tags: $conference.tags)
            validationMessage(for: .tags)

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

            ForEach(DeadlineKind.allCases) { kind in
                deadlineField(for: kind)
            }
        }
    }

    @ViewBuilder
    private func formField<Content: View>(
        _ label: String,
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.roundedBorder)
            if let error {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func deadlineField(for kind: DeadlineKind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if kind.isRequired {
                DatePicker(kind.displayName, selection: requiredDateBinding(for: kind))
                    .datePickerStyle(.compact)
            } else {
                OptionalInlineDatePicker(
                    title: kind.displayName,
                    date: dateBinding(for: kind)
                )
            }
            validationMessage(for: .deadline(kind))
        }
    }

    @ViewBuilder
    private func validationMessage(for field: ConferenceEditingField) -> some View {
        if let message = validationErrors[field] {
            Text(message)
                .font(.system(size: 9))
                .foregroundStyle(.red)
        }
    }

    private func binding(for keyPath: WritableKeyPath<Conference, String?>) -> Binding<String> {
        Binding(
            get: { conference[keyPath: keyPath] ?? "" },
            set: { conference[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func dateBinding(for kind: DeadlineKind) -> Binding<Date?> {
        Binding(
            get: { conference.deadlineLifecycle[kind] },
            set: { date in
                var lifecycle = conference.deadlineLifecycle
                lifecycle[kind] = date
                conference.deadlineLifecycle = lifecycle
            }
        )
    }

    private func requiredDateBinding(for kind: DeadlineKind) -> Binding<Date> {
        Binding(
            get: { conference.deadlineLifecycle[kind]! },
            set: { date in
                var lifecycle = conference.deadlineLifecycle
                lifecycle[kind] = date
                conference.deadlineLifecycle = lifecycle
            }
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
