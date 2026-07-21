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

The canonical step methods follow existing Formula, Cask, `Pathname`,
`FileUtils`, `SystemCommand` and utility naming where practical. Shared file
operations use `mkdir_p`, `touch`, `move`, `move_contents`, `copy`, `remove`,
`inreplace`, `symlink`, `symlink_tree`, `symlink_children` and `write_file`.
Formula steps default `mkdir_p` and `touch` paths to `var`, and source/target
paths to `prefix`. Cask steps default `base`, `source_base` and `target_base`
to `staged_path`.

Formula `post_install_steps` may temporarily coexist with `post_install` so tap
conversions can peel supported repeated statements out of larger hooks. Runtime
handling runs formula steps first and then runs `post_install` last for the
remaining Ruby work. Cask `*flight_steps` also temporarily coexist with the
matching legacy flight block and run before it. Formula post-install steps run
in the same sandboxed subprocess as the remaining `post_install` hook,
preserving its filesystem and network restrictions for structured Ruby
operations and any commands they invoke. Future cask work should sandbox all
`*flight` run scripts from non-Homebrew and non-system sources, for example
scripts shipped by upstream artifacts.

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

Named specialised actions require at least `2` current package usages across
`homebrew/core` and `homebrew/cask` before being added to the structured DSL.
One formula and one cask count as two usages. A named action or artifact used by
only one formula or cask should be refactored into generic steps or a packaged
helper. Orthogonal options on generic primitives, such as command input or a
symlink guard, are judged by the distinct behaviours they serialise rather than
by one exact keyword spelling.

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

## Migration Pull Request Workflow

Finish all DSL implementation work before enforcement, autocorrection or
bridge conflicts. For each capability, the `Homebrew/brew` implementation must
include the serialised data shape, runner or artifact behaviour, literal-block
allow-list entries, tests and public documentation. At the same time, apply the
candidate conversion to local `homebrew/core` and `homebrew/cask` migration
branches and rescan the residual hooks. If the scan exposes another reusable
behaviour, add the generic DSL or shared action and repeat until all five hook
searches are empty.

Unique complex formula logic belongs in a deterministic helper packaged in the
bottle and invoked by `run`. Prefer an existing cask artifact or a
`generated_script` for unique cask installer logic. Do not create a named DSL
action to hide a one-package algorithm.

The delivery order is now:

1. Review and merge the `Homebrew/brew` capability commits in order. Every
   commit is below `300` insertions and includes tests, documentation and a
   description suitable for an independent pull request.
2. Cut a stable `Homebrew/brew` release containing the complete DSL stack.
3. Refresh and merge the committed `homebrew/core` and `homebrew/cask` stacks
   in their recorded order. A tap file containing several step types is
   assigned to the latest brew capability it needs so every intermediate tap
   commit remains loadable.
4. Add sandbox hardening, conservative autocorrection and audit cops after the
   taps can consume every new DSL method.
5. Add conflicts or legacy-hook deprecations only after the merged tap heads,
   rather than only local branches, pass the zero-hook gate.

## Legacy Hook Removal Gate

The zero-hook gate is stricter than a scan for side-by-side legacy and steps
blocks. The baseline audit used `homebrew/core` at `2603b0ce7788`, with `8,470`
formula files and `82` `post_install` methods, and `homebrew/cask` at
`892cff1a33bb`, with `7,701` cask files and `146` legacy flight blocks in `124`
casks.

The committed local tap migrations based on those heads now pass the gate:

- `homebrew/core` has `0` `post_install` methods after changes to `83` files.
- `homebrew/cask` has `0` `preflight`, `postflight`, `uninstall_preflight` or
  `uninstall_postflight` blocks after changes to `124` files.
- Tap-wide style and `readall` checks pass for both migrations.

The compatibility naming pass also updates structured-step users that did not
have a legacy hook. The complete local stacks therefore differ from their tap
heads in `136` formula files and `137` cask files.

This proves that the implemented DSL is sufficient, but it does not authorise
bridge conflicts yet. The tap stacks must first be reviewed and merged against
current heads after a stable `Homebrew/brew` release contains the new DSL. The
same zero-hook scans must then pass again at the merged tap heads.

