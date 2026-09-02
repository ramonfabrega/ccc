import Foundation
import Testing

@testable import CCCKit

/// `ccc` on PATH is a symlink into the bundle, so the command and the app
/// are one build and an update carries the link along. These pin what the
/// first-launch offer and `ccc install-cli` decide from, and that a build
/// number is read from the bundle the executable actually lives in — not
/// from wherever the symlink was typed.
///
/// The code under test lives in `ota`'s `OTA` product now (docs/DESIGN.md
/// §6), and ota has its own tests for it. These stay anyway, and stay
/// ccc-flavoured: they are what ccc REQUIRES of that dependency, and the
/// day an ota bump changes one of these answers, ccc is what should fail.
@Suite struct CLIInstallTests {
    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "ccc-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    /// The installer under test, always named the way ccc names itself.
    private func installer(_ directories: [String], home: String = NSHomeDirectory()) -> CLIInstall {
        CLIInstall(command: cccName, directories: directories, home: home)
    }

    /// A fake `X.app` with a plist and an executable, the shape `ota bundle` makes.
    private func makeBundle(in dir: URL, version: String = "0.1.5", build: Int = 57, release: Bool = true) throws -> URL {
        let app = dir.appending(path: "ccc.app")
        let macos = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let exe = macos.appending(path: "ccc")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>ccc</string>
          <key>CFBundleIdentifier</key><string>com.ramonfabrega.ccc.test</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
          <key>CFBundleVersion</key><string>\(build)</string>
          \(release ? "<key>SUFeedURL</key><string>https://example.invalid/appcast.xml</string>" : "")
        </dict></plist>
        """
        try Data(plist.utf8).write(to: app.appending(path: "Contents/Info.plist"))
        return exe
    }

    @Test func buildComesFromTheBundleAboveTheExecutable() throws {
        try withTempDir { dir in
            let exe = try makeBundle(in: dir)
            let info = BuildInfo(name: cccName, executable: exe)
            #expect(info.version == "0.1.5")
            #expect(info.build == 57)
            #expect(info.bundlePath == dir.appending(path: "ccc.app").path)
            #expect(info.isBundled)
            #expect(!info.dev)
            #expect(info.short == "0.1.5 (57)")
            #expect(info.appTitle == "ccc")
        }
    }

    /// The lane is the feed's absence: a bundle cut without the feed keys
    /// (`ota bundle` with no `--feed`) is dev, says so everywhere, and is
    /// still installable.
    @Test func aBundleWithoutTheFeedIsTheDevLane() throws {
        try withTempDir { dir in
            let info = BuildInfo(name: cccName, executable: try makeBundle(in: dir, release: false))
            #expect(info.isBundled)
            #expect(info.dev)
            #expect(info.short == "0.1.5 (57) dev")
            #expect(info.appTitle == "ccc·dev")
        }
    }

    /// The command on PATH is a symlink; the build is still the bundle's.
    @Test func aSymlinkedCommandResolvesToItsBundle() throws {
        try withTempDir { dir in
            let exe = try makeBundle(in: dir)
            let bin = dir.appending(path: "bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let link = bin.appending(path: "ccc")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: exe)
            let info = BuildInfo(name: cccName, executable: link.resolvingSymlinksInPath())
            #expect(info.build == 57)
            #expect(info.executablePath == exe.resolvingSymlinksInPath().path)
        }
    }

    @Test func aBareBinaryIsADevBuild() throws {
        try withTempDir { dir in
            let exe = dir.appending(path: "ccc")
            try Data("#!/bin/sh\n".utf8).write(to: exe)
            let info = BuildInfo(name: cccName, executable: exe)
            #expect(!info.isBundled)
            #expect(info.dev)
            #expect(info.version == nil)
            #expect(info.short == "dev")
        }
    }

    @Test func buildInfoRoundTripsAsJSON() throws {
        let info = BuildInfo(name: cccName, version: "0.1.5", build: 57,
                             bundlePath: "/Applications/ccc.app",
                             executablePath: "/Applications/ccc.app/Contents/MacOS/ccc")
        let back = try JSONDecoder.ccc.decode(BuildInfo.self, from: JSONEncoder().encode(info))
        #expect(back == info)
    }

    /// A ccc older than v0.1.6 sends no `name` — `hosts check` is the reader
    /// and must still get a named build back, or a remote row renders blank.
    @Test func anOlderPeerStillDecodesAndIsNamedHere() throws {
        let legacy = Data("""
        {"version":"0.1.5","build":57,"bundlePath":"/Applications/ccc.app","executablePath":"/Applications/ccc.app/Contents/MacOS/ccc"}
        """.utf8)
        let info = try BuildInfo.decode(legacy, naming: cccName)
        #expect(info.name == "ccc")
        #expect(info.appTitle == "ccc")
        #expect(!info.dev)
        #expect(info.short == "0.1.5 (57)")
    }

    @Test func statusSeesMissingThenInstalledThenDangling() throws {
        try withTempDir { dir in
            let exe = try makeBundle(in: dir)
            let bin = dir.appending(path: "bin").path
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            let cli = installer([bin])
            #expect(cli.status(executable: exe.path, path: nil) == .missing)

            let result = try cli.install(executable: exe.path)
            #expect(result.path == bin + "/ccc")
            #expect(result.replaced == nil)
            #expect(!result.createdDirectory)
            #expect(cli.status(executable: exe.path, path: nil) == .installed(path: bin + "/ccc"))

            // Installing again is a no-op, not an error.
            let again = try cli.install(executable: exe.path)
            #expect(again == result)

            // The app moved away: the link dangles and is offered again.
            try FileManager.default.removeItem(at: dir.appending(path: "ccc.app"))
            #expect(cli.status(executable: exe.path, path: nil)
                    == .dangling(path: bin + "/ccc", target: exe.path))
        }
    }

    /// A `ccc` that is not ours — another bundle's link, or a real file — is
    /// reported and never replaced by the offer; `install` relinks a
    /// symlink on request but refuses a regular file without `--force`.
    @Test func aForeignCommandIsReportedAndAFileNeedsForce() throws {
        try withTempDir { dir in
            let exe = try makeBundle(in: dir)
            let other = try makeBundle(in: dir.appending(path: "other"), build: 50)
            let bin = dir.appending(path: "bin").path
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: bin + "/ccc", withDestinationPath: other.path)
            let cli = installer([bin])
            #expect(cli.status(executable: exe.path, path: nil)
                    == .foreign(path: bin + "/ccc", target: other.path))
            let relinked = try cli.install(executable: exe.path)
            #expect(relinked.replaced == other.path)
            #expect(cli.status(executable: exe.path, path: nil) == .installed(path: bin + "/ccc"))

            try FileManager.default.removeItem(atPath: bin + "/ccc")
            try Data("not a link".utf8).write(to: URL(filePath: bin + "/ccc"))
            #expect(cli.status(executable: exe.path, path: nil) == .foreign(path: bin + "/ccc", target: nil))
            #expect(throws: CLIInstall.InstallError.self) {
                try cli.install(executable: exe.path)
            }
            let forced = try cli.install(executable: exe.path, force: true)
            #expect(forced.replaced == bin + "/ccc")
        }
    }

    /// No writable candidate: the last one (`~/.local/bin`) is created, and
    /// the result says so, since it may not be on PATH yet.
    @Test func createsTheLastCandidateWhenNoneIsWritable() throws {
        try withTempDir { dir in
            let exe = try makeBundle(in: dir)
            let local = dir.appending(path: "home/.local/bin").path
            let cli = installer(["/nonexistent-\(UUID().uuidString)", "~/.local/bin"],
                                home: dir.appending(path: "home").path)
            let result = try cli.install(executable: exe.path)
            #expect(result.path == local + "/ccc")
            #expect(result.createdDirectory)
            #expect(result.description.contains("add it to PATH"))
        }
    }

    /// A PATH entry counts as "installed" too: the offer must not nag a
    /// user whose command lives somewhere unusual.
    @Test func statusSearchesPATHAfterTheCandidates() throws {
        try withTempDir { dir in
            let exe = try makeBundle(in: dir)
            let odd = dir.appending(path: "odd").path
            try FileManager.default.createDirectory(atPath: odd, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: odd + "/ccc", withDestinationPath: exe.path)
            #expect(installer([]).status(executable: exe.path, path: "/usr/bin:\(odd)") == .installed(path: odd + "/ccc"))
        }
    }
}
