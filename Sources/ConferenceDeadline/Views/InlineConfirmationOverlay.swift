import SwiftUI

struct InlineConfirmationOverlay<Actions: View>: View {
    let title: String
    let message: String
    let isBusy: Bool
    let onDismiss: () -> Void
    private let actions: Actions

    init(
        title: String,
        message: String,
        isBusy: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.isBusy = isBusy
        self.onDismiss = onDismiss
        self.actions = actions()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isBusy else { return }
                    onDismiss()
                }

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                if isBusy {
                    ProgressView("正在保存…")
                        .controlSize(.small)
                        .font(.system(size: 11))
                }

                HStack(spacing: 12) {
                    actions
                }
                .disabled(isBusy)
            }
            .padding(20)
            .frame(width: 320)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            .accessibilityElement(children: .contain)
        }
    }
}