Do not add conflict enforcement, change runtime precedence or deprecate a
legacy hook while any of these searches returns a result:

```sh
rg -n '^\s+def post_install\b' Library/Taps/homebrew/homebrew-core/Formula
for hook in preflight postflight uninstall_preflight uninstall_postflight; do
  rg -n "^\s+${hook}\b" Library/Taps/homebrew/homebrew-cask/Casks
done
```

Refresh the counts when preparing the tap review branches because new hooks may
have landed since this local audit. Closing the bridge requires all five
searches to be empty at the merged tap heads, tap `readall` and style checks to
pass and the zero result to be recorded here.

## Completed Formula DSL Work

The `82` formula hooks in the baseline were inspected as syntax trees. These
buckets overlap because a hook can use several kinds of operation:

- `63` hooks make `119` command or command-output calls.
- `31` create directories, `23` remove paths, `26` create or maintain links,
  `17` change permissions, `17` replace file content, `16` write files, `13`
  copy or install paths, `5` touch files and `3` move paths.
- Existing actions should be re-applied to cache work in `easy-tag`, `gtk+3`
  and `sysprof`, and the existing MySQL initialiser should cover the bootstrap
  portion of both Percona hooks. The completed conversion combines those
  existing actions with the new generic primitives.

The repeated formula families now use named, data-only operations:

- `8` GCC formulae generate runtime links and specs files.
- `8` formulae unpack a compressed executable and then install it with the
  required mode.
- `5` PHP formulae configure shared PEAR and PECL state.
- `5` Python-family formulae bootstrap packaging state: `3` CPython and `2`
  PyPy formulae.
- `4` LLVM formulae generate platform configuration files.
- `3` glibc formulae generate locales and maintain host timezone links.

The GHC cache refreshes and other reusable command shapes use generic `run`
steps. Individual XML catalogue, CA bundle, package cache, Mach-O relocation
and service transaction algorithms are deterministic helpers installed into
their bottles and invoked by `run`. This removed the hooks without adding
formula-specific one-use DSL actions.

## Completed Cask DSL Work

The `146` cask flight blocks in the baseline were also inspected as syntax trees.
The overlapping capability buckets are:

- `70` blocks make `75` file writes. `66` of those writes generate command
  wrappers in `63` casks, `5` generate installer or uninstaller scripts in `4`
  casks and `4` rewrite other files in `3` casks.
- `53` blocks make `69` command calls. Repeated groups include `10` `pkill`
  calls, `4` `killall` calls, `8` Parallels `inittool` calls, `7` Parallels
  `chflags` calls, `7` Parallels `xattr` calls and `4` `gcloud` calls.
- `16` blocks remove paths, `8` create links, `8` enumerate globs or children,
  `6` move paths, `6` change permissions or ownership and `1` copies paths.

The migration uses `67` `command_wrapper` artifacts in `64` casks and `6`
`generated_script` artifacts in `5` casks. Generic guards, matching removal,
temporary-path moves and uninstall-aware symlinks preserve conditional cleanup
and state. App-bundled helpers use `run`, while repeated termination behaviour
uses `terminate_process`.

## Completed Local Migration Workstreams

The zero-hook local tap result uses these capabilities:

1. Guarded path mutation with `copy`, `remove`, `inreplace`,
   globs, collections, ownership, permissions and serialised predicates.
2. Cask `command_wrapper` and `generated_script` artifacts for owned
   wrapper and helper scripts.
3. Literal command execution with arguments, environment, standard input and
   output paths, working directory, platform and path guards. Sandbox and advanced
   runner controls remain later non-DSL changes.
4. `terminate_process` for the `16` repeated termination calls and packaged
   helpers for multi-command service transactions.
5. Shared GCC, compressed-executable, glibc, Clang, PHP and Python formula
   actions, with generic commands or packaged helpers for the long tail.
6. Matching cleanup, state preservation and uninstall-aware symlinks using the
   generic path primitives.
7. Repeated rescans and conversions until all five legacy-hook searches became
   empty.

