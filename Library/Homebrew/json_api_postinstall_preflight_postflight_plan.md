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
warn when both forms are present. Post-install or postflight steps are not
sandboxed for this iteration because they run only Homebrew-owned structured
operations. The runner shape leaves room to sandbox future step types that
invoke non-Homebrew code. Future cask work should sandbox all `*flight` run
scripts from non-Homebrew and non-system sources, for example scripts shipped
by upstream artifacts.

The final target is not to keep legacy hooks and structured steps side by side.
Once `homebrew/core` and `homebrew/cask` have been converted, all
`homebrew/core` `post_install` blocks and all `homebrew/cask` legacy
`preflight`, `postflight`, `uninstall_preflight` and `uninstall_postflight`
blocks should be removed for cases covered by structured steps. After that,
`Homebrew/brew` should reject side-by-side usage again and deprecate
`post_install` and legacy cask flight blocks for third-party tap usage.

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

## Formula Patterns

Local all-file scan source: `homebrew/core` at `ced17121766b`. The scan read
all `8,459` files under `Formula/`. Pattern buckets overlap because one
`post_install` can create directories, write files and run commands.

- `144` of `8,459` formulae define `post_install`.
- `post_install_defined` is the only install-time Ruby execution flag exposed
  through the formula JSON API for bottle installs. I did not find a
  caskfile-only-style source download gate for other formula DSL at bottle
  install time; formula source downloads for API-loaded formulae are used for
  source builds, local patches and resources rather than post-install metadata
  gaps.
- `79` create shared directories in `var`, `etc` or `HOMEBREW_PREFIX`.
  Examples: `Formula/g/glib.rb`, `Formula/l/languagetool.rb` and
  `Formula/m/mecab.rb`.
- `112` write or patch default configuration/data files.
  Examples: `Formula/n/node@24.rb`, `Formula/w/wemux.rb` and
  `Formula/p/php.rb`.
- `27` rebuild desktop/cache databases.
  Examples: `Formula/g/gjs.rb`, `Formula/g/geocode-glib.rb` and
  `Formula/e/efl.rb`.
- `19` initialise service data directories.
  Examples: `Formula/m/mariadb.rb`, `Formula/m/mysql.rb`,
  `Formula/p/postgresql@12.rb` and `Formula/p/percona-server.rb`.
- `17` update certificate/trust state.
  Examples: `Formula/o/openssl@3.rb`, `Formula/lib/libressl.rb` and
  `Formula/g/gnutls.rb`.
- Marker/touch-only conversion surfaces are now smaller because
  `Formula/i/icecast.rb` already uses `post_install_steps`. Remaining touch
  examples such as `Formula/r/r.rb` and `Formula/n/nethack.rb` also contain
  symlink or permission work, so they need full-hook coverage before
  conversion.

Refresh the formula buckets with:

```sh
rg -n 'def post_install|\.mkpath|mkdir_p|FileUtils\.mkdir|\bmkdir\b' Library/Taps/homebrew/homebrew-core/Formula
rg -n 'def post_install|\.write\b|\.atomic_write\b|File\.write|\binreplace\b' Library/Taps/homebrew/homebrew-core/Formula
rg -n 'glib-compile-schemas|gio-querymodules|gdk-pixbuf-query-loaders|gtk.*update-icon-cache|update-mime-database|update-desktop-database' Library/Taps/homebrew/homebrew-core/Formula
rg -n 'initdb|mysqld.*initialize-insecure|mysql_install_db|PG_VERSION|general_log\.CSM|mysql/user\.frm' Library/Taps/homebrew/homebrew-core/Formula
rg -n 'c_rehash|cert\.pem|openssl.*rehash|\btrust\b|certifi|ca-certificates' Library/Taps/homebrew/homebrew-core/Formula
rg -n 'FileUtils\.touch|\.touch\b|\btouch\b' Library/Taps/homebrew/homebrew-core/Formula
```

## Cask Patterns

Local all-file scan source: `homebrew/cask` at `4eee0394c96c`. The scan read
all `7,741` files under `Casks/`. Pattern buckets overlap because one flight
block can prepare files, change permissions and run commands.

- `193` of `7,741` casks currently require the Ruby source at install time
  through `Cask#caskfile_only?`: `170` because of legacy `*flight` blocks and
  `23` because of language blocks only. `27` casks have language blocks in
  total, so `4` have both language blocks and legacy `*flight` blocks.
- I did not find other current cask install-time Ruby source download gates.
  Ordinary artifacts, uninstall/zap directives, caveats, dependencies and
  `on_*` variations are serialised through API data. `*_steps` artifacts are
  also serialised and should not make `caskfile_only?` true.
