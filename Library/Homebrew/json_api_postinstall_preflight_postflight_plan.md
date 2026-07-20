# JSON API Postinstall/Preflight/Postflight Plan

This plan tracks repeated Ruby-only install behaviours that can be expressed as
structured DSL data and exposed through the JSON APIs.

Install step data is stored as an ordered array of step hashes. Ruby hashes
preserve insertion order, but the outer array makes JSON ordering explicit for
API consumers in any language.

The first implemented high-level DSL is named `steps`, exposed as
`post_install_steps` for formulae and as `preflight_steps`, `postflight_steps`,
`uninstall_preflight_steps` and `uninstall_postflight_steps` for casks. The
blocks are deliberately narrow: they may only contain literal calls to the
step DSL, with no wider Ruby execution and no access to the surrounding formula
or cask DSL.

The initial step methods shadow common `FileUtils` naming where practical:
`mkdir`/`mkdir_p`, `touch`, `move`/`mv`, `move_children` and
`symlink`/`ln_s`/`ln_sf`. Formula steps default `mkdir` and `touch` paths to
`var`, and source/target paths to `prefix`. Cask steps default `base`,
`source_base` and `target_base` to `staged_path`.

Formula `post_install_steps` may temporarily coexist with `post_install` so tap
conversions can peel supported repeated statements out of larger hooks. Runtime
handling runs formula steps first and then runs `post_install` last for the
remaining Ruby work. Cask `*flight_steps` still replace the matching legacy
flight block because cask artifacts already carry replacement semantics and
warn when both forms are present. Formula post-install steps run in the same
sandboxed subprocess as the remaining `post_install` hook, preserving its
filesystem and network restrictions for structured Ruby operations and any
commands they invoke. Future cask work should sandbox all `*flight` run scripts
from non-Homebrew and non-system sources, for example scripts shipped by
upstream artifacts.

The final target is not to keep legacy hooks and structured steps side by side.
Once `homebrew/core` and `homebrew/cask` have been converted, all
`homebrew/core` `post_install` blocks and all `homebrew/cask` legacy
`preflight`, `postflight`, `uninstall_preflight` and `uninstall_postflight`
blocks should be removed. Only after all five legacy hook counts reach zero at
the current tap heads should `Homebrew/brew` reject side-by-side usage again or
deprecate the legacy hooks for third-party taps.

During the temporary bridge, structured steps must appear before the matching
legacy block to make the runtime order obvious: `post_install_steps` before
`post_install`, and each cask `*flight_steps` stanza before its matching legacy
`*flight` stanza.

For each future operation type, check `homebrew/core` and `homebrew/cask`
separately and add formula support only when needed by `homebrew/core` or cask
support only when needed by `homebrew/cask`.

Specialised method variants, such as `using: :postgresql_initdb`, require at
least `3` current usages across `homebrew/core` and `homebrew/cask` before
being added to the structured DSL.

When adding install step DSL methods, update the matching RuboCop allow-list so
formula or cask tap syntax checks accept the new method in the same context.

RuboCop autocorrection converts the simplest existing `post_install` and
`*flight` Ruby blocks to steps blocks when every statement is a supported file
preparation operation with literal paths and known bases. Future post-install
and `*flight` DSLs should include the same style of conservative autocorrection
from the matching legacy Ruby pattern where possible.

Before opening follow-up PRs, run `bundle exec rake lint` from `docs/` to catch
markdown lint issues and run `brew style homebrew/core homebrew/cask` to catch
tap-wide formula or cask opportunities exposed by the new DSLs.

## Per-DSL Pull Request Workflow

From PR 5 onwards each new DSL step type ships as four separate
commits/branches/PRs rather than one combined change:

1. Add the new DSL in `Homebrew/brew`: the step method(s), runner execution,
   shared step block allow-list entries so tap syntax checks accept the method,
   JSON API round-tripping, tests and docs. No legacy-to-steps autocorrection.
2. Add the new RuboCops in `Homebrew/brew` that enforce and audit the DSL:
   conflict checks against legacy blocks when the step form replaces them, and
   conservative autocorrection from the matching legacy Ruby pattern.