The final syntax-tree usage audit found no specialised install-step method or
artifact used by only one package. The narrowest methods are `symlink_children`,
`update_desktop_database`, `update_mime_database` and `warn`, each used by two
formulae. `copy` has seven calls across three formulae and one cask. Formula
`set_permissions` has three users;
`set_ownership` remains cask-only because no formula needs it and `36` casks
already use it.

The former one-user GIO cache action was refactored to `run`; the one-use
architecture token was replaced by a generic glob, the one-formula
non-overwriting copy option was replaced by `unless_path_exists` and the
one-cask fallible command was moved into the existing `uninstall` artifact.
Generic command and guard options may have a single current spelling without
encoding a package-specific algorithm. `stdin_path`, `stdout_path`, `chdir`
and `sudo: :if_needed` each serialise an orthogonal file or command behaviour
rather than a package-specific action.

The one apparent exception is `on_linux`, currently used by `mono` only. It is
retained because it is the existing Formula DSL spelling and the symmetric
counterpart to `on_macos`, which has three users; it is a generic platform
scope rather than a package action. A combined `on_system` spelling would be
less consistent with Formula syntax without reducing the runner surface.

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
  `mkdir_p "log/languagetool", base: :var`.
- `Formula/i/icecast.rb`: `post_install_steps` with one `mkdir_p` and two
  `touch` steps under `var/"log/icecast"`.
- `Formula/o/openssl@3.rb`: `post_install_steps` with an overwriting `symlink` from
  `ca-certificates` `pkgetc/"cert.pem"` into the formula `pkgetc`.
- `Casks/8/86box.rb`: `preflight_steps` with a home-directory `mkdir_p` for
  the shared ROM directory.
- `Casks/k/klayout.rb`: `preflight_steps` with `move_contents` from the
  staged root into the nested `KLayout` directory.
- `Casks/l/libcblite.rb`: `postflight_steps` with relative `symlink` steps
  marked for uninstall cleanup.

## Implementation Checklist

- [x] PR 1, shared install steps framework.
  Commit: `Add install steps framework`.
  Scope: shared ordered step data, a confined steps DSL, a shared runner, cask
  stanza ordering, RuboCop registration, migration bridge ordering and the
  refactor plan.
  This PR does not wire formula or cask JSON API output or run steps from
  install phases.
  Estimated existing formulae/casks affected: `0` runtime behaviour changes.
  It created the guardrails for the then-current `144` formulae with
  `post_install` blocks and `170` casks with flight blocks, but no existing
  formula or cask opted into the new DSL yet.
  Notes for the next PRs: keep the step payload as an ordered array; keep
  `_steps` blocks literal-only; for formulae, steps run before a remaining
  `post_install` hook during the temporary bridge; for casks, steps run before
  the matching legacy Ruby block. Add conservative autocorrection
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
  Notes for implementation: default `mkdir_p`/`touch` to `var` and source/target
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
  keep steps as normal cask artifacts so API loader round-trips work; run steps
  before a matching Ruby flight artifact during migration; keep
  `remove_on_uninstall: true` symlink cleanup available for install-phase steps. Keep
  the tap-wide autocorrect audit in a follow-up commit so the implementation
  can land before converted casks.
- [x] PR 4, desktop and cache rebuild actions.
  Estimated existing formulae/casks affected: about `27` formulae run rebuild
  tools such as `glib-compile-schemas`, `gtk*-update-icon-cache`,
  `gio-querymodules`, `gdk-pixbuf-query-loaders`, `update-mime-database` and
  `update-desktop-database`; no cask count was identified in the initial scan.
  Scope: shared named action types for GSettings schemas, GDK Pixbuf loaders,
  GTK icon caches, MIME databases and desktop databases, runner dispatch
  through Homebrew-owned tools and docs. The proposed GIO modules action was
  removed after the final tap audit found only one user; that formula uses
  generic `run` instead.
  Notes for implementation: define idempotence and failure handling; decide
  whether any action invokes non-Homebrew code and should be ready for future
  sandboxing. Land RuboCop autocorrection and tap-wide conversions in a
  separate follow-up after the new DSL methods are available in a stable
  Homebrew release.
