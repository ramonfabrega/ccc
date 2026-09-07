import Foundation
import Testing

/// The documents' own rules, enforced rather than trusted.
///
/// `docs/MILESTONES.md` carried one heading in 869 lines. That is not a
/// length problem, it is an addressing one: `docs/DESIGN.md` is cited as
/// §4a from CLAUDE.md, the queue and the wiki, and stays a page per
/// decision; a file with no headings can only ever be cited whole, and a
/// nested bullet is a frictionless append target — a clause joins an
/// existing bullet without anyone having to choose where it goes. It
/// reached 60,814 bytes because nothing failed when it grew. Borrowed
/// wholesale from attrition's `crates/sim/src/docs_guard.rs`, whose own
/// queue hit 409 lines two days after declaring that it subtracts: *a rule
/// that is only prose is a rule a tired afternoon defeats.*
///
/// Three rules there transfer; the fourth does not. Attrition's "CLAUDE.md
/// carries rules, not findings" is three lexical patterns — a `0x` hex
/// address, a literal `@00`, a `§` before a digit — and it guards a real
/// hazard *there*: a subagent inherits a decompiler address it cannot
/// re-derive. Run that blade on ours and its only hits are the three
/// `docs/DESIGN.md §N` cross-references that let a session read 142 lines
/// instead of 605. The hazard does not exist here, so the rule is not
/// ported — and `citationsResolve` below inverts it, protecting the
/// citations rather than banning them.
@Suite struct DocsGuardTests {
    /// Bytes, per `## ` section. The unit is the section because that is
    /// what a session reads: an item names §4a or a slice, never the file.
    /// Attrition's number, adopted unchanged — measured against this
    /// corpus the day the headings landed, the largest section anywhere
    /// was HARNESS.md's "Documented" at 10,553 B, so the ceiling binds on
    /// bloat rather than on any section's honest size. The text before the
    /// first `## ` counts as a section too: that is where the 60,814 bytes
    /// were hiding.
    ///
    /// **A `### ` rolls up into its parent `## `, deliberately.** Addressing
    /// and measuring therefore disagree about what a section is: §6a has an
    /// address of its own (`citationsResolve` reads both levels) and no byte
    /// budget of its own. That is the right way round — a reader who opens
    /// §6 reads 6a with it, so 6a is not a separate sitting — but it means
    /// **adding a `### ` does not get a section under the ceiling.** Only a
    /// new `## ` does. Whoever splits to get under the bound gets told here
    /// rather than discovering it.
    static let sectionCeiling = 16_000

    /// The sections over the ceiling, pinned at their size, each free to
    /// shrink and never to grow. **Empty, and it should stay that way** —
    /// unlike attrition, which adopted the ceiling with seven sections
    /// already over it, ccc got its headings first, so there is nothing to
    /// ratchet down. A row added here is a decision to carry a section
    /// that a session cannot read in one sitting; split it instead.
    static let over: [String: Int] = [:]

    /// The queue's whole length, in lines. **Bound the unit, not the file:**
    /// this is the number of items the board expects to hold live, times the
    /// honest size of one, plus the frontier — not a percentage over
    /// whatever the file happens to measure today, which would encode
    /// today's accident. Here that is ~12 items at ~11 lines each (an item
    /// is a paragraph: what it is, what is known, what is blocked), plus
    /// ~15 for the frontier and the entry rule.
    ///
    /// The bound must bite on bloat and never on an item's honest size — a
    /// session golfing lines instead of deleting stories is the bound set
    /// wrong, which is why attrition raised its own 180 to 200 when 180 bit
    /// on a board of ~20 items at five or six lines each. Both estimates
    /// made for this file before it was written (106, then 150) came in
    /// under 156, because both anchored to the old file's size instead of
    /// to what an item costs.
    ///
    /// **Raised 200 → 230 on 2026-09-06, because the model under it was
    /// wrong from the start.** 200 was "~12 items at ~11 lines"; this board
    /// has never held an 11-line item. Measured the day it bit: 7 live items
    /// averaging 19 lines, and it read 226 *after* a pass that deleted
    /// finished stories — item 17's shipped slices, item 6's settled
    /// numbers, and three paragraphs of "Later" whose argument had already
    /// moved to `docs/EVIDENCE.md` and `docs/HARNESS.md`. An item is bigger
    /// here than the estimate allowed because this file's own entry rule
    /// makes it so: *an item inlines its conclusion*, so a cold session can
    /// start from this file and CLAUDE.md without opening a third thing.
    /// The new number is the observed honest size (7 × 19) plus the
    /// frontier, "Later" and the entry rule, plus room for two more items —
    /// anchored to what an item costs, which is what the paragraph above
    /// asked for and the old number did not do.
    static let queueLines = 230