3. Tap `homebrew/core`: convert formulae to the new DSL.
4. Tap `homebrew/cask`: convert casks to the new DSL.

Merge order is `1`, `3`, `4`, `2`. PR `1` ships the DSL and its allow-list so
taps can adopt it; PR `2` (the enforcing/autocorrecting cops) merges last so it
does not flag formulae or casks before the DSL is widely available. After PR `1`
is merged and before PRs `3` and `4` are merged, cut a new `Homebrew/brew`
stable release so `homebrew/core` and `homebrew/cask` CI have the new DSL.

These four PRs are also a stage gate. Before starting the next numbered DSL
operation, implement and test the current operation's enforcing/autocorrecting
PR `2`, record its commit in this plan and run its cops across both taps. The
cop can still merge last, but an operation is not complete while its PR `2` is
missing. If no safe legacy pattern exists, record the tap scan, representative
filenames and negative cop coverage instead of silently omitting the PR.

Each operation PR should also clone, or create clean local worktrees for,
`homebrew/core` and `homebrew/cask`, make the corresponding tap changes and
verify the changed taps with `./bin/brew style`, `./bin/brew audit` and
`./bin/brew readall`. The local-tap workflow is:

1. Run `./bin/brew tap --force homebrew/core`.
2. Run `./bin/brew tap --force homebrew/cask`.
3. Confirm the edit locations with `./bin/brew --repository homebrew/core` and
   `./bin/brew --repository homebrew/cask`.
4. Edit the tap checkout returned by those commands.
5. Run targeted `./bin/brew style` and `./bin/brew audit` for changed formulae
   or casks, then tap-wide `./bin/brew readall homebrew/core` and
   `./bin/brew readall homebrew/cask`.
6. If either tapped checkout has no modifications after the scan and
   conversion pass, run `./bin/brew untap homebrew/core` or
   `./bin/brew untap homebrew/cask` for the unmodified tap before finishing
   the `Homebrew/brew` PR.

Do this local tap pass while implementing the `Homebrew/brew` DSL PR so tap
conversions are not left for a separate reminder. If one tap has no applicable
changes for an operation, record that with filenames from the scan rather than
leaving the tap unchecked.

Long-term success for each operation PR means a tap conversion can remove the
whole legacy hook for the case it targets. For formulae, the temporary bridge
also allows partial conversions: move the supported repeated statements into
`post_install_steps`, leave the remaining Ruby in `post_install` and rely on
`post_install` running last. For casks, the matching `*flight` block should
still disappear because cask steps continue to replace legacy flight blocks. If
a candidate formula step only covers one statement in a current hook, either
include the remaining repeated behaviour as named steps for the same case or
document the remaining legacy work with filenames and use the bridge only while
the follow-up named step is being built.

## Legacy Hook Removal Gate

The zero-hook gate is stricter than a scan for side-by-side legacy and steps
blocks. At the latest tapped heads used for this audit:

- `homebrew/core` at `2603b0ce7788` contains `8,470` formula files, `82`
  `post_install` methods and `78` formulae using `post_install_steps`. No file
  uses both forms, but all `82` methods still block removal of the bridge.
- `homebrew/cask` at `892cff1a33bb` contains `7,701` cask files and `146`
  legacy flight blocks in `124` casks: `79` `preflight`, `42` `postflight`,
  `10` `uninstall_preflight` and `15` `uninstall_postflight` blocks. The tap
  also has `16`, `20`, `22` and `8` matching steps blocks respectively, with
  no cask using both matching forms.

Do not add conflict enforcement, change runtime precedence or deprecate a
legacy hook while any of these searches returns a result:

```sh
rg -n '^\s+def post_install\b' Library/Taps/homebrew/homebrew-core/Formula
for hook in preflight postflight uninstall_preflight uninstall_postflight; do
  rg -n "^\s+${hook}\b" Library/Taps/homebrew/homebrew-cask/Casks
done
```

Refresh the counts against current tap heads in every DSL operation. Keep a
residual ledger that assigns every matching file to an existing conversion, a
planned DSL operation or a deliberate refactor into another serialised
artifact. New legacy hooks added while migration is in progress must be added
to that ledger. Closing the bridge requires all five searches to be empty, tap
`readall` and style checks to pass and the zero result to be recorded here.

