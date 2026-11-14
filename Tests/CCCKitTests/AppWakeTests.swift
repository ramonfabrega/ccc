import Foundation
import Testing

@testable import CCCKit

/// `AppWake`: the CLI bringing ccc.app up when nothing serves the socket.
/// Every dependency is injected, so nothing here launches anything.
@Suite struct AppWakeTests {
    /// Counts calls and flips "serving" after an open, from Sendable closures.
    private final class World: @unchecked Sendable {
        private let lock = NSLock()
        private var _opened: [String] = []
        private var _up = false
        var comesUp = true
        var opened: [String] { lock.withLock { _opened } }
        var up: Bool { lock.withLock { _up } }
        func open(_ bundle: String) { lock.withLock { _opened.append(bundle); if comesUp { _up = true } } }
    }

    private let sock = "/Users/x/Library/Application Support/ccc/control.sock"
    private let app = "/Users/x/Applications/ccc.app"

    @Test func aServingCCCIsLeftAlone() async {
        let world = World()
        let refusal = await AppWake.wake(socket: sock, standardSocket: sock, bundle: app, executable: "\(app)/Contents/MacOS/ccc",
                                         serving: { true }, open: { world.open($0); return nil })
        #expect(refusal == nil)
        #expect(world.opened.isEmpty)
    }

    @Test func theAppIsOpenedOnceAndWaitedFor() async {
        let world = World()
        let refusal = await AppWake.wake(socket: sock, standardSocket: sock, bundle: app, executable: "\(app)/Contents/MacOS/ccc",
                                         patience: 2, interval: 0.01,
                                         serving: { world.up }, open: { world.open($0); return nil })
        #expect(refusal == nil)
        #expect(world.opened == [app])
    }

    /// A private socket (a test's, a proof's) is one the app would never
    /// answer on, so the user's app is not started for it.
    @Test func aPrivateSocketWakesNothing() async {
        let world = World()
        let refusal = await AppWake.wake(socket: "/tmp/private.sock", standardSocket: sock, bundle: app,
                                         executable: "\(app)/Contents/MacOS/ccc",
                                         serving: { false }, open: { world.open($0); return nil })
        #expect(refusal == .privateSocket("/tmp/private.sock"))
        #expect(world.opened.isEmpty)
        #expect("\(refusal!)".contains("CCC_CONTROL_SOCKET"))
    }

    /// A development binary is in no bundle, and says which binary it is.
    @Test func aBareBinaryHasNoAppToStart() async {
        let refusal = await AppWake.wake(socket: sock, standardSocket: sock, bundle: nil, executable: "/repo/.build/debug/ccc",
                                         serving: { false }, open: { _ in nil })
        #expect(refusal == .noBundle("/repo/.build/debug/ccc"))
        #expect("\(refusal!)".contains("/repo/.build/debug/ccc is not in an app bundle"))
    }

    @Test func aFailedOpenCarriesItsReason() async {
        let refusal = await AppWake.wake(socket: sock, standardSocket: sock, bundle: app, executable: "\(app)/Contents/MacOS/ccc",
                                         serving: { false }, open: { _ in "The application cannot be opened" })
        #expect(refusal == .openFailed("The application cannot be opened"))
    }

    @Test func anAppThatNeverServesIsReported() async {
        let world = World()
        world.comesUp = false
        let refusal = await AppWake.wake(socket: sock, standardSocket: sock, bundle: app, executable: "\(app)/Contents/MacOS/ccc",
                                         patience: 0.1, interval: 0.01,
                                         serving: { world.up }, open: { world.open($0); return nil })
        #expect(refusal == .neverServed(app, 0.1))
        #expect(world.opened == [app])
    }

    /// Started, never brought forward, and told it is resident: the words
    /// the app's launch reads to keep its window closed.
    @Test func theAppIsStartedInTheBackgroundAndToldSo() {
        #expect(AppWake.argv(bundle: app) == ["/usr/bin/open", "-g", "--env", "CCC_RESIDENT=1", app])
        #expect(AppWake.residentKey == "CCC_RESIDENT")
    }

    /// The standard path ignores the override; the default path obeys it.
    @Test func theStandardSocketIsTheOneTheAppServes() {
        #expect(ControlSocket.standardPath.hasSuffix("/ccc/control.sock"))
    }
}
