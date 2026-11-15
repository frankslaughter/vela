import SwiftUI

/// Shown whenever the phone is not on a boat: the boats it can see, and why it is not on one.
struct BoatListView: View {
    @EnvironmentObject private var intercom: Intercom
    @State private var isShowingSettings = false

    private var joiningName: String? {
        if case let .joining(name) = intercom.phase { return name }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vela")
                    .font(.largeTitle.bold())
                Spacer()
                Button { isShowingSettings = true } label: {
                    Label(intercom.displayName, systemImage: "person.crop.circle")
                        .font(.title3)
                        .frame(minHeight: 44)
                }
                .tint(.white)
            }

            if let joiningName {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text("Joining \(joiningName)")
                        .font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            }

            if let problem = intercom.problem ?? intercom.searchProblem {
                Text(problem)
                    .font(.body)
                    .foregroundStyle(.black)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warning, in: RoundedRectangle(cornerRadius: 14))
            }

            Text(intercom.boats.isEmpty ? "Looking for boats on this Wi-Fi" : "Boats on this Wi-Fi")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            if intercom.boats.isEmpty {
                HStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Join the boat's Wi-Fi and the boat appears here.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(intercom.boats) { boat in
                            Button { intercom.choose(boat) } label: {
                                HStack {
                                    Image(systemName: "sailboat.fill").font(.title)
                                    Text(boat.name)
                                        .font(.title2.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .tint(.white)
                            .disabled(joiningName != nil)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }
}