## Remaining Formula DSL Work

The `82` remaining formula hooks were inspected as syntax trees. These buckets
overlap because a hook can use several kinds of operation:

- `63` hooks make `119` command or command-output calls.
- `31` create directories, `23` remove paths, `26` create or maintain links,
  `17` change permissions, `17` replace file content, `16` write files, `13`
  copy or install paths, `5` touch files and `3` move paths.
- Existing actions should be re-applied to cache work in `easy-tag`, `gtk+3`
  and `sysprof`, and the existing MySQL initialiser should cover the bootstrap
  portion of both Percona hooks. Any unsupported remainder stays behind the
  formula bridge until the whole hook can be removed.

The repeated formula families justify named, data-only operations:

- `8` GCC formulae generate runtime links and specs files.
- `8` formulae unpack a compressed executable and then install it with the
  required mode.
- `7` GHC formulae refresh the package cache.
- `5` PHP formulae configure shared PEAR and PECL state.
- `5` Python-family formulae bootstrap packaging state: `3` CPython and `2`
  PyPy formulae.
- `4` LLVM formulae generate platform configuration files.
- `3` glibc formulae generate locales and maintain host timezone links.

The remaining individual hooks include XML catalogue registration, CA bundle
generation, GTK input-module and font/info caches, package or keystore
initialisation, path migration, Mach-O relocation and service start/stop
transactions. They should use generic guarded file or command steps where
possible. Complex one-off logic should be moved into a deterministic helper
installed into the bottle and invoked by a structured command step instead of
adding a formula-specific DSL action that does not meet the usage threshold.

## Remaining Cask DSL Work

The `146` remaining cask flight blocks were also inspected as syntax trees.
The overlapping capability buckets are:

- `70` blocks make `75` file writes. `66` of those writes generate command
  wrappers in `63` casks, `5` generate installer or uninstaller scripts in `4`
  casks and `4` rewrite other files in `3` casks.
- `53` blocks make `69` command calls. Repeated groups include `10` `pkill`
  calls, `4` `killall` calls, `8` Parallels `inittool` calls, `7` Parallels
  `chflags` calls, `7` Parallels `xattr` calls and `4` `gcloud` calls.
- `16` blocks remove paths, `8` create links, `8` enumerate globs or children,
  `6` move paths, `6` change permissions or ownership and `1` copies paths.

The uninstall hooks also need serialised predicates and state preservation.
Current repeated examples include conditional GPG launcher cleanup in `4`
casks, Conda environment preservation across `4` hooks in `2` casks and
paired symlink installation/removal in `distroav` and the `2` `libcblite`
casks. Other hooks unload dynamic launch agents, remove matching IDE launchers
or screen savers and invoke an app-bundled uninstaller.

## Remaining Migration Workstreams

The following capabilities are required before the zero-hook gate can pass:

1. Convert hooks already expressible with the current steps, including partial
   formula conversions that preserve ordering through the bridge. Do this
   before inventing another operation for the same behaviour.
2. Add common path mutation and predicate data: `copy`/`copy_children`,
   `remove`, literal or token-based `replace`, formula permission support,
   path arrays and globs and `if_exists`, `unless_exists` and symlink-target
   guards. Add only the template values demonstrated by the residual ledger,
   including the current user, selected architecture or language and caskroom
   or temporary paths.
3. Add a cask command-wrapper artifact that owns both a serialised wrapper
   template and its binary target. This removes the local `shimscript` and
   `wrapper` variables that prevent the existing `write` step from covering
   the `63` wrapper casks. It must support executable mode and the existing
   fixed template tokens without evaluating Ruby.
4. Add a constrained `run` step with an executable selected from an enumerated
   base, a literal argument array, a fixed environment map, optional stdin,
   accepted exit statuses, sudo policy and declarative path guards, retries and
   timeouts. It must not accept shell command strings, command substitution or
   Ruby callbacks. Cask commands from `staged_path` or `appdir` must run in the
   cask sandbox; formula-installed helpers must run in a formula post-install
   sandbox. Fixed system executables can use a separate system base.
