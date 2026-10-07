import Foundation
import Testing

@testable import CCCKit

/// Item 22: the verb list as data, and the guards that keep it honest.
///
/// The defect this exists for is not "no per-verb help" — it is that the
/// only description of any verb was a 126-line string literal no test could
/// reach, so `update`'s entry sat a release stale saying "the repo's default
/// branch" and `ccc spawn --help` answered "unknown flag '--help' for
/// spawn". A string nothing reads is a string nothing keeps true. These
/// tests are what now reads it.
@Suite struct ManifestTests {
    /// The dispatch switch's words, transcribed from `CLI.run`. This is the
    /// one place the two lists meet, and it is on purpose: a verb added to
    /// the switch and not to the manifest fails here, which is the only
    /// mechanism that stops the manifest going stale the way the string
    /// literal did.
    static let dispatched = [
        "hosts", "list", "archive", "unarchive", "pin", "unpin", "watch", "hook",
        "spawn", "new", "attach", "detach", "stop", "rm", "forget",
        "base", "merge", "update", "fetch", "pull", "ff", "push", "shell", "clear",
        "snapshot", "send", "select", "copy", "links", "focus", "resize",
        "peek", "capture", "pixel", "geometry", "theme", "window",
        "stats", "replay", "bench", "version", "install-cli",
    ]

    @Test func everyDispatchedVerbIsInTheManifest() {
        for word in Self.dispatched {
            #expect(CommandManifest.verb(named: word) != nil, "`ccc \(word)` dispatches and the manifest does not know it")
        }
    }

    @Test func everyManifestVerbIsDispatched() {
        for verb in CommandManifest.verbs {
            for word in [verb.name] + verb.aliases {
                #expect(Self.dispatched.contains(word), "the manifest offers `ccc \(word)` and nothing dispatches it")
            }
        }
    }

