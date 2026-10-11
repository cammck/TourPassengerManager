import SwiftUI

struct AddEditTemplateView: View {
    @EnvironmentObject private var store: TemplateStore
    @Environment(\.dismiss) private var dismiss

    let existingTemplate: SMSTemplate?

    @State private var name: String
    @State private var messageBody: String
    @State private var sendToFixedNumber: Bool
    @State private var staticRecipientNumbers: String

    init(existingTemplate: SMSTemplate?) {
        self.existingTemplate = existingTemplate
        _name = State(initialValue: existingTemplate?.name ?? "")
        _messageBody = State(initialValue: existingTemplate?.body ?? "")
        _sendToFixedNumber = State(initialValue: existingTemplate?.hasStaticRecipient ?? false)
        _staticRecipientNumbers = State(initialValue: existingTemplate?.staticRecipientNumbers ?? "")
    }

    private let conditionalSnippets: [(label: String, text: String)] = [
        (
            label: "Dietary requirements (if any)",
            text: "{#DietaryRequirements}Dietary requirements noted: {DietaryRequirements}. {/DietaryRequirements}"
        ),
        (
            label: "Medical condition (if any)",
            text: "{#MedicalCondition}Medical condition noted: {MedicalCondition}. {/MedicalCondition}"
        )
    ]

    /// Snippets available to include via {Snippet:Name} — e.g. a shared intro or
    /// signoff. Managed separately on the Templates screen; snippets are never
    /// themselves selectable on the Send SMS screen.
    private var availableSnippets: [Snippet] {
        store.snippets
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Name") {
                    TextField("e.g. Pickup Reminder", text: $name)
                }

                Section("Message") {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle("Send to a fixed number instead", isOn: $sendToFixedNumber.animation())

                    if sendToFixedNumber {
                        TextField("e.g. 0400 111 222", text: $staticRecipientNumbers)
                            .keyboardType(.phonePad)
                    }
                } footer: {
                    Text(sendToFixedNumber
                         ? "Sending this template always goes to this number, never to the selected passengers' own numbers — useful for a template that notifies a driver or the office about a pickup rather than messaging the guest. Separate multiple numbers with commas to send to all of them at once. Placeholders still fill in using the passengers selected when you send."
                         : "By default, sending a template goes to each selected passenger's own mobile number.")
                }

                Section {
                    ForEach(MessagePlaceholders.availableTokens, id: \.self) { token in
                        Button {
                            messageBody += token
                        } label: {
                            Text(token)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                } header: {
                    Text("Tap to Insert a Placeholder")
                } footer: {
                    Text("{Day1FullDate}/{Day1Name} work for any day of the tour — type {Day2FullDate}, {Day7Name}, etc. Day 1 is the tour's start date. These only resolve if the tour has a start date set. {PickupTime}, {DropoffTime}, and {TownTourTime} also accept an offset, e.g. {PickupTime + 15m}, {DropoffTime - 1h}, or {TownTourTime + 1h30m}.")
                }

                Section {
                    ForEach(conditionalSnippets, id: \.label) { snippet in
                        Button {
                            messageBody += snippet.text
                        } label: {
                            Text(snippet.label)
                        }
                    }
                } header: {
                    Text("Tap to Insert a Conditional Snippet")
                } footer: {
                    Text("Wrap text in {#Token}...{/Token} and it only appears when at least one selected passenger has something in that field — e.g. {#DietaryRequirements}Dietary requirements: {DietaryRequirements}. {/DietaryRequirements} disappears entirely if nobody selected has any dietary requirements on file. Works with any token, not just the two examples above — just match the name inside {#...} and {/...}. Tip: put spacing inside the block rather than around it, so removing an inapplicable block doesn't leave a stray double space.")
                }

                Section {
                    Button {
                        messageBody += "{#EachBooking}{CombinedName}: flight {PickupFlightNumber}, pickup {PickupTime} from {PickupLocation}.\n{/EachBooking}"
                    } label: {
                        Text("Flight details, one line per booking")
                    }
                } header: {
                    Text("Tap to Insert a Booking Loop")
                } footer: {
                    Text("Wrap text in {#EachBooking}...{/EachBooking} and it repeats once for each distinct booking among the selected passengers — so guests on different flights (or otherwise different pickup/dropoff details) can each get their own line instead of being merged into one combined sentence. Every placeholder inside the block, plus conditional blocks like {#DietaryRequirements}, resolves using just that one booking's passengers. A shared or linked booking number (see Booking Links) still counts as a single booking. Passengers with no booking number at all aren't part of any booking and are skipped by the loop.")
                }

                if !availableSnippets.isEmpty {
                    Section {
                        ForEach(availableSnippets) { snippet in
                            Button {
                                messageBody += "{Snippet:\(snippet.name)}"
                            } label: {
                                Text(snippet.name)
                            }
                        }
                    } header: {
                        Text("Tap to Include a Snippet")
                    } footer: {
                        Text("{Snippet:Name} splices in a reusable snippet's text — handy for a shared intro or signoff used across many templates. Manage snippets from the Templates screen. It's resolved before anything else, so placeholders and conditional snippets inside the included snippet still work normally.")
                    }
                }

                if existingTemplate != nil {
                    Section {
                        Button("Delete Template", role: .destructive) {
                            if let existingTemplate {
                                store.delete(existingTemplate)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingTemplate == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var template = existingTemplate ?? SMSTemplate()
                        template.name = name.trimmingCharacters(in: .whitespaces)
                        template.body = messageBody
                        template.staticRecipientNumbers = sendToFixedNumber ? staticRecipientNumbers : nil
                        if existingTemplate == nil {
                            store.add(template)
                        } else {
                            store.update(template)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              messageBody.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddEditTemplateView(existingTemplate: nil)
        .environmentObject(TemplateStore())
}