- `68` flight blocks create directories, touch files or write small files.
  Examples: `Casks/a/android-ndk.rb`, `Casks/b/blender.rb` and
  `Casks/c/chromium.rb`.
- `13` move, copy or symlink files during install or uninstall.
  Examples: `Casks/g/gcloud-cli.rb`, `Casks/l/libcblite.rb` and
  `Casks/m/miniconda.rb`.
- `21` change permissions and `36` change ownership.
  Examples: `Casks/b/bitcoin-core.rb`, `Casks/a/anaconda.rb` and
  `Casks/p/parallels.rb`.
- `8` legacy flight blocks directly invoke `/usr/bin/security` for keychain
  certificate cleanup.
  Examples: `Casks/c/charles.rb`, `Casks/a/autofirma.rb` and
  `Casks/b/betwixt.rb`.
- `27` casks use language blocks. Large examples include
  `Casks/f/firefox.rb`, `Casks/l/libreoffice-language-pack.rb` and
  `Casks/t/thunderbird.rb`.

Refresh the cask buckets with:

```sh
rg -n 'preflight|postflight|FileUtils\.mkdir|mkdir_p|\.mkpath|FileUtils\.touch|\.touch\b|\.write\b|File\.write|atomic_write' Library/Taps/homebrew/homebrew-cask/Casks
rg -n 'FileUtils\.(mv|cp|cp_r|ln_s|ln_sf)|\b(mv|cp|cp_r|ln_s|ln_sf)\b|make_symlink|File\.symlink' Library/Taps/homebrew/homebrew-cask/Casks
rg -n 'set_permissions|chmod|FileUtils\.chmod|set_ownership|chown|FileUtils\.chown' Library/Taps/homebrew/homebrew-cask/Casks
rg -n '/usr/bin/security|system_command\s+"/usr/bin/security"|security\s+(delete|add|find)-' Library/Taps/homebrew/homebrew-cask/Casks
rg -n '^\s*language\b' Library/Taps/homebrew/homebrew-cask/Casks
```

## API Source Download Gates

Formula JSON API installs need to preserve `post_install` because it is the
only install-time Ruby hook recorded for bottle installs. The hook runs from
the formula stored in the installed keg, while source builds and local patch
handling use `Homebrew::API::Formula.source_download_formula` for build-time
reasons outside this post-install DSL work.

Cask JSON API installs use `Homebrew::API::Cask.source_download_cask` when
`Cask#caskfile_only?` is true. Today that is true when a cask has any legacy
`preflight`, `postflight`, `uninstall_preflight` or `uninstall_postflight`
block, or when it has language blocks. Legacy flight blocks need the source
because API data only records that a block exists, not the Ruby body. Language
blocks need the source because the API stores available language codes, but not
the selected block return value or stanza effects; language-specific URLs must
be resolved before the download can be enqueued.

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
  It creates the guardrails for the later `144` formulae with `post_install`
  blocks and `170` casks with flight blocks, but no existing formula or cask
  opts into the new DSL yet.
  Notes for the next PRs: keep the step payload as an ordered array; keep
  `_steps` blocks literal-only; for formulae, steps run before a remaining
  `post_install` hook during the temporary bridge; for casks, steps win over
  the legacy Ruby block with a runtime warning. Add conservative autocorrection
  only where every legacy statement maps mechanically.
- [x] PR 2, formula `post_install_steps`.
  Commit: `Add formula install steps`.
  Scope: formula DSL, formula JSON API data, API formula loading, installer and
  `brew postinstall` execution, formula cookbook docs and formula fixture.
  Estimated existing formulae affected: `144` formulae currently define
  `post_install`. The first useful conversion surface is roughly `79` formulae
  creating shared directories; parts of the `19` service data directory and
  `17` certificate/trust formulae may also
  move once their operations fit the supported step set. Runtime behaviour
  changes only for formulae that opt into `post_install_steps`.
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
  Estimated existing casks affected: `170` casks currently use flight blocks.
  The first useful conversion surface is roughly `68` casks that create/touch
  files or directories and the supported subset of `13` casks that move or
  symlink files. Runtime behaviour changes only for casks that opt into the
  new `*_steps` stanzas.
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
- [x] PR 6, database and service data directory initialisation.
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
- [x] PR 7, certificate and trust store actions.
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
- [x] PR 8, cask permission and ownership actions.
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
- [ ] PR 9, cask language variations in API data.
  Estimated existing casks affected: `27` casks use language blocks, with large
  examples including `Casks/f/firefox.rb`,
  `Casks/l/libreoffice-language-pack.rb` and `Casks/t/thunderbird.rb`.
  Notes for implementation: represent language-specific URLs, checksums and
  returned values without evaluating cask Ruby before fetch; keep the public API
  shape friendly to clients that need to choose one language deterministically.
