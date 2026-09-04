import Foundation
import Testing

@testable import CCCKit

/// The launch mode off the same flags (2026-09-04, the user's word via
/// lore): which worker stops at its first permission prompt. "As
/// launched" and nothing more — a runtime toggle never reaches the flags.
@Suite struct JobPermissionModeTests {
    @Test func theModeIsReadAsLaunched() {
        let json = #"{"detail":"x","respawnFlags":["--rc","--name","lore","--permission-mode","auto","--model","opus"]}"#
        let info = JobInfo.decode(Data(json.utf8))
        #expect(info?.permissionMode == "auto")
        #expect(info?.asksForPermission == false)
    }

    /// The fleet's commanders as measured: `--rc`, a name, a model, no mode.
    /// That is the harness's default, which asks.
    @Test func noModeIsTheOneThatAsks() {
        let json = #"{"detail":"x","respawnFlags":["--rc","--name","ccc","--model","opus[1m]"]}"#
        let info = JobInfo.decode(Data(json.utf8))
        #expect(info?.permissionMode == nil)
        #expect(info?.asksForPermission == true)
        #expect(JobInfo(permissionMode: "plan").asksForPermission)
        #expect(JobInfo(permissionMode: "bypassPermissions").asksForPermission == false)
    }

    /// A flag with nothing usable after it is no mode; the row says
    /// nothing rather than something wrong.
    @Test func aDanglingFlagIsNoMode() {
        let json = #"{"detail":"x","respawnFlags":["--name","n","--permission-mode"]}"#
        #expect(JobInfo.decode(Data(json.utf8))?.permissionMode == nil)
        let next = #"{"detail":"x","respawnFlags":["--permission-mode","--rc"]}"#
        #expect(JobInfo.decode(Data(next.utf8))?.permissionMode == nil)
    }

    /// Across the hop from an older ccc the key is absent, and that reads
    /// as "unknown", never as a decode failure.
    @Test func anOlderRowHasNoMode() throws {
        let wire = Data(#"{"detail":"x","remoteControl":true}"#.utf8)
        let info = try JSONDecoder().decode(JobInfo.self, from: wire)
        #expect(info.permissionMode == nil)
        #expect(info.remoteControl)
    }
}
