# Releasing ccc

The fleet's release flow (`~/code/fun/disk/RELEASES.md`, which is mux's),
adapted to a private two-Mac tool: a version, a tag, a GitHub Release with
the notarized app attached, and a two-key CDN feed that makes installed
copies update themselves. No changesets, no CI, no ceremony. **Merging ≠
releasing**: work lands on the branch; a release is a separate act.

Why this and not a copied bundle: air cannot be pushed to (no Remote Login),
so every update is a pull, and an ad-hoc-signed app on another Mac churns
its identity on every rebuild (Gatekeeper, TCC, the login item). Developer
ID signing plus Sparkle is the fleet's answer, and since 2026-09-02 it costs
no script at all: the flow lives in `ota`, which was extracted from this
repo's copy of it (docs/DESIGN.md §6 and §6a). `ota` must be on PATH —
install it from `~/code/fun/ota` with its own `scripts/install`.

## Two lanes

- **Dev, on studio:** `scripts/install` — release build, ad-hoc sign,
  `~/Applications/ccc.app`, `ccc` on PATH as a symlink into the bundle.
  This Mac only. A dev bundle carries no Sparkle keys (`ota bundle`
  without `--feed`), which is the one definition of the lane: it never
  polls the CDN, `ccc version` says `dev`, the status item and window
  read `ccc·dev`, and "Check for Updates…" is disabled with that reason.
  `scripts/install --dist` installs the last cut instead
  (the notarized app from `.build/dist`), so the daily driver on studio is
  the same bytes air runs.
- **Release, for every Mac, studio included:** the steps below. Air only
  ever sees a notarized zip, first from the CDN by hand, then through
  Sparkle; studio installs each cut with `--dist` and updates the same way.

## Versioning

SemVer `vMAJOR.MINOR.PATCH`, pre-1.0 rules. The marketing version lives in
the `VERSION` file (`ota bundle` stamps `CFBundleShortVersionString`, `ota
release` names the zip). The build number (`CFBundleVersion`) is the git commit
count: monotonic, zero upkeep, and what Sparkle compares — so a dev build
always outranks the released zip and is never offered a downgrade. Corollary:
cut from the branch master fast-forwards to, and rebuild the dev copy after.

## Cutting a release

1. **Bump `VERSION`** and commit.
2. **Tag** (annotated) and push the tag:
   ```sh
   git tag -a v0.1.0 -m "ccc v0.1.0"
   git push origin v0.1.0
   ```
3. **Cut it.** One command does the build, the bundle, Developer ID signing,
   notarization, stapling, the zip, the appcast, both CDN keys and the
   live-feed check (Developer ID cert, the `mux-notary` notarytool profile
   and the fleet's Sparkle EdDSA key are all in the Studio's Keychain):
   ```sh
   scripts/package                    # → .build/dist/ccc-vX.Y.Z.zip
   ```
   It stops before the first signature if the Keychain's EdDSA key no longer
   matches the app's pinned `SUPublicEDKey`, or if the bundle carries no key
   at all (a dev cut can never accept an update, so it can never be
   released). After `generate_appcast` it asserts exactly one `<item>` — see
   below — and rewrites the enclosure to the stable key
   `ccc/ccc-latest.zip`. Then it overwrites both CDN keys, **zip first**, and
   finishes by fetching the live feed and comparing its `length=` to the
   zip's real `content-length`. A failure there exits non-zero and names
   both numbers.

   `scripts/package --no-publish` stops after the appcast and prints the two
   `share` lines instead of running them. `scripts/package --ad-hoc` is a
   packaging test on this Mac and refuses to notarize or publish at all.
4. **GitHub Release** off the tag, with the zip (the durable record of every
   version; the CDN carries only the latest):
   ```sh
   gh release create v0.1.0 .build/dist/ccc-v0.1.0.zip --generate-notes
   ```
5. **Install the cut on studio** (`scripts/install --dist`) so the daily
   driver is the released build and Sparkle has nothing to offer it.

Step 3's last act is the check that used to be steps 5 and 6 by hand. To run
it again later, against whatever the CDN is serving right now:
```sh
ota verify --feed ccc
```

## The feed must be single-item, and that is correctness

Every item's enclosure points at the *same* stable key, so only the newest
can be truthful — an older item keeps its own `length=` and EdDSA signature
while describing bytes that key no longer holds. `ota release` archives every
other zip, deletes the appcast, regenerates from empty and then asserts one
item; `ota verify --appcast <path>` runs the same check on a local feed.

`--maximum-versions 1` does **not** guarantee it, and the trigger is narrower
than "sometimes": `generate_appcast` keeps an older item whose *hardware
requirements the newer item does not cover*. Reproduced deliberately from
disk's v0.6.0 — an arm64-only predecessor beside a universal successor
publishes two items, while a same-arch predecessor is pruned normally. ccc is
arm64-only, so ccc cannot hit this today; **the first universal ccc cut is
the one that could**, and the guard is what makes it a failed release rather
than a feed that lies.

## First install on a new Mac

Download `https://cdn.ramonfabrega.com/ccc/ccc-latest.zip`, open it, drag
`ccc.app` to `~/Applications`, launch. On first launch the app offers to
install the `ccc` command — a symlink into the bundle, in the first of
`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` that is writable
(VS Code's pattern). "Install ‘ccc’ Command…" in the app menu and
`ccc install-cli` do the same later; by hand it is
```sh
ln -sf ~/Applications/ccc.app/Contents/MacOS/ccc /opt/homebrew/bin/ccc
```
From then on the app updates itself; the symlink survives, since Sparkle
replaces the bundle at the same path. `ccc version` says which build the
command is; `ccc stats` says which build the app on the socket is, and
`ccc hosts check` says which build each host's ccc is — skew is a number
on the row, not a decode failure.
