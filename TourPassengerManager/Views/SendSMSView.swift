import SwiftUI
import MessageUI

struct SendSMSView: View {
    let tour: Tour
    let passengers: [Passenger]
    var onFinished: () -> Void

    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var useCustomMessage = false
    @State private var selectedTemplate: SMSTemplate?
    @State private var customBody = ""
    @State private var editedBody = ""
    @State private var showingCantSendAlert = false
    @StateObject private var messageComposerPresenter = MessageComposerPresenter()

    private var recipientsWithNumbers: [Passenger] {
        passengers.filter { !$0.mobileNumber.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var recipientsMissingNumbers: [Passenger] {
        passengers.filter { $0.mobileNumber.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var messageTemplate: String {
        useCustomMessage ? customBody : (selectedTemplate?.body ?? "")
    }

    /// The fixed number(s) set on the selected template, if any — only applies to a
    /// chosen template, never to a custom message (which has no template to carry one).
    private var staticRecipients: [String] {
        guard !useCustomMessage else { return [] }
        return selectedTemplate?.staticRecipients ?? []
    }

    private var isUsingStaticRecipient: Bool {
        !staticRecipients.isEmpty
    }

    /// Who the message actually goes to: the template's fixed number(s) when set,
    /// otherwise each selected passenger's own mobile number.
    private var recipientNumbers: [String] {
        isUsingStaticRecipient ? staticRecipients : recipientsWithNumbers.map { $0.mobileNumber }
    }

    /// Which passengers' details fill in the message placeholders. When sending to a
    /// fixed number, every selected passenger counts — the message is about them,
    /// even though it isn't going to their own phone — so a passenger with no mobile
    /// number on file no longer needs to be excluded.
    private var placeholderPassengers: [Passenger] {
        isUsingStaticRecipient ? passengers : recipientsWithNumbers
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipients") {
                    if isUsingStaticRecipient {
                        Label(
                            "This template sends to a fixed number, set on the template — not to the selected passengers' own numbers.",
                            systemImage: "pin.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        ForEach(staticRecipients, id: \.self) { number in
                            Label(number, systemImage: "phone.fill")
                                .font(.subheadline)
                        }
                    } else {
                        Text("\(recipientsWithNumbers.count) of \(passengers.count) selected passengers have a mobile number on file.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !recipientsMissingNumbers.isEmpty {
                            ForEach(recipientsMissingNumbers) { passenger in
                                Label(passenger.displayName, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if !isUsingStaticRecipient {
                    Section {
                        Label("This sends a single group text to everyone listed above. Recipients will see each other's phone numbers and any replies, the same as a normal group text.", systemImage: "person.2.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if staticRecipients.count > 1 {
                    Section {
                        Label("This sends a single group text to every fixed number listed above. They will see each other's numbers and any replies.", systemImage: "person.2.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Message") {
                    Toggle("Write custom message instead", isOn: $useCustomMessage.animation())

                    if !useCustomMessage {
                        Picker("Template", selection: $selectedTemplate) {
                            Text("Choose a template").tag(SMSTemplate?.none)
                            ForEach(templateStore.templates) { template in
                                Text(template.hasStaticRecipient ? "📌 \(template.name)" : template.name)
                                    .tag(Optional(template))
                            }
                        }
                    }
                }

                if useCustomMessage {
                    Section("Custom Message") {
                        TextEditor(text: $customBody)
                            .frame(minHeight: 100)
                    }
                }

                if !editedBody.isEmpty || !messageTemplate.isEmpty {
                    Section {
                        TextEditor(text: $editedBody)
                            .frame(minHeight: 160)
                    } header: {
                        HStack {
                            Text("Message (edit before sending)")
                            Spacer()
                            Button("Reset") {
                                resetEditedBody()
                            }
                            .font(.caption)
                            .disabled(messageTemplate.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } footer: {
                        Text("Placeholders are filled in automatically. Double-check anything marked with *** or **** — those are meant to be filled in by hand (exact meeting time, allergy specifics, etc.) before you send.")
                    }
                }

                Section {
                    Text("Available placeholders: " + MessagePlaceholders.availableTokens.joined(separator: ", ") + ". {Snippet:Name} splices in a reusable snippet (e.g. a shared intro or signoff, managed on the Templates screen). When multiple passengers are selected, name-style placeholders combine into a natural list (e.g. \"Jane and John\") and shared details like pickup location appear once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("iOS requires you to tap Send yourself in the Messages screen — apps can't send texts without your confirmation. You'll see one composer, pre-filled and addressed to everyone selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Send SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        startSending()
                    }
                    .disabled(editedBody.trimmingCharacters(in: .whitespaces).isEmpty || recipientNumbers.isEmpty)
                }
            }
            .alert("Can't Send Messages", isPresented: $showingCantSendAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device isn't set up to send text messages. Try a physical iPhone signed into Messages — the Simulator can't send SMS.")
            }
            .onChange(of: messageTemplate) { _, newValue in
                resetEditedBody(to: newValue)
            }
            .onChange(of: selectedTemplate) { _, _ in
                // The body text alone doesn't change when switching between two
                // templates that happen to read the same but differ in their fixed
                // recipient, so re-resolve on template selection too, not just body.
                resetEditedBody()
            }
        }
    }

    /// Recomputes editedBody from the current template selection/custom text,
    /// discarding any manual edits — used both by the "Reset" button and
    /// automatically whenever the underlying template/custom text changes.
    private func resetEditedBody(to template: String? = nil) {
        let source = template ?? messageTemplate
        guard !source.isEmpty else {
            editedBody = ""
            return
        }
        editedBody = MessagePlaceholders.resolveGroup(source, passengers: placeholderPassengers, tour: tour, settings: settingsStore.settings, allSnippets: templateStore.snippets)
    }

    private func startSending() {
        guard MessageComposerPresenter.canSendText else {
            showingCantSendAlert = true
            return
        }
        messageComposerPresenter.present(recipients: recipientNumbers, body: editedBody) { _ in
            onFinished()
            dismiss()
        }
    }
}

#Preview {
    SendSMSView(
        tour: Tour(code: "Sample Tour", startDate: Date()),
        passengers: [
            Passenger(surname: "Doe", firstName: "Jane", preferredName: "Janie", mobileNumber: "0400 000 000"),
            Passenger(surname: "Smith", firstName: "John", mobileNumber: "0400 111 111")
        ],
        onFinished: {}
    )
    .environmentObject(TemplateStore())
    .environmentObject(SettingsStore())
}