5. Add shared lifecycle actions on top of `run`, led by process termination
   and retry handling. There are `16` current termination calls across the
   taps: the `10` cask `pkill` calls, `4` cask `killall` calls and `2` formula
   `killall` calls. Keep service transactions inside packaged helpers rather
   than turning steps blocks into an arbitrary command language.
6. Add the repeated formula actions listed above. Command-output-dependent
   GCC, PHP, Python and platform configuration work should stay inside these
   typed actions or packaged helpers, not expose captured command output as an
   unrestricted template language.
7. Add serialised uninstall cleanup and preservation primitives for matching
   symlinks/files, temporary path preservation and launch-agent unloading.
   Prefer existing `uninstall`, `zap`, `binary` and symlink cleanup artifacts
   whenever they already preserve the required behaviour.
8. After each workstream lands, convert both taps and refresh the residual
   ledger. The final long-tail pass packages any remaining formula helper,
   converts app-bundled cask helpers to sandboxed `run` steps and records why
   each hook disappeared. Only the subsequent zero-count PR may close the
   bridge and add conflicts or deprecations.

## API Source Download Gates

Formula JSON API installs need to preserve `post_install` because it is the
only install-time Ruby hook recorded for bottle installs. The hook runs from
the formula stored in the installed keg, while source builds and local patch
handling use `Homebrew::API::Formula.source_download_formula` for build-time
reasons outside this post-install DSL work.

Cask JSON API installs use `Homebrew::API::Cask.source_download_cask` when
`Cask#caskfile_only?` is true. Legacy `preflight`, `postflight`,
`uninstall_preflight` and `uninstall_postflight` blocks need the source because
API data only records that a block exists, not the Ruby body. Current API data
stores each language block's locale group, default marker, return value and
resulting stanza differences, so language-specific URLs can be resolved before
the download is enqueued. Older API data with only the flat `languages` array
continues to download source as a compatibility fallback.

## Installed Cask Metadata Format

Store supported installed cask metadata as regular `<token>.json`, not Ruby
caskfiles or internal JSON. Casks with `uninstall_preflight` or
`uninstall_postflight` Ruby blocks should keep using Ruby caskfiles in the
Caskroom until those blocks are ported to structured JSON data. The installed
caskfile is a post-install snapshot, so it should only retain data that can be
useful after installation has finished. This lets future uninstall, reinstall,
upgrade and zap runs reload supported installed metadata without evaluating the
original Ruby caskfile.

The installed JSON is deliberately minimal. It relies on
`INSTALL_RECEIPT.json` for receipt-owned data such as the installed cask
`version` and uninstallable artifacts, and only keeps data not otherwise
available after installation, such as `url_specs.only_path` when needed to
reconstruct staged artifact sources. It omits the full API snapshot so future
JSON API or DSL changes cannot affect post-install operations through fields
that are not needed after installation.

The installed JSON omits legacy `preflight` and `postflight` Ruby block
placeholders because JSON cannot represent their block bodies and they are not
needed after installation. Casks with `uninstall_preflight` or
`uninstall_postflight` Ruby blocks must remain backed by Ruby metadata so those
blocks continue to run on uninstall, zap, reinstall and upgrade. The goal is to
replace those Ruby blocks with structured uninstall step DSLs so they can be
migrated to JSON too.

The `brew update` migration should convert existing supported Caskroom `.rb`
and `.internal.json` caskfiles to regular `.json` caskfiles.

As the cask step DSLs grow, keep migrating post-install behaviour from legacy
Ruby flight blocks into structured JSON data so less installed cask behaviour
is stripped during metadata serialisation.

## Install Step Examples

- `Formula/l/languagetool.rb`: `post_install_steps` with
  `mkdir "log/languagetool", base: :var`.
- `Formula/i/icecast.rb`: `post_install_steps` with one `mkdir` and two
  `touch` steps under `var/"log/icecast"`.
- `Formula/o/openssl@3.rb`: `post_install_steps` with a forced `symlink` from
  `ca-certificates` `pkgetc/"cert.pem"` into the formula `pkgetc`.
- `Casks/8/86box.rb`: `preflight_steps` with a home-directory `mkdir` for
  the shared ROM directory.
