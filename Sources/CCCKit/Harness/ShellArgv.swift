import Foundation

extension ClaudeCLI {
    /// The argv for a shell pane in a session's folder (v6 slice 4): the
    /// user's login shell there, or — behind the same `ssh -t` prefix the
    /// attach pane uses, so it rides the warm master — a remote `cd` and
    /// the far side's login shell. `$SHELL` in the remote words is the
    /// remote shell's to expand: no local shell ever sees these words, the
    /// PTY execs them.
    public func shellArgv(cwd: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        guard let destination = host.ssh else {
            return [Self.loginShell(environment), "-l"]
        }
        return sshPrefix(tty: true, destination: destination) + ["cd \(Self.shellQuoted(cwd)) && exec $SHELL -l"]
    }

    /// `$SHELL` as launchd hands it to a GUI app, else zsh, which every
    /// Mac since Catalina has as the default.
    static func loginShell(_ environment: [String: String]) -> String {
        if let shell = environment["SHELL"], shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    /// Single-quoted for a POSIX shell; a quote inside becomes `'\''`.
    static func shellQuoted(_ word: String) -> String {
        let safe = !word.isEmpty && word.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:@~+,".contains($0) }
        if safe { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
