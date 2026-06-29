import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: ConferenceListViewModel

    var body: some View {
        Group {
            if let editingSession = viewModel.editingSession {
                InlineEditView(session: editingSession) {
                    viewModel.finishEditing()
                }
            } else {
                conferenceListView
            }
        }
    }

    private let ccfTags = ["CCF-A", "CCF-B", "CCF-C"]
    private let categories = ["AI", "ML", "CV", "NLP", "Robotics", "DM", "IR", "DB", "MM"]

    private var conferenceListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            filterSection

            Divider()

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(8)
            }

            if viewModel.conferences.isEmpty {
                Text("暂无会议数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if viewModel.displayedConferences.isEmpty {
                Text("没有符合筛选条件的会议")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                List(viewModel.displayedConferences) { conference in
                    ConferenceRowView(conference: conference)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .frame(minWidth: 320, maxWidth: 360, minHeight: 200, maxHeight: 450)
            }

            Divider()

            HStack {
                Button("编辑会议") {
                    viewModel.beginEditing()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

                Spacer()

                Toggle("通知", isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { viewModel.toggleNotifications(enabled: $0) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .controlSize(.small)

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var header: some View {
        HStack {
            Text("AI 会议 Deadline")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            filterChipRow(
                title: "等级",
                allTitle: "全部",
                items: ccfTags,
                isSelected: { viewModel.filter.selectedTags.contains($0) },
                isAllSelected: { viewModel.filter.selectedTags.isEmpty },
                selectAll: { viewModel.filter.selectedTags.removeAll() },
                toggle: { viewModel.toggleTag($0) }
            )

            filterChipRow(
                title: "领域",
                allTitle: "全部",
                items: categories,
                isSelected: { viewModel.filter.selectedCategories.contains($0) },
                isAllSelected: { viewModel.filter.selectedCategories.isEmpty },
                selectAll: { viewModel.filter.selectedCategories.removeAll() },
                toggle: { viewModel.toggleCategory($0) }
            )

            if viewModel.filter.isActive {
                HStack {
                    Spacer()
                    Button("重置") {
                        viewModel.clearFilter()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func filterChipRow(
        title: String,
        allTitle: String,
        items: [String],
        isSelected: @escaping (String) -> Bool,
        isAllSelected: @escaping () -> Bool,
        selectAll: @escaping () -> Void,
        toggle: @escaping (String) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
                .padding(.top, 3)

            FlowLayout(spacing: 6) {
                filterChip(title: allTitle, isSelected: isAllSelected()) {
                    selectAll()
                }

                ForEach(items, id: \.self) { item in
                    filterChip(title: item, isSelected: isSelected(item)) {
                        toggle(item)
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