- [x] PR 4.1, formula install-step sandboxing.
  Commit: `Sandbox formula install steps`.
  Scope: run structured formula steps inside the existing post-install child
  process so macOS Seatbelt and Linux Bubblewrap apply the same filesystem and
  network policy as legacy `post_install` hooks. This must land before any tap
  migrations use filesystem-mutating steps.
- PR 5, default config and template writes (historical split workflow).
  Estimated existing formulae/casks affected: about `112` formulae write or
  patch default configuration/data files, and a subset of the `68` file-prep
  cask flight blocks write small files.
  Notes for implementation: use scoped token expansion instead of arbitrary
  Ruby interpolation; require literal templates or API-safe template data;
  define overwrite, `unless_path_exists` and upgrade semantics before adding
  autocorrection.
  - [x] PR 5.1, add the `write_file` DSL in `Homebrew/brew`.
    Commit: `Add install step config writes`.
    Scope: shared `write_file` step method with `base:`, exact atomic overwrite
    behaviour matching `Pathname#atomic_write`, formula and
    cask step block allow-list entries, non-interpolated heredoc (`dstr`)
    support so `write_file` content can use heredocs, runner tests and cookbook
    docs. `unless_path_exists` preserves user-edited files across upgrades.
    Content stays a literal template in the JSON API but supports a
    fixed `{{...}}` token allow-list (`HOMEBREW_PREFIX`, `prefix`, `opt_prefix`,
    `bin`, `var`, `etc`, `pkgetc`, `version`, `version.major_minor`; casks add
    `staged_path` and `appdir`) expanded at install time; any other `{{...}}`
    is left verbatim. Dynamic interpolation (random cookies, `popen`-derived
    paths, `File.read` rewrites) is intentionally out of scope and stays as
    legacy Ruby.
  - [x] PR 5.2, add the `write_file` enforcing RuboCops in `Homebrew/brew`.
    Commit: `Add install step write cops`.
    Scope: formula and cask RuboCops conservatively autocorrect literal,
    newline-terminated `.write`, `.atomic_write` and `File.write` legacy
    blocks to `*_steps` `write_file` calls. Content is preserved exactly.
  - [x] PR 5.3, convert `homebrew/core` formulae to `write_file`.
    Branch `install-steps-config-write`, commits
    `tronbyt-server: use post_install_steps` and `node@18: use
    post_install_steps`. `tronbyt-server` mapped with literal content;
    `node@18` became convertible once `{{HOMEBREW_PREFIX}}` token expansion
    landed (its whole `post_install` was one `atomic_write`). All other
    `.write` formulae interpolate paths, interpolate unsupported values, or
    run unsupported Ruby (`cp_r`, `inreplace`, `safe_popen_read`, loops).
  - [x] PR 5.4, convert `homebrew/cask` casks to `write_file`.
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
  `symlink_tree` and `symlink_children` steps. MySQL conflicting configuration
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
  recognised PostgreSQL link maintenance to `symlink_tree` or `symlink_children`.
  Partial conversions preserve existing `post_install_steps` ordering and
  leave unsupported warning or maintenance work in `post_install`. Matching
  Percona bootstrap hooks remain unchanged because they were not part of the
  recorded MySQL formula conversion.
- [x] PR 7.1, certificate and trust store actions.
  Commit: `Add install step keychain cleanup`.
  Estimated existing formulae/casks affected: about `17` formulae update
  certificate/trust state and `8` cask flight blocks invoke
  `/usr/bin/security` for keychain certificate cleanup.
  Scope: cask `delete_keychain_certificates` step, runner execution through
  fixed `/usr/bin/security find-certificate` and `delete-certificate` calls,
  optional local certificate fingerprint matching for selective deletion,
  cask step block allow-list entries and docs. Formula-owned `cert.pem`
  symlinks use `symlink` with `overwrite: true`, `source_formula` and
  `source_base: :formula_pkgetc`; specialised trust store generation such as
  `ca-certificates` bundle regeneration and Mono `cert-sync` stays legacy Ruby
  because current repeated usage is below the named-variant threshold.
