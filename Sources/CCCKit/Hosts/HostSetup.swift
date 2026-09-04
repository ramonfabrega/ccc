import Foundation

/// Adding a Mac, once, for both surfaces that do it.
///
/// `ccc hosts add` and the app's picker must not be two implementations of
/// "add a host" — one of them would eventually learn something the other did
/// not (CLAUDE.md: every gesture has a command twin, one definition). So the
/// probe, the flag overrides, the validation and the save live here, and each
/// surface only decides how to *ask* and how to *say*.
public enum HostSetup {
    /// What an add produced: the host that was saved, and the things worth
    /// telling the user that were not failures.
    ///
    /// Notes are separate from errors on purpose. "No ccc on the far side"
    /// still gives a correct roster — just without the model column — so it
    /// is a sentence, not a refusal (v2 slice 1's behaviour).
    public struct Added: Sendable, Equatable {
        public var host: Host
        public var notes: [String]
    }

    /// Why an add could not happen, in the words the surface should show.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The far side's host key is not in `known_hosts`, so ccc's
        /// non-interactive ssh was refused before it could look for
        /// anything. **This is the first add from any new Mac**, and it used
        /// to be reported as "no claude found" — the search never ran.
        case unknownHostKey(destination: String, name: String)
        /// Reached the far side, found no `claude` on it.
        case noClaude(name: String, looked: [String], notes: [String])
        /// The host would not survive a write to `hosts.json`.
        case invalid(String)
        case couldNotSave(String)

        public var description: String {
            switch self {
            case .unknownHostKey(let destination, let name):
                return "\(destination)'s host key is not known, so ccc's non-interactive ssh was refused "
                    + "before it could look for claude. Run `ssh \(destination)` once, accept the key, "
                    + "then add \(name) again."
            case .noClaude(let name, let looked, let notes):
                return "no claude found on \(name) at \(looked.joined(separator: ", ")); pass an absolute path"
                    + (notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))")
            case .invalid(let reason): return reason
            case .couldNotSave(let reason): return "could not save the host list: \(reason)"
            }
        }
    }

    /// Ask the far side where things are, then save it.
    ///
    /// `ssh` defaults to `name`, which is the **short MagicDNS label** and
    /// not the full name: `known_hosts` and `~/.ssh/config` are keyed on
    /// what a human types, so `studio` works where
    /// `studio.bengal-barb.ts.net` fails host key verification (measured
    /// 2026-09-04, docs/EVIDENCE.md "v9 slice 6").
    ///
    /// One ssh, not three: `ClaudeCLI.probe` asks for `$HOME`, `claude` and
    /// `ccc` together, because a round trip is ~250 ms and guessing any of
    /// the three is how experiment 3's "no claude on PATH" bites.
    public static func add(
        name: String, ssh: String? = nil, claude: String? = nil,
        ccc: String? = nil, wantCCC: Bool = true,
        into path: String = HostConfig.defaultPath
    ) async -> Result<Added, Failure> {
        let destination = ssh ?? name
        var notes: [String] = []
        var probed: ClaudeCLI.Probe?
        var probeError: String?
        do {
            probed = try await ClaudeCLI(executable: "claude", host: Host(name: name, ssh: destination)).probe()
        } catch {
            probeError = "\(error)"
            notes.append("could not reach \(destination) to look for claude and ccc (\(error))")
        }

        guard let resolvedClaude = claude ?? probed?.claude else {
            if probeError?.contains("Host key verification failed") == true {
                return .failure(.unknownHostKey(destination: destination, name: name))
            }
            return .failure(.noClaude(name: name, looked: ClaudeCLI.Probe.claudeCandidates, notes: notes))
        }

        let remoteCCC = wantCCC ? (ccc ?? probed?.ccc) : nil
        if wantCCC, remoteCCC == nil {
            notes.append("no ccc on \(name) (looked in \(ClaudeCLI.Probe.cccCandidates.joined(separator: ", "))): "
                         + "roster via claude agents, no model column; install ccc there and re-add")
        }

        let host = Host(name: name, ssh: destination, claude: resolvedClaude, ccc: remoteCCC, home: probed?.home)
        if let problem = host.validate() { return .failure(.invalid(problem)) }

        var loaded = HostConfig.load(path: path)
        loaded.config.hosts.removeAll { $0.name == name }
        loaded.config.hosts.append(host)
        do {
            try loaded.config.save(path: path)
        } catch {
            return .failure(.couldNotSave("\(error)"))
        }
        return .success(Added(host: host, notes: notes))
    }
}
