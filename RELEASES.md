# Releasing ccc

The fleet's release flow (`~/code/fun/disk/RELEASES.md`, which is mux's),
adapted to a private two-Mac tool: a version, a tag, a GitHub Release with
the notarized app attached, and a two-key CDN feed that makes installed
copies update themselves. No changesets, no CI, no ceremony. **Merging ≠
releasing**: work lands on the branch; a release is a separate act.

Why this and not a copied bundle: air cannot be pushed to (no Remote Login),
so every update is a pull, and an ad-hoc-signed app on another Mac churns
its identity on every rebuild (Gatekeeper, TCC, the login item). Developer
ID signing plus Sparkle is the fleet's answer and it costs one script
(docs/DESIGN.md §6).

## Two lanes

- **Dev, on studio:** `scripts/install` — release build, ad-hoc sign,
  `~/Applications/ccc.app`, `ccc` on PATH as a symlink into the bundle.
  This Mac only. A dev bundle carries no Sparkle keys (`make-bundle`
  without `--release`), which is the one definition of the lane: it never
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
the `VERSION` file (make-bundle stamps `CFBundleShortVersionString`, package
names the zip). The build number (`CFBundleVersion`) is the git commit
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
3. **Build the notarized artifact** (Developer ID cert, the `mux-notary`
   notarytool profile, and the fleet's Sparkle EdDSA key are all in the
   Studio's Keychain; `package` aborts if the key stops matching the app's
   pinned `SUPublicEDKey`):
   ```sh
   scripts/package                    # → .build/dist/ccc-vX.Y.Z.zip
   ```
   This also regenerates the Sparkle appcast in
   `~/Library/Application Support/ccc-releases/` — single item, EdDSA
   signed, enclosure pointed at the stable key `ccc/ccc-latest.zip`.
4. **GitHub Release** off the tag, with the zip (the durable record of every
   version; the CDN carries only the latest):
   ```sh
   gh release create v0.1.0 .build/dist/ccc-v0.1.0.zip --generate-notes
   ```
5. **Publish the feed** — the two `share` lines `package` prints. Both keys
   are overwritten every release and `--permanent` keeps them out of the
   CDN's 30-day sweep:
   ```sh
   share .build/dist/ccc-vX.Y.Z.zip ccc/ccc-latest.zip --permanent
   share "$HOME/Library/Application Support/ccc-releases/appcast.xml" ccc/appcast.xml --permanent
   ```
6. **Verify the live feed** the way Sparkle will read it. The appcast's
   `length` must equal the zip's content-length or every installed copy
   fails the update:
   ```sh
   curl -s https://cdn.ramonfabrega.com/ccc/appcast.xml | grep -E 'sparkle:version|enclosure'
   curl -sI https://cdn.ramonfabrega.com/ccc/ccc-latest.zip | grep -i 'content-length'
   ```
7. **Install the cut on studio** (`scripts/install --dist`) so the daily
   driver is the released build and Sparkle has nothing to offer it.

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
