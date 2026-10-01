# Relocatable Bottles

## Goal

Every Homebrew/core bottle pours at every prefix under 65 characters long.

- This applies on x86_64 Linux, arm64 Linux and arm64 macOS; longer prefixes
  build from source. Intel macOS is out of scope: Homebrew/core no longer
  builds Intel bottles outside the portable Ruby toolchain.
- It includes today's non-relocatable (cellar-pinned) bottles, i.e. those
  that are neither `cellar :any` nor `cellar :any_skip_relocation`. The
  padded-prefix scheme below handles most of them; the residual classes in
  "Completeness" each get their own strategy so that none is left behind
  silently. Exceptions must be named, justified in the formula and counted.
- Phases are ordered by how many users benefit and how soon: pour-time
  performance helps everyone on every prefix, making more bottles
  relocatable helps every custom prefix at any length, pour-time patching
  helps short custom prefixes, and the 64-byte migration extends that to
  long ones. Phases run sequentially, not in parallel, with a multi-month
  user soak before catalogue-wide padded builds begin.

This is a living document: edit or remove steps as they are implemented so
it always describes the remaining work.

End each implementation commit body with this exact line:

```text
This change is part of [`plans/relocatable-bottles.md`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/plans/relocatable-bottles.md)
```

Any benchmark quoted in a commit message must be the full hyperfine
output from `brew benchmark` (using its `--exec` mode for bespoke
workloads), never hand-summarised numbers.

Changes to homebrew/core (re-marks, formula fixes, sweeps) use one commit
per formula with the subject `<formula>: <change>`, never one commit
spanning many formulae.

Pull requests must always fill in the repository's pull request
template (`.github/PULL_REQUEST_TEMPLATE.md`), never bypass it
(e.g. with `gh pr create --fill`).

## Current state (21 August 2026, formulae.brew.sh data)

| Tag | `:any_skip_relocation` | `:any` | pinned |
|---|---|---|---|
| `arm64_tahoe` (8,369 bottles) | 4,598 (54.9%) | 2,745 (32.8%) | 1,026 (12.3%) |
| `x86_64_linux` (8,401 bottles) | 4,891 (58.2%) | 2,341 (27.9%) | 1,169 (13.9%) |

The 1,121 `:all` bottles are counted in `:any_skip_relocation`: they are all
marked that way and apply on every platform. 1,328 formulae carry a pinned
bottle on at least one tag and 892 are pinned on both `arm64_tahoe` and
`x86_64_linux`, so causes are mostly inherent rather than
platform-specific. Six formulae still gate pouring on
`pour_bottle? only_if: :default_prefix`.

Per-bottle rates understate the problem, because an install only avoids
source builds when the formula's entire recursive runtime dependency closure
pours. On `arm64_tahoe`, although 87.7% of bottles are individually
relocatable, only 56.0% of formulae (4,688 of 8,369) have a fully
relocatable closure; 43.9% contain at least one pinned bottle. A few hub
formulae do most of the poisoning: `openssl@3` alone appears in the closure
of 2,152 formulae, followed by `gettext` (1,325), `glib` (963),
`python@3.14` (867), `libx11` (855) and `fontconfig` (831). Fixing only
those six would lift closure coverage to 70.9%, and the top twenty to
76.4%, which is why per-formula fixes alone plateau and the value of this
plan is convex: it concentrates near 100%, where whole dependency trees
become pourable, and every pinned formula left continues to poison its
entire dependent subtree.

## Background: how relocation works today

Bottles are stored with `@@HOMEBREW_PREFIX@@`-style placeholders in text
files, libtool files, Mach-O load commands and ELF RPATHs/interpreters
(`keg_relocate.rb`, `extend/os/{mac,linux}/keg_relocate.rb`). After
placeholdering, `brew bottle` scans the keg (`dev-cmd/bottle.rb`); any
surviving prefix/cellar/library reference or absolute symlink into the prefix
pins the bottle to its build cellar. Surviving references are almost always
raw C strings compiled into binaries, because text replacement deliberately
touches only text files.

Raw C strings are the only length-limited content at pour time:

