import SwiftUI

/// The servers a game can be streamed from, best first.
///
/// Every server the service offers for the account is listed with how far
/// away it is and how long its queue was last time. The server can be
/// picked by hand, which is the point: the queue on one side of the world
/// can be shorter than the queue on the other, and the only way to know is
/// to be told.
struct ServerPickerSheet: View {
    let game: Game
    let onPlay: (CloudServer?) -> Void

    @EnvironmentObject private var servers: CloudServers
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if servers.servers.isEmpty {
                        // The list comes from the service's own answer, so
                        // it may not have arrived yet.
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Asking Xbox which servers it can use…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(servers.ranked) { server in
                        Button {
                            onPlay(server)
                            dismiss()
                        } label: {
                            row(server)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Where to play \(game.title)")
                } footer: {
                    Text("The queue is the wait the service estimated the last "
                         + "time a session was started there. The ping is "
                         + "measured now. A server that is far away is no "
                         + "good however short its queue.")
                }

                Section {
                    Button {
                        onPlay(nil)
                        dismiss()
                    } label: {
                        Label("Let the service choose", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle("Cloud server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { servers.measure() }
        }
    }

    private func row(_ server: CloudServer) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.title)
                        .font(.subheadline.weight(.semibold))
                    if server.isDefault {
                        Text("default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                Text("\(server.shortName) · \(servers.queueText(for: server))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(servers.pingText(for: server))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
