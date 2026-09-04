import SwiftUI

/// The bearer token, on its way to the Keychain.
///
/// The field starts empty even when a token *is* stored — the model has no
/// getter, by design, so there is nothing to prefill and nothing to leak. What
/// the row can say is whether one is stored, which is the only thing the user
/// needs to know before deciding whether to type.
///
/// The write happens on every keystroke rather than on submit: a token that
/// only saves when you remember to press Return is a token that silently is not
/// saved, and the Keychain write is cheap and prompt-free for our own item.
struct TokenFieldRow: View {
    var hasToken: Bool
    var setToken: (String) throws -> Void

    @State private var draft = ""
    @State private var writeFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SecureField(L.settingsHostToken, text: $draft, prompt: Text(prompt))

            if let writeFailure {
                Label(writeFailure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: draft) { _, newValue in
            store(newValue)
        }
    }

    private var prompt: String {
        hasToken ? L.settingsHostTokenStored : L.settingsHostTokenEmpty
    }

    private func store(_ token: String) {
        // An empty draft is "I have not typed anything", not "delete my token".
        guard !token.isEmpty else { return }
        do {
            try setToken(token)
            writeFailure = nil
        } catch {
            writeFailure = L.settingsHostTokenFailed(error.localizedDescription)
        }
    }
}