- Text files are rewritten wholesale, so replacements can grow.
- Mach-O load commands can grow because superenv always passes
  `-headerpad_max_install_names` (`shims/super/cc`), and install-name edits
  happen in-process via ruby-macho.
- ELF RPATHs and interpreters can grow because patchelf.rb rewrites them into
  a new segment.
- A raw C string can only be replaced by an equal-or-shorter string, padded
  with NUL bytes; a string in an ELF dynamic string table that a linker has
  suffix-merged (referenced from its interior) is instead padded with extra
  path separators after the prefix so those references keep their offsets.
  Only NUL-delimited chunks that could be text strings are patched: valid
  UTF-8 without control characters other than whitespace and up to 16 KiB,
  an empirical bound (php's configure line, the longest C string found
  carrying a prefix, is 3740 bytes; `node`'s embedded `config.gypi` JSON
  exceeds 21 KiB). A prefix inside serialised or length-prefixed data, such
  as `node`'s V8 startup snapshot and that JSON, is left unrelocated because
  shifting its neighbours corrupts them (#23808).

`Keg#relocate_build_prefix` (`keg_relocate.rb`) implements that NUL-padded
patching and re-signs patched Mach-O files, and
`BottleSpecification#compatible_locations?` allows pouring a pinned bottle
into an equal-or-shorter prefix by default. The documented
`HOMEBREW_NO_RELOCATE_BUILD_PREFIX` variable disables this. History:
default-on was added in #12534 (December 2021), reverted twice, then gated
behind a positive variable in #13217 after #13209 reported hard failures at
a prefix longer than the bottled one. The length check now prevents that
case and the positive variable was removed when default-on was restored.

Prior art: conda-forge builds packages under a long placeholder prefix (up
to 255 characters) and rewrites it at install time, including NUL-padded
replacement inside binaries, and Spack's `padded_length` configuration pads
install tree paths for the same reason so its build caches relocate. Both
validate the padded-prefix approach at scale and are useful references for
edge cases (e.g. prefixes inside length-prefixed data).

### Why bottles are pinned (verified by inspection)

Replaying the exact `keg_contain?` logic over the contents of 17 pinned and
16 relocatable published bottles:

- 12/17: compiled-in own-keg or prefix C strings (sysconfdir, datadir,
  localedir, plugin directories), e.g. `wget2`'s localedir, `graphviz`'s
  plugin directory, `python@3.x`'s framework prefix.
- 2/17: stale ELF `.dynstr` bytes: Meson's install-time RPATH rewrite
  overwrites the build RPATH without clearing the rest of the old string
  (intentional upstream; Nix carries a patch), and patchelf leaves the old
  table behind when growing one, so the checker counts the corpse
  (`harfbuzz`, `shared-mime-info`; the 224-formula glib/gobject
  introspection cluster on Linux looks identical). Functionally these are
  false positives, since addressed by scanning ELF files by structure
  (design decision 11).
- 1/17: node-gyp build debris: native addons compiled inside the keg embed
  keg paths in debug info and ship stray `.o` artefacts (about 29 npm
  formulae).
- 1/17: `abseil` replays clean under the current checker yet CI pinned it:
  since explained and fixed (phantom resolved-linkage matches, Phase 1
  item 4). A bottle's cellar lives in the formula, not the tarball, so
  provably clean bottles can be re-marked `cellar :any` without
  rebuilding.

## Design decisions

1. Order by user benefit. Pour-speed and relocatable-count improvements ship
   before any new machinery, because they help users immediately without
   opting in to anything; patching and the padded migration follow.
2. Push logic and metadata generation to bottle time and away from pour time
   whenever possible: bottle time runs once on CI, pour time runs on every
   user's machine.
3. Legacy short-built bottle patching is pour-time only in its effect.
   Eligibility and patching are entirely client-side, so it works
   retroactively for published bottles and needs no homebrew/core changes.
   Bottle time only adds accelerator metadata, always with a scan fallback,
   so there is no version coupling for that stage.
4. Bottling uses a canonical 64-byte padded build prefix per platform. Its
   tab records `padded_prefix: true`, while formulae retain the tag's default
   cellar. Every embedded C string then carries 64 bytes of patchable
   material, so bottles patch down to any prefix up to 64 bytes, including
   the defaults. Clients must understand the tab marker before the first
   padded bottles are published, so the brew release precedes the
   infrastructure cutover.
   64 rather than conda's 255 because build-time Unix socket paths
   (`sun_path` is 104 bytes) and shebang limits punish very long prefixes.
   test-bot builds at the padded prefix but tests the resulting bottles
   after pouring them into a shorter/default prefix.
5. The cost profile is surgical: `:any` and `:any_skip_relocation` bottles
   (84 to 88% of the catalogue) are placeholder-based and prefix-independent,
   so they pour exactly as today. Only pinned bottles start patching (1 to 2
   files typically) plus re-signing at pour. Re-signing preserves
   entitlements, requirements, flags and runtime metadata
   (`codesign_patched_binary` passes `--preserve-metadata`).
6. A bottle built at a non-default prefix records the literal prefix string
   as `built_prefix` in its tab; absence means the tag's default prefix, so
   tabs for today's bottles are unchanged. The literal string, not a
   name/version pair, so the constant can change without a mapping. A
   canonical padded build also records `padded_prefix: true` there.
7. The user contract is global, not per-bottle, for comprehensibility: one
   number (64) once migration completes; until then the interim rule is
   prefix length up to the bottled default (13 for arm64 macOS, 26 for
   Linux).
8. Relocation-by-patching defaults on for equal-or-shorter prefixes. This
   initially means up to 13 bytes on arm64 macOS and 26 on Linux. Only after
   a multi-month soak and the padded catalogue migration does the default
   contract expand to 64 bytes.
9. `HOMEBREW_NO_RELOCATE_BUILD_PREFIX` is the documented escape hatch,
   retained through the soak and padded migration.
10. Non-intuitive logic must always be commented, especially relocation edge
    cases (NUL padding, string-table subtleties, codesign behaviour): this
    code is touched rarely and debugged under pressure.
11. The relocatability checker deliberately errs towards classifying
    bottles as relocatable rather than pinned. This is a rebalancing of the
    original `strings`-based checker, which counted every prefix byte
    sequence in a file as a pin: a wrongly pinned bottle forces source
    builds for every non-default-prefix user and poisons its whole
    dependent subtree, whereas a wrongly relocatable one surfaces as a
    per-formula bug report with a trivial fix and is caught by the Phase 4
    validation sweep and the test-bot relocated-pour test. Concretely, ELF
    files are scanned by structure rather than as a whole: only the
    interpreter the loader uses, the dynamic strings the loader references
    and the contents of ordinary sections count; bytes outside every
    section and unreferenced entries in loader-owned string tables never
    do. Other file types keep the whole-file scan.

## Plan

### Next step: test existing bottles at shorter prefixes

Test as many formulae as possible, including their runtime dependency
closures, in a fresh prefix shorter than the bottle's build prefix on each
target platform. Use published bottles with relocation enabled, record
source-build fallbacks as failures, run `brew linkage --test` and
`brew test`, exercise installed executables and report per-formula results.
Successful installation alone is insufficient: the Perl/ack failure only
appeared at runtime. This validation precedes further padded-prefix rollout.

### Phase 1: maximise relocatable bottles now (helps every custom prefix, any length)

Each pinned bottle flipped to `cellar :any` pours at any prefix with no
length limit and no new machinery.

4. **Completed August 2026.**
   Reconcile checker divergences: resolved. The `abseil` class was pinned
   by `file_linked_libraries` resolving `@rpath`/`@loader_path` load
   commands against the live keg at bottle time, turning relocatable
   linkage into absolute build-prefix paths; the checker now reads raw
   load-command names. Text matches never recorded it because googletest
   include-path strings hit the `ignores` filters, which also explains
   why only arm64 macOS pinned: `/usr/local/include/...` never byte-matched
   Intel's `/usr/local/opt` and `/usr/local/Cellar` search strings and
   Linux has no linkage check. Remaining: once the fix is deployed to CI,
   batch re-mark provably clean pins `cellar :any` with no rebuild
   (sha256 unchanged) in homebrew/core, starting from the 127 formulae
   pinned on all arm64 macOS tags yet `:any` on `x86_64_linux` (e.g.
   `abseil`, `boost`, `binutils`, `aws-sdk-cpp`).
7. Data-driven ignore extensions where blocker diagnostics show a class is
   functionally dead.

### Phase 2: pour-time patching for pinned bottles (completed August 2026)

Whole dependency closures now pour at prefixes up to the bottled default
length (13 bytes arm64 macOS, 26 Linux), covering the hub formulae
(`openssl@3`, `gettext`, `glib`, `python@3.x`) that Phase 1 cannot.
Relocation is the default for equal-or-shorter prefixes and
`HOMEBREW_NO_RELOCATE_BUILD_PREFIX` provides a documented escape hatch.
This exercises the already-published catalogue across more real custom
prefixes before Homebrew commits to padded production builds.

During a soak of at least a few months, Homebrew/brew CI pairs its existing
default-prefix test-bot jobs with padded-prefix jobs on x86_64 Linux, arm64
Linux and arm64 macOS. Both variants run the same source-build, bottle,
reinstall, linkage and formula-test workflow. Padded jobs build and bottle
at the padded prefix, then pour the fresh bottles and runtime dependencies
into a shorter/default prefix for linkage and formula tests. Make the build
prefix unavailable during those tests so unrelocated paths cannot silently
work. The padded jobs neither publish nor upload their bottles.

All remaining homebrew/brew and individual-formula fixes (the brew side of
Phase 3, the upstream hub track and the Completeness items) come before
production changes to homebrew/core CI or catalogue-wide rebottling.

### Phase 3: migrate bottling to the 64-byte prefix (extends to long prefixes)

**Client foundations completed August 2026:** canonical 64-byte prefixes
exist, padded eligibility remains in tab or manifest metadata only and bottle
selection uses that manifest data. Begin the production steps below only
after Phase 2 has soaked for at least a few months.

13. Extend the paired test-bot jobs to cover a pinned plus
    path-length-sensitive sample and representative pinned dependency
    closures built at the candidate 64-byte prefixes and tested after pouring
    into shorter/default prefixes on all three target platforms.
15. test-bot: build changed formulae at the padded prefix, pour each fresh
    bottle into a scratch shorter/default prefix, then run
    `brew linkage --test` and `brew test` there with the build prefix
    unavailable.
Before cutover, version-gate symbolic cellar and `padded_prefix` metadata
consumers, release supporting clients and ensure the marker remains
per-platform rather than merging into `:all`. Resolve socket, shebang and
build-path failures, audit scanner blind spots, decide the glibc strategy and
retire or justify `pour_bottle? only_if: :default_prefix` gates.

16. Infra cutover in order: x86_64 Linux runners first (no SIP, biggest
    pinned share), arm64 Linux second, arm64 macOS third.

### Phase 4: catalogue burndown (homebrew/core)

17. Natural version-bump and autobump churn rebottles most formulae at 64;
    a dashboard tracks the 64-built share per platform from `built_prefix`.
18. Dependency-ordered forced sweep for stragglers, prioritised by poisoned
    dependent count (`openssl@3`, `gettext`, `glib`, `python@3.x`, `libx11`
    and `fontconfig` first), then remaining pinned formulae: old pinned
    bottles cannot pour into the padded CI prefix, so they force CI
    source-build fallbacks until rebottled, whereas old relocatable bottles
    pour there immediately (placeholder relocation has no length limit).
    Old pinned bottles keep pouring unchanged at default prefixes
    throughout.

19. Repeat the shorter-prefix validation sweep in homebrew/core CI
    (`workflow_dispatch`) after rebottling: pour every pinned bottle into a
    scratch prefix shorter than the bottled one on each target platform
    with patching enabled, confirm each tab records `relocated_build_prefix`,
    run `brew linkage --test` and `brew test`, and report a per-formula table.
    This catches scanner blind spots introduced by padded builds; the
    initial broad sweep of existing bottles is the next step above.

### Phase 5: extend the default to 64 bytes

20. Only when the catalogue is fully 64-built on the target platforms:
    relocation-by-patching expands to every prefix up to 64 bytes; retain
    `HOMEBREW_NO_RELOCATE_BUILD_PREFIX`; update `docs/Bottles.md`,
    `docs/Installation.md` and homebrew/install messaging with the single
    global contract.

### Upstream fixes for the hubs

Independent of the phases above and prioritised by poisoned dependent
count, because these help prefixes beyond 64 bytes and remove formulae from
the patching path entirely: prefer executable-relative lookups upstream,
environment fallbacks or moving baked-in paths into generated text files
(which relocate for free). Biggest heads: `openssl@3`, `gettext`, `glib`,
`python@3.x`, `libx11`, `fontconfig`, then `node`, `perl`, `ruby`, `php`,
`mysql`, `postgresql@x`, `ffmpeg`, `llvm`, `gcc`, `ghc`, `openjdk`.

## Completeness: making every pinned bottle relocatable

The padded-prefix scheme alone does not cover every non-`:any` bottle. Each
residual class below is a goal with its own strategy, tracked to zero or to
a named, formula-annotated exception:

1. **Absolute symlinks into the prefix.** Done: `brew bottle` rewrites
   absolute symlinks into the prefix or cellar as relative ones
   (functionally identical) and pouring retargets any left in older
   bottles from the prefix they were built for.
2. **Files patchelf must skip** (`protodesc_cold`/`.bun` sections, e.g.
   bun): these keep raw RPATH strings and auto-pin today. Strategy: the
   NUL-padded string patcher handles them at pour. A shortened NUL-padded
   `.dynstr` entry is valid (the loader reads to the first NUL), and under
   padded builds the replacement always fits. Verified with bun in the
   Phase 4 validation sweep.
3. **Scanner blind spots**: prefix strings inside compressed, serialised or
   length-prefixed data that `strings`-based scanning cannot see. Under
   padded builds these become a correctness risk for default-prefix users
   too, since an unseen string never gets patched. Strategy: bottle-time
   audit of known container formats with warnings; the Phase 4
   validation sweep and the test-bot relocated-pour test are the functional
   catch-all; findings become per-formula fixes. NUL padding inside a
   length-prefixed field can also corrupt rare formats: the patcher skips
   chunks that cannot be text strings, which keeps `node`'s V8 snapshot
   intact (#23808), and the same validation catches the rest. The bytes
   alone cannot tell a text payload read by length from a C string, and
   Rust and Go address strings by length and pack them without NUL
   separators, so shifting such a chunk corrupts whatever follows the
   prefix in it. Padding each occurrence with separators instead, as
   `replace_prefix_preserving_length` already does for suffix-merged string
   tables and as Spack does throughout, keeps every offset and is the
   layout-agnostic fix should those cases surface, at the cost of `//` runs
   in printed paths and in programs comparing paths against the prefix.
4. **glibc**: relocating the dynamic linker is deliberately skipped because
   patchelf breaks it. Strategy: investigate NUL-padded string patching of
   padded-built glibc (plain C string replacement, a different mechanism
   from patchelf); if it proves fragile, glibc stays a permanent named
   exception, which only affects hosts old enough to need it.
5. **`pour_bottle? only_if: :default_prefix`** (apptainer, composer, fish,
   ocaml, ocaml@4, screenfetch): these refuse to pour at non-default
   prefixes regardless of cellar. Strategy: re-test each under patching and
   retire or convert the gates during Phase 4.
6. **Prefixes longer than 64 bytes** stay source-built by design; the
   upstream track above shrinks even that over time.

An audit should enforce the end state: a formula whose fresh bottle is
neither relocatable nor patchable must carry an in-formula annotation naming
the reason, so the exceptions list stays short, visible and countable.

## Success criteria

- 0 bottles on current tags that are neither relocatable nor patchable,
  minus the named exceptions list.
- `brew install` at any prefix up to 64 bytes never falls back to source
  because of relocation on the target platforms.
- Default-prefix pours are measurably faster than before the metadata-driven
  pour (`brew benchmark` at implementation: 1.67x faster end-to-end on a
  5,000-file synthetic keg, relocation cost itself dropping from ~320ms to
  ~1ms), with gains accruing as bottles are rebottled with metadata.
- CI fails when a formula regresses from relocatable-or-patchable without an
  annotation.

## Open questions

- How many formulae fail to build at all at a 64-byte prefix
  (path-length-sensitive build systems), discovered by the Phase 3 shadow
  builds; these block the sweep rather than staying pinned.
