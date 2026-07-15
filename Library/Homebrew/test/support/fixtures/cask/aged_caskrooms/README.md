# Aged Caskroom fixtures

Each directory here is a miniature Caskroom exactly as some past Homebrew
version left it on a real machine: metadata only, a few kilobytes per era.
CI machines are born fresh, so bugs that live in aged installed state
(metadata written by older brews) are structurally invisible to every other
test. This corpus makes those states first-class test inputs.
`test/cask/aged_caskroom_spec.rb` walks every era and asserts the same
invariants: every cask loads, keeps at least one artifact, and survives the
caskfile migration losslessly.

Layout of an era:

- `<era>/caskroom/<token>/.metadata/...` — the Caskroom tree, verbatim.
- `<era>/api/<token>.json` — optional; API cask JSON to stub for casks whose
  loading falls back to the API.

The rule: **every PR that changes an installed-metadata format adds an era
fixture here**, and every field-found aged-state bug donates its state, so
each class of bug is found at most once.

Current eras:

- `pre-receipt-rb` — full Ruby caskfile, no `INSTALL_RECEIPT.json`
  (installs from before install receipts existed, pre-migration).
- `pre-receipt-stubbed` — caskfile already stubbed to `{}`, no receipt
  (the same installs after the 6.0.10 caskfile-to-JSON migration).
- `receipt-era-stub` — `{}` stub caskfile plus a receipt holding
  `uninstall_artifacts` (the current healthy format).
- `internal-json` — `.internal.json` caskfile plus receipt
  (the other migration input format).
- `uninstall-flight-block` — Ruby caskfile with an `uninstall_preflight`
  block, which the migration deliberately skips.
