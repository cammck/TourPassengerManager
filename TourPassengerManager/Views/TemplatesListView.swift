import SwiftUI

struct TemplatesListView: View {
    @EnvironmentObject var store: TemplateStore
    @State private var showingAddTemplate = false
    @State private var editingTemplate: SMSTemplate?
    @State private var showingAddSnippet = false
    @State private var editingSnippet: Snippet?

    var body: some View {
        List {
            Section {
                ForEach(store.templates) { template in
                    Button {
                        editingTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(template.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                if template.hasStaticRecipient {
                                    Label("Fixed Number", systemImage: "pin.fill")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.indigo, in: Capsule())
                                }
                            }
                            Text(template.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { offsets in
                    store.delete(at: offsets)
                }

                if store.templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates Yet",
                        systemImage: "text.bubble",
                        description: Text("Add a reusable message for things like pickup reminders or booking confirmations.")
                    )
                }
            } header: {
                Text("Templates")
            } footer: {
                Text("Placeholders like {FirstName}, {PickupDetails}, or {BookingNumber} are filled in automatically for each passenger when you send. These are the messages selectable on the Send SMS screen.")
            }

            Section {
                ForEach(store.snippets) { snippet in
                    Button {
                        editingSnippet = snippet
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(snippet.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { offsets in
                    store.deleteSnippet(at: offsets)
                }

                if store.snippets.isEmpty {
                    ContentUnavailableView(
                        "No Snippets Yet",
                        systemImage: "puzzlepiece",
                        description: Text("Add a reusable chunk of text, like an intro or signoff, to include inside templates.")
                    )
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Snippets are reusable building blocks included inside templates via {Snippet:Name} — e.g. a shared intro or signoff. They're not selectable directly on the Send SMS screen.")
            }
        }
        .navigationTitle("Message Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingAddTemplate = true
                    } label: {
                        Label("Add Template", systemImage: "text.bubble")
                    }
                    Button {
                        showingAddSnippet = true
                    } label: {
                        Label("Add Snippet", systemImage: "puzzlepiece")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTemplate) {
            AddEditTemplateView(existingTemplate: nil)
        }
        .sheet(item: $editingTemplate) { template in
            AddEditTemplateView(existingTemplate: template)
        }
        .sheet(isPresented: $showingAddSnippet) {
            AddEditSnippetView(existingSnippet: nil)
        }
        .sheet(item: $editingSnippet) { snippet in
            AddEditSnippetView(existingSnippet: snippet)
        }
    }
}

#Preview {
    NavigationStack {
        TemplatesListView()
            .environmentObject(TemplateStore())
    }
}