- `Casks/k/klayout.rb`: `preflight_steps` with `move_children` from the
  staged root into the nested `KLayout` directory.
- `Casks/l/libcblite.rb`: `postflight_steps` with relative `symlink` steps
  marked for uninstall cleanup.

## Implementation Checklist

- [x] PR 1, shared install steps framework.
  Commit: `Add install steps framework`.
  Scope: shared ordered step data, a confined steps DSL, a shared runner, cask
  stanza ordering, RuboCop registration, conflict checks and the refactor plan.
  This PR does not wire formula or cask JSON API output or run steps from
  install phases.
  Estimated existing formulae/casks affected: `0` runtime behaviour changes.
  It created the guardrails for the then-current `144` formulae with
  `post_install` blocks and `170` casks with flight blocks, but no existing
  formula or cask opted into the new DSL yet.
  Notes for the next PRs: keep the step payload as an ordered array; keep
  `_steps` blocks literal-only; for formulae, steps run before a remaining
  `post_install` hook during the temporary bridge; for casks, steps win over
  the legacy Ruby block with a runtime warning. Add conservative autocorrection
  only where every legacy statement maps mechanically.
- [x] PR 2, formula `post_install_steps`.
  Commit: `Add formula install steps`.
  Scope: formula DSL, formula JSON API data, API formula loading, installer and
  `brew postinstall` execution, formula cookbook docs and formula fixture.
  Estimated existing formulae affected: at implementation time, `144` formulae
  defined `post_install`. The first useful conversion surface was roughly `79`
  formulae creating shared directories; parts of the `19` service data
  directory and `17` certificate/trust formulae could also move once their
  operations fit the supported step set. Runtime behaviour changes only for
  formulae that opt into `post_install_steps`.
  Notes for implementation: default `mkdir`/`touch` to `var` and source/target
  paths to `prefix`; expose the ordered array through `FormulaStruct`; make
  `post_install_steps` run before any remaining `post_install`; document that
  the two forms may coexist only as an incremental conversion bridge. Keep the
  tap-wide autocorrect audit in a follow-up commit so the implementation can
  land before converted formulae.
- [x] PR 3, cask flight steps.
  Commit: `Add cask install steps`.
  Scope: cask artifacts for `preflight_steps`, `postflight_steps`,
  `uninstall_preflight_steps` and `uninstall_postflight_steps`, cask API
  serialisation through artifact data, installer casts, cask cookbook docs,
  cask fixture/API loader coverage.
  Estimated existing casks affected: at implementation time, `170` casks used
  flight blocks. The first useful conversion surface was roughly `68` casks
  that created or touched files or directories and the supported subset of
  `13` casks that moved or symlinked files. Runtime behaviour changed only for
  casks that opted into the new `*_steps` stanzas.
  Notes for implementation: default all relative cask paths to `staged_path`;
  keep steps as normal cask artifacts so API loader round-trips work; make
  steps remove/override the matching Ruby flight artifact with a warning; keep
  `uninstall: true` symlink cleanup available for install-phase steps. Keep
  the tap-wide autocorrect audit in a follow-up commit so the implementation
  can land before converted casks.
- [x] PR 4, desktop and cache rebuild actions.
  Estimated existing formulae/casks affected: about `27` formulae run rebuild
  tools such as `glib-compile-schemas`, `gtk*-update-icon-cache`,
  `gio-querymodules`, `gdk-pixbuf-query-loaders`, `update-mime-database` and
  `update-desktop-database`; no cask count was identified in the initial scan.
  Scope: shared named action types for GSettings schemas, GIO modules,
  GDK Pixbuf loaders, GTK icon caches, MIME databases and desktop databases,
  runner dispatch through Homebrew-owned tools and docs.
  Notes for implementation: add named action types rather than raw commands;
  define idempotence and failure handling; decide whether any action invokes
  non-Homebrew code and should be ready for future sandboxing. Land RuboCop
  autocorrection and tap-wide conversions in a separate follow-up after the
  new DSL methods are available in a stable Homebrew release.
