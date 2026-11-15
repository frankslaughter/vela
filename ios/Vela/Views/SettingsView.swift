import SwiftUI

/// The rarely used things, kept off the main screen.
struct SettingsView: View {
    @EnvironmentObject private var intercom: Intercom
    @EnvironmentObject private var meter: MicMeter
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { intercom.setDisplayName(name) }
                }

                Section {
                    Toggle("Phone speaker when no headset", isOn: Binding(
                        get: { intercom.usesSpeakerWithoutHeadset },
                        set: { intercom.setUsesSpeakerWithoutHeadset($0) }
                    ))
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Off on the boat, so a lost headset never turns the phone into a loudspeaker. Turn it on to test without a headset. It takes effect the next time you join.")
                }

                Section {
                    LabeledContent("Microphone level", value: meter.levelDB <= -119 ? "Silent" : "\(Int(meter.levelDB.rounded())) dB")
                    LabeledContent("Gate", value: meter.isGateOpen ? "Open" : "Closed")
                } header: {
                    Text("Microphone")
                } footer: {
                    Text("Measured after noise suppression. Silent for five seconds while live raises the dead-microphone warning.")
                }

                if let boat = intercom.wantedBoat {
                    Section {
                        Button(role: .destructive) {
                            intercom.leave()
                            dismiss()
                        } label: {
                            Text("Leave \(boat)").foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Vela stops joining this boat on sight until you pick it again.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    LabeledContent("This phone", value: String(Preferences.deviceID.prefix(8)))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        intercom.setDisplayName(name)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { name = intercom.displayName }
    }
}
