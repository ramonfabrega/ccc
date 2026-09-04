import AppKit
import CCCKit
import SwiftUI

/// The picker (queue item 3): the Macs on the tailnet, so adding one is a
/// click rather than looking up an address.
///
/// The view of `ccc hosts discover`, and its Add calls the same
/// `HostSetup.add` the command does — the list and the add are both one
/// definition with two surfaces, which is the only reason a picker is safe
/// to have at all (CLAUDE.md's parity rule).
///
/// It **enumerates and probes; it never guesses**. Nothing in
/// `tailscale status --json` says which Mac runs an sshd, so every live Mac
/// is offered and the ssh probe is what decides. A machine that cannot
/// answer says why, in place, and nothing is written.
@MainActor @Observable
final class AddHostModel {
    var peers: [Tailnet.Peer] = []
    /// Names already in `hosts.json`, so a peer can say "added" rather than
    /// being silently absent — the list is about the tailnet, not about us.
    var known: Set<String> = []
    var scanError: String?
    /// The peer being added, so its row alone shows a spinner.
    var adding: String?
    /// Per-peer outcome, keyed by name: the sentence to show under the row.
    var results: [String: Outcome] = [:]

    /// What an add said. Not `Result` — both sides are a sentence to show,
    /// and the failure has already been turned into one by `HostSetup`.
    enum Outcome: Equatable {
        case added(String)
        case refused(String)
    }

    var scanning = false

    /// Off the main actor: `Tailnet.scan` runs a subprocess, and a sheet
    /// that spawns one during `onAppear` hitches on the way in.
    func scan() async {
        scanning = true
        defer { scanning = false }
        known = Set(HostConfig.load().config.hosts.map(\.name))
        do {
            peers = try await Task.detached { try Tailnet.scan() }.value
            scanError = nil
        } catch {
            peers = []
            // "No tailscale found" is the common one and already reads as an
            // instruction; anything else is passed through whole.
            scanError = "\(error)"
        }
    }

    func add(_ peer: Tailnet.Peer) async {
        adding = peer.name
        defer { adding = nil }
        // The short MagicDNS label, not `dnsName`: known_hosts and
        // ~/.ssh/config are keyed on what a human types (docs/EVIDENCE.md
        // "v9 slice 6"). `HostSetup.add` defaults ssh to the name, so this
        // passes nothing and inherits that.
        switch await HostSetup.add(name: peer.name) {
        case .success(let added):
            known.insert(peer.name)
            let reader = added.host.ccc == nil ? "roster via claude agents, no model column" : "roster via its own ccc"
            results[peer.name] = .added("added — \(reader)")
        case .failure(let problem):
            results[peer.name] = .refused("\(problem)")
        }
    }
}

struct AddHostView: View {
    @State private var model = AddHostModel()
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Mac").font(.title3.weight(.semibold))
            Text("Macs on your tailnet. Adding one asks it over ssh where `claude` lives; "
                 + "a Mac that cannot answer says so and nothing is saved.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let scanError = model.scanError {
                Label(scanError, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Asking tailscale\u{2026}").font(.callout).foregroundStyle(.secondary)
                }
            } else if model.peers.isEmpty {
                Text("No Macs found on the tailnet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.peers, id: \.name) { peer in
                        row(peer)
                        if peer.name != model.peers.last?.name { Divider() }
                    }
                }
                .padding(.vertical, 2)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text(HostConfig.defaultPath)
                    .font(.caption.monospaced()).foregroundStyle(.tertiary)
                    .truncationMode(.head).lineLimit(1)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await model.scan() }
    }

    @ViewBuilder private func row(_ peer: Tailnet.Peer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(peer.online ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(peer.name).font(.body.weight(.medium))
                // What the machine calls itself, which is never the address.
                Text(peer.hostName).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                if peer.isSelf {
                    Text("this Mac").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                trailing(peer)
            }
            if let result = model.results[peer.name] {
                switch result {
                case .added(let text):
                    Text(text).font(.caption).foregroundStyle(.secondary)
                case .refused(let text):
                    Text(text).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if peer.isSelf, !model.known.contains(peer.name) {
                // Measured 2026-09-04: adding this Mac doubles the roster —
                // `local` and the loopback are the same daemon, so every
                // session appears under both. That is exactly what makes it
                // useful for testing the remote path, and exactly what would
                // baffle someone who clicked Add without knowing.
                Text("the loopback: real ssh, no latency. Every session would appear twice, "
                     + "under local and under \(peer.name).")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !peer.online, let seen = peer.lastSeen {
                Text("last seen \(seen.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder private func trailing(_ peer: Tailnet.Peer) -> some View {
        if model.adding == peer.name {
            ProgressView().controlSize(.small)
        } else if model.known.contains(peer.name) {
            Text("added").font(.callout).foregroundStyle(.tertiary)
        } else {
            Button("Add") { Task { await model.add(peer) } }
                .disabled(model.adding != nil)
        }
    }
}
