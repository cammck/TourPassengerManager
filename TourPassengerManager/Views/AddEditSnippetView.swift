import SwiftUI

struct AddEditSnippetView: View {
    @EnvironmentObject private var store: TemplateStore
    @Environment(\.dismiss) private var dismiss

    let existingSnippet: Snippet?

    @State private var name: String
    @State private var messageBody: String

    init(existingSnippet: Snippet?) {
        self.existingSnippet = existingSnippet
        _name = State(initialValue: existingSnippet?.name ?? "")
        _messageBody = State(initialValue: existingSnippet?.body ?? "")
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Intro", text: $name)
                } header: {
                    Text("Snippet Name")
                } footer: {
                    Text("This is the name used to include it in a template, e.g. {Snippet:\(name.isEmpty ? "Name" : name)}.")
                }

                Section("Text") {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 120)
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
                    Text("Wrap text in {#Token}...{/Token} and it only appears when at least one selected passenger has something in that field. Works with any token, not just the two examples above.")
                }

                if existingSnippet != nil {
                    Section {
                        Button("Delete Snippet", role: .destructive) {
                            if let existingSnippet {
                                store.deleteSnippet(existingSnippet)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingSnippet == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var snippet = existingSnippet ?? Snippet()
                        snippet.name = name.trimmingCharacters(in: .whitespaces)
                        snippet.body = messageBody
                        if existingSnippet == nil {
                            store.addSnippet(snippet)
                        } else {
                            store.updateSnippet(snippet)
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
    AddEditSnippetView(existingSnippet: nil)
        .environmentObject(TemplateStore())
}
