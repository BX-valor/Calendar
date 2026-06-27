import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: ConferenceListViewModel
    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                InlineEditView(viewModel: viewModel) {
                    isEditing = false
                }
            } else {
                conferenceListView
            }
        }
    }

    private var conferenceListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

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
            } else {
                List(viewModel.conferences) { conference in
                    ConferenceRowView(conference: conference)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .frame(minWidth: 320, maxWidth: 360, minHeight: 200, maxHeight: 450)
            }

            Divider()

            HStack {
                Button("编辑会议") {
                    isEditing = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

                Spacer()

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
}