    /// Each verb's synopsis has to begin with its own name, or `ccc <verb>
    /// --help` prints a command that is not the one asked about.
    @Test func aSynopsisNamesItsOwnVerb() {
        for verb in CommandManifest.verbs {
            let first = verb.synopsis.first ?? ""
            #expect(first.hasPrefix(verb.name) || verb.aliases.contains(where: { first.hasPrefix($0) }),
                    "`\(verb.name)`'s synopsis starts \(first)")
            #expect(!verb.about.isEmpty, "`\(verb.name)` says nothing about itself")
            #expect(CommandManifest.groups.contains(verb.group), "`\(verb.name)` is in unknown group '\(verb.group)'")
        }
    }

    /// A `--json` claim must be in the synopsis, and a synopsis `--json`
    /// must have its shape described. This is the twin rule pointed at the
    /// documentation: a verb that answers JSON without saying what shape
    /// leaves an agent to run it and guess.
    @Test func everyJSONVerbSaysItsShape() {
        for verb in CommandManifest.verbs {
            let offersJSON = verb.synopsis.contains { $0.contains("--json") }
            if offersJSON {
                #expect(verb.json != nil, "`ccc \(verb.name)` takes --json and the manifest does not say what it answers")
            } else {
                #expect(verb.json == nil || verb.name == "hosts",
                        "`ccc \(verb.name)` describes a --json answer its synopsis does not offer")
            }
        }
    }

    /// `--repo` and `ff`, read by a test on the day they land rather than a
    /// release later. The rule this obeys is the one `update`'s help broke:
    /// a string nothing reads is a string nothing keeps true.
    @Test func pullCarriesTheRepoFormAndTheFFAlias() throws {
        let pull = try #require(CommandManifest.verb(named: "pull"))
        #expect(CommandManifest.verb(named: "ff")?.name == "pull", "`ccc ff` must reach `pull`, not a second verb")
        let text = CommandManifest.help(for: pull)
        #expect(text.contains("ccc pull --repo [<path>] [--json]"))
        #expect(text.contains("(also: ff)"))
        // Why the form exists at all — the ordering that makes the ref form
        // unusable at the end of a reap.
        #expect(text.contains("BEFORE `git worktree remove`"))
        #expect(text.contains("{ repo, pulled, said }"))
        // Its twin on the fetch side: the pair is only useful together.
        let fetch = try #require(CommandManifest.verb(named: "fetch"))
        let fetchText = CommandManifest.help(for: fetch)
        #expect(fetchText.contains("ccc fetch --repo [<path>] [--json]"))
        #expect(fetchText.contains("{ repo, fetched, said }"))
        #expect(fetchText.contains("that repository's ROOT"))
    }

    /// **Where the base is, and which base it is** (2026-09-17). Both
    /// strings had readers act on them and both were wrong: `pull` said it
    /// runs in the MAIN checkout (it now runs where the base is checked
    /// out), and `push --base` said "the repo's default branch" while the
    /// code has pushed `WorktreeInfo.base` — the *recorded* base — since
    /// the day bases could be recorded. A commander read the second one
    /// and reported ccc as pushing the wrong ref for its loop. So the
    /// strings get a test, which is the rule this repo already earned.
    @Test func theGitVerbsSayWhereTheyActAndOnWhat() throws {
        let merge = try #require(CommandManifest.verb(named: "merge"))
        let mergeText = CommandManifest.help(for: merge)
        #expect(mergeText.contains("WHERE THAT BASE IS CHECKED OUT"))
        #expect(mergeText.contains("the worktree holding it"))
        let pull = try #require(CommandManifest.verb(named: "pull"))
        let pullText = CommandManifest.help(for: pull)
        #expect(pullText.contains("WHERE THE BASE"))
        #expect(!pullText.contains("Runs in the MAIN"), "pull no longer refuses a base a worktree holds")
        let push = try #require(CommandManifest.verb(named: "push"))
        let pushText = CommandManifest.help(for: push)
        #expect(pushText.contains("ITS BASE"))
        #expect(pushText.contains("recorded for the branch"))
        #expect(pushText.contains("needs no checkout anywhere"))
    }

    /// **`rm` says when the branch survives** (2026-09-17). The rule is
    /// eleven tests old (`CutWorktreeTests`) and was in no string: the
    /// help said "when the harness says that is safe" and left the branch
    /// unmentioned, so a commander hand-rolling its reap could not know
    /// that `ccc rm` never deletes work that has not landed — which is
    /// "the difference between `rm` being safe to reach for and being a
    /// thing you check first", in the words of the commander that reached
    /// for git instead.
    @Test func rmSaysWhatBecomesOfTheBranch() throws {
        let rm = try #require(CommandManifest.verb(named: "rm"))
        let text = CommandManifest.help(for: rm)
        #expect(text.contains("THE BRANCH GOES ONLY IF ITS COMMITS ARE SOMEWHERE ELSE"))
        #expect(text.contains("recorded"), "a non-default base counts, and that is the point")
        #expect(text.contains("branchDeleted"), "the JSON key the answer carries it in")
    }

    @Test func namesAreUniqueAcrossVerbsAndAliases() {
        var seen = Set<String>()
        for verb in CommandManifest.verbs {
            for word in [verb.name] + verb.aliases {
                #expect(seen.insert(word).inserted, "'\(word)' names two verbs")
            }
        }
    }

    // MARK: the rendered faces

    @Test func usageCarriesEveryVerbAndItsOwnDiscovery() {
        let text = CommandManifest.usage()
        for verb in CommandManifest.verbs {
            #expect(text.contains("ccc \(verb.name)"), "usage does not mention `ccc \(verb.name)`")
        }
        // The three doors an agent needs, named where a person will see them.
        #expect(text.contains("--help"))
        #expect(text.contains("--llms"))
        #expect(text.contains("--schema"))
    }

    /// A wrapped synopsis line must not read as a second command. Before
    /// the continuation rule, `ccc spawn`'s four wrapped lines rendered as
    /// four `ccc` commands, three of which do not exist.
    @Test func aWrappedSynopsisIsOneCommand() throws {
        let spawn = try #require(CommandManifest.verb(named: "spawn"))
        let text = CommandManifest.help(for: spawn)
        #expect(text.contains("  ccc spawn [--host"))
        #expect(text.contains("            [--permission-mode"), "a continuation must not get its own `ccc`")
        #expect(!text.contains("ccc       [--permission-mode"))
        // And a verb whose synopsis really is several commands keeps them.
        let hosts = try #require(CommandManifest.verb(named: "hosts"))
        let hostsText = CommandManifest.help(for: hosts)
        #expect(hostsText.contains("ccc hosts discover"))
        #expect(hostsText.contains("ccc hosts mute|unmute"))
    }

    /// `--channels` (hail's ask, 2026-09-08) is a research-preview flag the
    /// harness hides from its own `--help`, so ccc's help is the only place
    /// it is written down — and a string no test reads is a string nothing
    /// keeps true.
    @Test func spawnNamesTheChannelsFlagAndWhatItIsFor() throws {
        let spawn = try #require(CommandManifest.verb(named: "spawn"))
        let text = CommandManifest.help(for: spawn)
        #expect(text.contains("[--channels <entry>]..."))
        #expect(text.contains("plugin:hail@hail"))
        #expect(text.contains("respawnFlags"), "the reason it belongs at launch")
    }

    @Test func aVerbsHelpCarriesItsJSONAndItsExit() throws {
        let update = try #require(CommandManifest.verb(named: "update"))
        let text = CommandManifest.help(for: update)
        #expect(text.contains("ccc update <ref> [--ask] [--keep-conflicts] [--json]"))
        // Two exits that promise opposite things about the tree.
        #expect(text.contains("3 when --keep-conflicts left it mid-merge"))
        // The correction that started all of this: the base, not the
        // default branch, and the sentence that sends a brief here.
        #expect(text.contains("recorded, else the repo's default branch"))
        #expect(text.contains("never `git merge`"))
        #expect(text.contains("--json:"))
        #expect(text.contains("exit:"))
        // A verb with no --json says so rather than leaving it blank.
        let detach = try #require(CommandManifest.verb(named: "detach"))
        #expect(CommandManifest.help(for: detach).contains("not answered by this verb"))
    }

    /// `--llms` is one document: the conventions once at the top, then
    /// every verb under its group. The conventions are the part a per-verb
    /// page cannot carry — exit codes, `<ref>`, where errors go.
    @Test func llmsStatesTheConventionsOnceAndThenEveryVerb() {
        let text = CommandManifest.llms()
        #expect(text.contains("## Conventions"))
        #expect(text.contains("`id` (this Mac) or `host:id`"))
        #expect(text.contains("Exit 0 is success"))
        #expect(text.contains("prefixed `ccc: `"))
        for group in CommandManifest.groups {
            #expect(text.contains("## \(group)"), "no section for '\(group)'")
        }
        for verb in CommandManifest.verbs {
            #expect(text.contains("### ccc \(verb.name)"), "`\(verb.name)` is missing from --llms")
        }
    }

    /// The manifest goes out as JSON, which is the "manifest an agent can
    /// read" the whole item asked for. Round-tripping it is the check that
    /// it is data and not prose in a trench coat.
    @Test func theManifestIsJSONAnAgentCanRead() throws {
        let data = try JSONEncoder().encode(CommandManifest.verbs)
        let back = try JSONDecoder().decode([CommandManifest.Verb].self, from: data)
        #expect(back == CommandManifest.verbs)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(object.count == CommandManifest.verbs.count)
        // Field names are the wire: an agent keys off these.
        let spawn = try #require(object.first { $0["name"] as? String == "spawn" })
        #expect(spawn["synopsis"] is [Any])
        #expect(spawn["json"] is String)
        #expect(spawn["exit"] is String)
        #expect((spawn["aliases"] as? [String]) == ["new"])
    }

    /// **Every event kind is named where a reader looks for it.** The
    /// rule cost a merge once already (`CLAUDE.md`, "Rules earned"):
    /// `ccc update`'s help went a release stale because it was a string
    /// no test read. `ccc watch`'s kinds are that same shape — one list,
    /// repeated in the manifest that prints `--help` and in README — and
    /// `landed` was added on 2026-09-07, which is exactly the moment such
    /// a list is easy to keep and cheap to forget.
    ///
    /// It walks `SessionEvent.Kind.allCases` rather than a literal, so a
    /// kind added tomorrow fails here until it is documented. The list is
    /// a type; that is the whole trick.
    @Test func everyEventKindIsDocumented() throws {
        let about = (CommandManifest.verb(named: "watch")?.about ?? []).joined(separator: " ")
        #expect(!about.isEmpty, "the watch verb has left the manifest; this guard is now blind")
        let readme = try DocsGuardTests.read("README.md")
        var missing: [String] = []
        for kind in SessionEvent.Kind.allCases {
            if !about.contains(kind.rawValue) { missing.append("manifest: \(kind.rawValue)") }
            if !readme.contains(kind.rawValue) { missing.append("README.md: \(kind.rawValue)") }
        }
        #expect(
            missing.isEmpty,
            """
            \(missing.joined(separator: "; ")) — a kind `ccc watch` can print \
            and nothing documents. Name it in the manifest's `about`, which is \
            what `ccc watch --help` prints, and in README's verb list.
            """)
    }
}