- [x] PR 4.1, formula install-step sandboxing.
  Commit: `Sandbox formula install steps`.
  Scope: run structured formula steps inside the existing post-install child
  process so macOS Seatbelt and Linux Bubblewrap apply the same filesystem and
  network policy as legacy `post_install` hooks. This must land before any tap
  migrations use filesystem-mutating steps.
- PR 5, default config and template writes (four-PR workflow above).
  Estimated existing formulae/casks affected: about `112` formulae write or
  patch default configuration/data files, and a subset of the `68` file-prep
  cask flight blocks write small files.
  Notes for implementation: use scoped token expansion instead of arbitrary
  Ruby interpolation; require literal templates or API-safe template data;
  define overwrite, `unless_exists` and upgrade semantics before adding
  autocorrection.
  - [x] PR 5.1, add the `write` DSL in `Homebrew/brew`.
    Commit: `Add install step config writes`.
    Scope: shared `write` step method with `base:` and `overwrite:`, runner
    execution that skips existing files unless `overwrite` is set, formula and
    cask step block allow-list entries, non-interpolated heredoc (`dstr`)
    support so `write` content can use heredocs, runner tests and cookbook
    docs. Default behaviour preserves existing files so user edits survive
    upgrades. Content stays a literal template in the JSON API but supports a
    fixed `{{...}}` token allow-list (`HOMEBREW_PREFIX`, `prefix`, `opt_prefix`,
    `bin`, `var`, `etc`, `pkgetc`, `version`, `version.major_minor`; casks add
    `staged_path` and `appdir`) expanded at install time; any other `{{...}}`
    is left verbatim. Dynamic interpolation (random cookies, `popen`-derived
    paths, `File.read` rewrites) is intentionally out of scope and stays as
    legacy Ruby.
  - [x] PR 5.2, add the `write` enforcing RuboCops in `Homebrew/brew`.
    Commit: `Add install step write cops`.
    Scope: formula and cask RuboCops conservatively autocorrect literal,
    newline-terminated `.write`, `.atomic_write` and `File.write` legacy
    blocks to `*_steps` `write` calls with `overwrite: true`. Writes without
    trailing newlines stay as legacy Ruby because the step DSL appends one.
  - [x] PR 5.3, convert `homebrew/core` formulae to `write`.
    Branch `install-steps-config-write`, commits
    `tronbyt-server: use post_install_steps` and `node@18: use
    post_install_steps`. `tronbyt-server` mapped with literal content;
    `node@18` became convertible once `{{HOMEBREW_PREFIX}}` token expansion
    landed (its whole `post_install` was one `atomic_write`). All other
    `.write` formulae interpolate paths, interpolate unsupported values, or
    run unsupported Ruby (`cp_r`, `inreplace`, `safe_popen_read`, loops).
  - [x] PR 5.4, convert `homebrew/cask` casks to `write`.
    Branch `install-steps-config-write`, commit
    `dnsmonitor: use postflight_steps`. Only `dnsmonitor` had a flight block
    with literal content. Token expansion does not unblock more casks: the
    `{{appdir}}`-content flight writes all target a `shimscript` local that is
    also wired to a `binary` stanza, and the literal-path LibreOffice packs
    interpolate an unsupported language `token` and run `system_command`.
