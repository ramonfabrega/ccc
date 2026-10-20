import Foundation

extension RosterPoller.State {
    /// The row an attach names, across every host in view: what `ccc
    /// attach <ref>`, the roster's click and a `ccc://attach/<ref>` link all
    /// go through before the pane execs anything.
    ///
    /// **A bare ref is local first, then anywhere.** The local form has
    /// meant "this Mac's daemon" since v1 and still does whenever this
    /// Mac's roster has the row. A link has no way to know which ccc host
    /// name the Mac reading it gave the Mac it came from: lore on studio
    /// emits `ccc://attach/d573a0e9`, and on air that id is only on the
    /// `studio` row. So a bare ref no local row answers is looked for on
    /// every other host. The id wins over a name here too, and a ref two
    /// hosts both answer is refused with both addresses rather than picked
    /// between (`RefLookupError`).
    ///
    /// A host-qualified ref is looked up on that host alone. A ref no
    /// roster answers comes back unchanged, so `claude attach` still gets
    /// the word and says what it says about it. A host whose poll failed
    /// may hold the row, and the roster is not the last word on it.
    public func resolve(_ ref: SessionRef) throws -> SessionRef {
        if !ref.isLocal {
            guard let poll = host(ref.host), let row = try Self.match(ref.id, in: poll) else { return ref }
            return row
        }
        if let poll = host(Host.localName), let row = try Self.match(ref.id, in: poll) { return row }
        let others = hosts.filter { $0.host != Host.localName }
        for pass in [Pass.id, .name] {
            var found: [SessionRef] = []
            for poll in others {
                if let row = try Self.match(ref.id, in: poll, pass: pass) { found.append(row) }
            }
            if found.count == 1 { return found[0] }
            if found.count > 1 { throw RefLookupError.ambiguousHost(ref.id, found.map(\.description)) }
        }
        return ref
    }

    private enum Pass { case id, name, either }

    /// One host's answer, by `Collection<Session>.session(matching:)`, the
    /// rule every verb resolves with. Not finding a row is nil, and a name
    /// two of this host's live rows share still throws.
    private static func match(_ text: String, in poll: HostPoll, pass: Pass = .either) throws -> SessionRef? {
        let sessions = poll.rows.map(\.session)
        let found: Session?
        switch pass {
        case .id: found = sessions.first { $0.id == text }
        case .name, .either:
            do {
                found = try sessions.session(matching: text)
            } catch RefLookupError.noSuchSession {
                found = nil
            }
            // `session(matching:)` tries the id first. A name pass that
            // got there by id would count that row twice, once per pass.
            if pass == .name, found?.id == text { return nil }
        }
        return found.map { SessionRef(host: poll.host, id: $0.id) }
    }
}