- [x] PR 7.2, certificate and keychain enforcement.
  Commit: `Add install step enforcement cops`.
  Scope: the cask install-step cop converts fixed `/usr/bin/security`
  certificate deletion flights to `delete_keychain_certificates`. The formula
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
- [x] PR 11, guarded path predicates, `7501685232`.
  Scope: serialise path collections, globs, bases, template tokens and scoped
  `if_path_exists`, `unless_path_exists`, `on_macos` and `on_linux` predicates
  shared by later path and command steps.
- [x] PR 12, copy steps, `05341645e6`.
  Scope: add recursive and globbed copies with per-target preservation guards.
- [x] PR 13, removal steps, `d7361407f5`.
  Scope: add recursive, privileged and matching removals for install and
  uninstall phases.
- [x] PR 14, `inreplace` steps, `c1d64e3f87`.
  Scope: add literal and regular-expression replacements with Formula-compatible
  audit and global defaults plus scoped path guards.
- [x] PR 15, command wrappers, `54f0613331`.
  Scope: serialise owned cask launchers as normal binary artifacts.
- [x] PR 16, generated scripts, `7b5953863f`.
  Scope: serialise fixed executable scripts consumed by installers or steps.
- [x] PR 17, formula permissions, `ff6ff2a50a`.
  Scope: allow formula `set_permissions`; keep ownership cask-only because no
  formula conversion needs it.
- [x] PR 18, constrained commands, `59ea6aff23`.
  Scope: add `run` with `SystemCommand`-aligned arguments, environment,
  standard input and output paths, working directory and output defaults.
  Package complex one-off formula logic as deterministic helpers.
- [x] PR 19, process termination, `cb41c7a9c2`.
  Scope: add name or full-command matching, a total attempts count, notices,
  privilege and a non-fatal default failure policy.
- [x] PR 20, path warnings, `818795c8d2`.
  Scope: combine generic `warn` with `if_path_exists` for the shared Percona
  configuration warning without adding a database-specific action.
- [x] PR 21, GCC runtime action, `9d7961ca06`.
  Scope: share the Linux runtime-link and specs generation used by eight GCC
  formulae.
- [x] PR 22, gzipped executable action, `8eec09ba26`.
  Scope: share staged gzip decompression and fixed-mode executable installation
  across eight formulae.
- [x] PR 23, glibc runtime action, `5b2f81c3d3`.
  Scope: share locale generation and timezone-link maintenance across three
  glibc formulae.
- [x] PR 24, Clang system config action, `fadf536f9a`.
  Scope: extract the existing LLVM SDK and architecture configuration into a
  shared utility used by both installation and four LLVM post-install steps.
- [x] PR 25, PHP configuration action, `f05c74eb5d`.
  Scope: share PEAR, PECL and versioned extension setup across five formulae.
- [x] PR 26, Python bootstrap action, `7a3842db2b`.
  Scope: share CPython and PyPy packaging state across five formulae while
  reusing `Language::Python.homebrew_site_packages` for CPython paths.
- [x] PRs 27.1-27.14, prepare the `homebrew/core` migration stack.
  Scope: the `14` committed capability layers listed above remove all `83`
  remaining formula hooks and carry independent review descriptions.
- [x] PRs 28.1-28.7, prepare the `homebrew/cask` migration stack.
  Scope: the `7` committed capability layers listed above remove all legacy
  flight blocks from `124` casks and carry independent review descriptions.
- [ ] PR 29, refresh and merge both tap stacks.
  Scope: after the brew DSL ships in a stable release, rebase each stack onto
  the current tap head, repeat the zero-hook gate and merge in order.
- [ ] PR 30, sandbox and runner hardening.
  Scope: sandbox eligible helpers and commands without adding migration DSL.
- [ ] PR 31, enforcement and migration cops.
  Scope: add conservative autocorrection and audits after both taps consume the
  complete DSL. Do not introduce conflicts here.
- [ ] PR 32, close the bridges and deprecate legacy hooks.
  Hard prerequisite: the merged `homebrew/core` head has no `post_install`
  methods and the merged `homebrew/cask` head has no legacy flight blocks.