- [x] PR 6.1, database and service data directory initialisation.
  Commit: `Add install step data directories`.
  Estimated existing formulae/casks affected: about `19` formulae initialise
  service data directories.
  Scope: formula `init_data_dir` step, runner execution, formula step block
  allow-list entries, fixture coverage and formula cookbook docs. The step
  creates service data directories and supports named bootstrap commands for
  PostgreSQL `initdb`, MySQL `mysqld --initialize-insecure` and MariaDB
  `mysql_install_db`, including the marker-file and CI-skip guards used by
  current `homebrew/core` formulae. Permission and ownership metadata were
  skipped because current tap usages fit future permission/ownership action
  work instead. PostgreSQL versioned link maintenance is handled by generic
  `link_dir` and `link_children` steps. MySQL conflicting configuration
  warnings stay as legacy Ruby until a separate named action is added.
  Local tap work for this step was prepared with
  `./bin/brew tap --force homebrew/core` and
  `./bin/brew tap --force homebrew/cask`. In this checkout,
  `./bin/brew --repository homebrew/core` resolves to
  `Library/Taps/homebrew/homebrew-core` at `369b5855942`, and
  `./bin/brew --repository homebrew/cask` resolves to
  `Library/Taps/homebrew/homebrew-cask` at `16a3a6e4562`.
  Success target for tap conversions: use the bridge to move database
  bootstrap statements out of every current MySQL and PostgreSQL hook, including
  `Formula/m/mysql.rb`, `Formula/m/mysql@8.0.rb`, `Formula/m/mysql@8.4.rb`,
  `Formula/p/postgresql@17.rb` and `Formula/p/postgresql@18.rb`, while their
  remaining warning or link maintenance work stays in `post_install` until
  separate named actions cover it. Fully remove `post_install` from
  bootstrap-only formulae such as `Formula/m/mariadb.rb`,
  `Formula/m/mariadb@10.11.rb`, `Formula/m/mariadb@10.5.rb`,
  `Formula/m/mariadb@10.6.rb`, `Formula/m/mariadb@11.4.rb`,
  `Formula/m/mariadb@11.8.rb`, `Formula/p/postgresql@12.rb`,
  `Formula/p/postgresql@13.rb`, `Formula/p/postgresql@15.rb` and
  `Formula/p/postgresql@16.rb`. Verify the `homebrew/core` conversion with
  `./bin/brew style homebrew/core`, targeted `./bin/brew audit --strict
  --online --formula ...` for the changed formulae and `./bin/brew readall
  homebrew/core`.
- [x] PR 6.2, database and link enforcement.
  Commit: `Add install step enforcement cops`.
  Scope: the formula install-step cop conservatively autocorrects recognised
  PostgreSQL, MySQL and MariaDB bootstrap statements to `init_data_dir`, and
  recognised PostgreSQL link maintenance to `link_dir` or `link_children`.
  Partial conversions preserve existing `post_install_steps` ordering and
  leave unsupported warning or maintenance work in `post_install`. Matching
  Percona bootstrap hooks remain unchanged because they were not part of the
  recorded MySQL formula conversion.
- [x] PR 7.1, certificate and trust store actions.
  Commit: `Add install step keychain cleanup`.
  Estimated existing formulae/casks affected: about `17` formulae update
  certificate/trust state and `8` cask flight blocks invoke
  `/usr/bin/security` for keychain certificate cleanup.
  Scope: cask `delete_keychain_certificate` step, runner execution through
  fixed `/usr/bin/security find-certificate` and `delete-certificate` calls,
  optional local certificate fingerprint matching for selective deletion,
  cask step block allow-list entries and docs. Formula-owned `cert.pem`
  symlinks use the existing `ln_sf` step with `source_formula` and
  `source_base: :formula_pkgetc`; specialised trust store generation such as
  `ca-certificates` bundle regeneration and Mono `cert-sync` stays legacy Ruby
  because current repeated usage is below the named-variant threshold.
- [x] PR 7.2, certificate and keychain enforcement.
  Commit: `Add install step enforcement cops`.
  Scope: the cask install-step cop converts fixed `/usr/bin/security`
  certificate deletion flights to `delete_keychain_certificate`. The formula
  cop converts the three direct `pkgetc` certificate bundle replacements to
  forced `symlink` steps using `source_formula` and
  `source_base: :formula_pkgetc`. Dynamic paths, altered commands and
  specialised certificate generation remain unsupported.
- [x] PR 8.1, cask permission and ownership actions.
  Commit: `Add cask permission steps`.
  Estimated existing casks affected: about `21` casks change permissions and
  `36` change ownership.
  Scope: cask `set_permissions` and `set_ownership` steps, path-array API
  normalisation, runner execution through `chmod` and `sudo chown`, cask
  installer command routing, App Management checks before ownership changes,
  cask step block allow-list entries, fixture/API loader coverage and cask
  cookbook docs. The steps skip missing paths like the existing flight
  mini-DSL. `set_ownership` defaults to the current user and `staff` group
  unless `user:` or `group:` are provided.
  Local tap work converted pure `set_permissions` and `set_ownership` flight
  blocks in `48` `homebrew/cask` casks. `homebrew/core` had no matching
  formula conversions for the cask-only DSL and was untapped after the clean
  scan. Remaining cask legacy blocks are `Casks/s/starnet++.rb`,
  `Casks/h/hummingbird.rb`, `Casks/m/mplabx-ide.rb` and
  `Casks/p/proxy-audio-device.rb`; they depend on unsupported local variables,
  architecture data or additional `system_command` work.
