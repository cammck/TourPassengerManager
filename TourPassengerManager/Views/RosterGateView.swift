import SwiftUI

/// Wraps PassengerListView with a Face ID / passcode gate — guest details for a tour
/// are never shown until the device owner authenticates. Locking is session-based:
/// once unlocked it stays unlocked (across tours) until the app backgrounds or the
/// person taps Lock, at which point this automatically re-covers the screen.
///
/// Important: PassengerListView is always kept mounted, even while locked — only an
/// opaque screen is overlaid on top of it. Swapping it out entirely (rather than
/// covering it) would tear down and recreate it, along with anything presented on
/// top of it (e.g. the SMS compose sheet), losing any in-progress edits whenever the
/// app backgrounds and re-locks — which is exactly what used to happen.
struct RosterGateView: View {
    @Binding var tour: Tour
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        PassengerListView(tour: $tour)
            .accessibilityHidden(!authManager.isUnlocked)
            .allowsHitTesting(authManager.isUnlocked)
            .toolbar(authManager.isUnlocked ? .visible : .hidden, for: .navigationBar)
            .overlay {
                if !authManager.isUnlocked {
                    lockedView
                }
            }
            .onAppear {
                if !authManager.isUnlocked {
                    authManager.authenticate()
                }
            }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Passenger Details Locked")
                .font(.headline)

            Text("Face ID (or your device passcode) is required to view guest details for \(tour.code.isEmpty ? "this tour" : tour.code).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = authManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                authManager.authenticate()
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        RosterGateView(tour: .constant(Tour(code: "Sample Tour")))
            .environmentObject(AuthManager())
    }
}
