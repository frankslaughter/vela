import SwiftUI

struct RootView: View {
    @EnvironmentObject private var intercom: Intercom

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch intercom.phase {
            case .needsName:
                NameView()
            case .looking, .joining:
                BoatListView()
            case .connected, .reconnecting:
                IntercomView()
            }
        }
        .foregroundStyle(.white)
    }
}

/// First launch: the one thing the app has to ask.
struct NameView: View {
    @EnvironmentObject private var intercom: Intercom
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("What should the crew call you?")
                .font(.largeTitle.bold())
            Text("This is the name others see when you talk.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
            TextField("Your name", text: $name)
                .font(.title2)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .frame(height: 64)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .onSubmit(save)
            Button(action: save) {
                Text("Continue")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.live)
            .disabled(trimmed.isEmpty)
            Spacer()
            Spacer()
        }
        .padding(24)
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        intercom.setDisplayName(trimmed)
    }
}