- [x] PR 8.2, permission and ownership enforcement.
  Commit: `Add install step enforcement cops`.
  Scope: the cask install-step cop converts pure legacy flight blocks using
  `set_permissions` and `set_ownership` to matching `*_steps` blocks. Mixed
  flights, dynamic paths and unsupported arguments remain unchanged.
- [x] PR 9, cask language variations in API data.
  Commit: `Serialise cask language variations`.
  Estimated existing casks affected: `27` casks use language blocks, with large
  examples including `Casks/f/firefox.rb`,
  `Casks/l/libreoffice-language-pack.rb` and `Casks/t/thunderbird.rb`.
  Scope: serialise a deterministic default plus ordered language variation
  deltas containing locale groups, the default marker, return values and all
  resulting API stanza changes. Public and internal API loaders select exact or
  partial locale matches and fall back to the default. Cask downloads use the
  selected URL and checksum directly, while older API data still falls back to
  source. Artifact differences are included so all `27` current language casks,
  including `cave-story` and `wondershare-edrawmax`, can use API data.
- [x] PR 10, audit the legacy hook removal gate.
  Commit: `Plan remaining install hook migration`.
  Scope: retain the formula incremental bridge, record exact residual counts
  at `homebrew/core` `2603b0ce7788` and `homebrew/cask` `892cff1a33bb`, assign
  the remaining behaviour to migration workstreams and make zero legacy hooks
  a hard prerequisite for conflicts or deprecations. The absence of matching
  legacy and steps blocks in one file is not a completion signal.
- [ ] PR 11, guarded path mutation and formula permissions.
  Scope: add copy, remove and replace operations, path collections and globs,
  declarative path predicates, the residual template tokens and formula use of
  permission steps. Convert both taps through the four-PR workflow and refresh
  the residual ledger.
- [ ] PR 12, serialised cask command wrappers.
  Scope: replace the `66` wrapper writes in `63` casks with a wrapper artifact
  that owns the generated executable and binary target. Cover installer script
  generation only where the same literal-template model is sufficient.
- [ ] PR 13, constrained and sandboxed command execution.
  Scope: add the enumerated-base `run` step, its argument, environment, stdin,
  result, guard, retry and timeout data and sandbox profiles. Use packaged
  formula helpers for complex one-off work and app-bundled cask helpers for
  upstream integration without admitting arbitrary shell or Ruby.
- [ ] PR 14, process lifecycle actions.
  Scope: migrate the `16` current termination calls with a shared action and
  preserve retry, output and failure behaviour. Keep multi-command service
  transactions in packaged helpers invoked by `run`.
- [ ] PR 15, repeated formula toolchain actions.
  Scope: migrate the GCC, compressed executable, GHC, PHP, Python, LLVM and
  glibc families recorded above. Treat each named action as its own four-PR
  operation and update the tap ledger before starting the next action.
- [ ] PR 16, uninstall cleanup and state preservation.
  Scope: add matching-path removal, temporary path preservation and dynamic
  launch-agent cleanup where existing cask artifacts cannot express the same
  behaviour. Convert install and uninstall halves together.
- [ ] PR 17, residual tap conversion.
  Scope: convert every remaining ledger entry with an existing step, a
  packaged helper and `run`, or a refactor into another serialised artifact.
  Re-scan current tap heads and do not complete this item until all five legacy
  hook searches are empty.
- [ ] PR 18, close the bridges and deprecate legacy hooks.
  Hard prerequisite: `homebrew/core` has no `post_install` methods and
  `homebrew/cask` has no legacy `preflight`, `postflight`,
  `uninstall_preflight` or `uninstall_postflight` blocks. Only this PR restores
  conflicts, structured-step precedence and third-party tap deprecations.
