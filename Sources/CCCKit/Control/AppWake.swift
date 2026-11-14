import Foundation
import OTA

/// Bring this Mac's ccc.app up when nothing is serving the control socket.
///
/// The CLI has always worked without the app — except for the verbs whose
/// whole point is that something acts *later*. An armed clear is typed by
/// a pane minutes after the caller has gone, so `ccc clear` refuses when
/// no ccc is serving, and for a month that refusal was the loop's one
/// handover channel failing whenever the window happened to be closed
/// (attrition, 2026-10-15 and 2026-11-12: the steer session started a
/// headless pane as a background task to get its handover through, and
/// told the user "opening ccc.app is the durable fix").
///
/// The app is meant to be resident (CLAUDE.md: menubar-resident, launch
/// at login). This is the CLI restoring that when it finds it broken,
/// rather than reporting it to a session that cannot open an app. It is
/// **not** a daemon of our own: what comes up is the same ccc.app, with
/// its window left closed (`residentKey`).
public enum AppWake {
    /// Set in the woken app's environment. The app reads it as "nobody
    /// asked to look at me": no window, no activation, no reattach to the
    /// session the window was last in — a wake is an agent's side effect
    /// and must not resize a session the user is watching elsewhere.
    public static let residentKey = "CCC_RESIDENT"

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        /// The socket is not the one a woken app would serve.
        case privateSocket(String)
        /// This `ccc` is not inside an app bundle.
        case noBundle(String)
        /// `open` refused; its first line.
        case openFailed(String)
        /// The app was started and never answered.
        case neverServed(String, TimeInterval)

        public var description: String {
            switch self {
            case .privateSocket(let path):
                return "CCC_CONTROL_SOCKET points at \(path), which ccc.app does not serve"
            case .noBundle(let executable):
                return "\(executable) is not in an app bundle, so there is no ccc.app to start"
            case .openFailed(let said):
                return "starting ccc.app failed: \(said)"
            case .neverServed(let bundle, let seconds):
                return "started \(bundle) and it did not serve the socket within \(Int(seconds)) s"
            }
        }
    }

    /// `nil` once a ccc is serving; otherwise why none could be brought up.
    /// Every dependency is a parameter so the decision is a test and the
    /// test never launches anything.
    public static func wake(socket: String = ControlSocket.defaultPath,
                            standardSocket: String = ControlSocket.standardPath,
                            bundle: String? = BuildInfo.current.bundlePath,
                            executable: String = BuildInfo.current.executablePath,
                            patience: TimeInterval = 15,
                            interval: TimeInterval = 0.25,
                            serving: @Sendable () -> Bool = { ControlClient().isReachable() },
                            open: @Sendable (String) async -> String? = AppWake.open) async -> Refusal? {
        if serving() { return nil }
        guard socket == standardSocket else { return .privateSocket(socket) }
        guard let bundle else { return .noBundle(executable) }
        if let said = await open(bundle) { return .openFailed(said) }
        let deadline = Date().addingTimeInterval(patience)
        while Date() < deadline {
            if serving() { return nil }
            try? await Task.sleep(for: .seconds(interval))
        }
        return serving() ? nil : .neverServed(bundle, patience)
    }

    /// `open -g`: started, never brought forward. `nil` on success, else
    /// the first line `open` printed — the reason, not "exit 1".
    public static let open: @Sendable (String) async -> String? = { bundle in
        do {
            let out = try await Subprocess.run(argv(bundle: bundle))
            guard out.status != 0 else { return nil }
            let said = String(decoding: out.stderr + out.stdout, as: UTF8.self)
                .split(whereSeparator: \.isNewline).first.map(String.init)
            return said ?? "open exited \(out.status)"
        } catch {
            return "\(error)"
        }
    }

    /// The words, apart from the run, so a test reads them.
    public static func argv(bundle: String) -> [String] {
        ["/usr/bin/open", "-g", "--env", "\(residentKey)=1", bundle]
    }
}
