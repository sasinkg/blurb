import SwiftUI

struct AddExampleGroupButton: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var isAdding = false
    @State private var resultMessage: String?

    var body: some View {
        Button {
            guard !isAdding else { return }
            isAdding = true
            Task {
                let added = await blurbStore.addExampleGroup()
                isAdding = false
                resultMessage = added
                    ? "Example group is ready on Home. Its people and conversations are fictional; you can try posting, liking, and replying."
                    : blurbStore.errorMessage ?? "The example group couldn't be added. Please try again."
            }
        } label: {
            HStack(spacing: 8) {
                if isAdding { ProgressView() }
                Label(isAdding ? "Adding examples…" : "Add example group", systemImage: "sparkles")
            }
        }
        .disabled(isAdding)
        .accessibilityIdentifier("addExampleGroup")
        .alert("Example group", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }
}