    private static let docs = [
        "docs/DESIGN.md", "docs/HARNESS.md", "docs/TERMINAL.md",
        "docs/CHECKS.md", "docs/QUEUE.md", "docs/EVIDENCE.md",
    ]

    static var root: URL {
        URL(filePath: #filePath)          // Tests/CCCKitTests/DocsGuardTests.swift
            .deletingLastPathComponent()  // Tests/CCCKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the repository
    }

    /// `name` is relative to the repository root, so a failure message
    /// names a path a reader can open.
    static func read(_ name: String) throws -> String {
        try String(contentsOf: root.appending(path: name), encoding: .utf8)
    }

    /// `(heading, bytes)` for every `## ` section, the preamble included
    /// under the name the failure message should print.
    private static func sections(_ text: String) -> [(String, Int)] {
        var out: [(String, Int)] = []
        var heading = "(preamble)"
        var bytes = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                out.append((heading, bytes))
                heading = String(line)
                bytes = 0
            } else {
                bytes += line.utf8.count + 1
            }
        }
        out.append((heading, bytes))
        return out
    }

    @Test(arguments: docs)
    func sectionsStayUnderTheCeiling(_ name: String) throws {
        for (heading, bytes) in Self.sections(try Self.read(name)) {
            let key = "\(name)  \(heading)"
            if let pin = Self.over[key] {
                #expect(
                    bytes <= pin,
                    """
                    \(key) is \(bytes) B, over its pin of \(pin). A pinned \
                    section may only shrink. Split it, or move its evidence \
                    to docs/EVIDENCE.md first.
                    """)
            } else {
                #expect(
                    bytes <= Self.sectionCeiling,
                    """
                    \(key) is \(bytes) B, over the \(Self.sectionCeiling) B \
                    ceiling. A session reads the section, not the file — \
                    split it with a `## ` heading, which costs a reader \
                    nothing, or move its evidence to docs/EVIDENCE.md.
                    """)
            }
        }
    }

    /// The queue is bounded; `docs/EVIDENCE.md` deliberately is not. An
    /// unbounded file is safe only when it is addressed — every section
    /// there carries a `## ` heading and is reached by grep, never read
    /// whole — and the queue is the opposite: it is read whole, every
    /// session, so its length is a tax on every session.
    @Test func theQueueIsBounded() throws {
        let text = try Self.read("docs/QUEUE.md")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(
            lines <= Self.queueLines,
            """
            docs/QUEUE.md is \(lines) lines, over \(Self.queueLines). A \
            finished item leaves — its commands and numbers go to \
            docs/EVIDENCE.md under a heading, its argument to the lore \
            wiki. Delete, do not golf.
            """)
    }

    /// A surface doc's `Rules` section carries the queue's bound in
    /// miniature (`docs/DESIGN.md` §9). It exists so a rule that has
    /// earned its second instance can be read before acting on that
    /// surface, rather than grepped out of `docs/EVIDENCE.md`'s tail —
    /// and it is bounded for the same reason the queue is: a section that
    /// can grow without cost becomes a second EVIDENCE, which is the
    /// problem it was built to solve.
    ///
    /// Twelve lines is about six rules with their citations. Promotion is
    /// therefore subtractive too: the twelfth rule displaces one whose
    /// surface no longer exists or whose lesson has become structural.
    static let rulesLines = 12

    @Test(arguments: docs)
    func aRulesSectionIsBounded(_ name: String) throws {
        let text = try Self.read(name)
        guard let start = text.range(of: "\n## Rules\n") else { return }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        #expect(
            lines <= Self.rulesLines,
            """
            \(name)'s Rules section is \(lines) lines, over \(Self.rulesLines). \
            A rule graduates on its second instance and displaces one that has \
            stopped earning its line; the evidence stays in docs/EVIDENCE.md \
            either way (docs/DESIGN.md §9).
            """)
    }

    /// Every rule cites the evidence that proved it, or it is an opinion
    /// wearing a rule's clothes. The citation is a quoted EVIDENCE
    /// heading, which is also what makes it greppable from there.
    @Test(arguments: docs)
    func everyRuleCitesItsEvidence(_ name: String) throws {
        let text = try Self.read(name)
        guard let start = text.range(of: "\n## Rules\n") else { return }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        let uncited = String(rest[..<end])
            .components(separatedBy: "\n- ")
            .dropFirst()
            .filter { !$0.contains("(\"") }
        #expect(uncited.isEmpty, "\(name): a rule with no evidence heading cited: \(uncited.first ?? "")")
    }

    /// A finished item leaves; it is not struck through. A struck line is a
    /// story the queue kept, and the stories are what grew the paragraphs.
    @Test(arguments: docs)
    func nothingIsStruckThrough(_ name: String) throws {
        let struck = try Self.read(name)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.element.contains("~~") }
            .map { "\(name):\($0.offset + 1)" }
        #expect(
            struck.isEmpty,
            "struck-through text in \(struck.joined(separator: ", ")) — delete it; docs/EVIDENCE.md keeps what was proved")
    }

    /// Every section carries a heading a reader can cite. A `#` title and
    /// `## ` sections; nothing may hide in a preamble longer than a
    /// paragraph — which is exactly how MILESTONES.md grew to 60 KB with
    /// one heading. CHECKS.md is exempt: it is a single table with its
    /// rules under it, and a table is not a section that wants splitting.
    @Test(arguments: docs.filter { $0 != "docs/CHECKS.md" })
    func nothingHidesInThePreamble(_ name: String) throws {
        let text = try Self.read(name)
        let preamble = Self.sections(text).first!.1
        #expect(
            preamble <= 2_000,
            """
            \(name)'s text before the first `## ` is \(preamble) B. A \
            preamble is the file's opening paragraph; anything longer wants \
            a heading so it can be cited and bounded.
            """)
    }

    /// DESIGN.md's section numbers are addresses, cited from CLAUDE.md, the
    /// queue and the lore wiki. They are appended to, never reordered and
    /// never renumbered — which is why §5 sits after §8. This resolves
    /// every `§N` cited anywhere against DESIGN's own headings, so a
    /// future session that tidies the numbering finds out here rather than
    /// leaving a trail of citations pointing at the wrong decision.
    @Test func citationsResolve() throws {
        let design = try Self.read("docs/DESIGN.md")
        // Both levels define an address: §6a is an amendment under §6 and
        // sits at `### `, while every other decision is a `## `. The
        // ceiling above counts a `###` as body, which is right for what a
        // session reads in one sitting; a citation is a different question.
        let defined = Set(
            design.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("## ") || line.hasPrefix("### ") else { return nil }
                let rest = line.drop { $0 == "#" }.dropFirst()
                let number = rest.prefix { $0.isNumber || $0.isLowercase }
                return number.isEmpty ? nil : String(number)
            })
        #expect(!defined.isEmpty, "DESIGN.md has no numbered sections; has the heading style changed?")

        var dangling: [String] = []
        for name in Self.docs + ["CLAUDE.md", "README.md", "RELEASES.md"] {
            let text = try Self.read(name)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var rest = Substring(line)
                while let sign = rest.firstIndex(of: "§") {
                    rest = rest[rest.index(after: sign)...]
                    let cited = rest.prefix { $0.isNumber || $0.isLowercase }
                    guard let first = cited.first, first.isNumber else { continue }
                    if !defined.contains(String(cited)) {
                        dangling.append("\(name):\(i + 1) cites §\(cited)")
                    }
                }
            }
        }
        #expect(
            dangling.isEmpty,
            """
            \(dangling.joined(separator: "; ")) — DESIGN.md defines \
            \(defined.sorted().joined(separator: ", ")). Section numbers are \
            addresses: append, never reorder, never renumber.
            """)
    }
}
