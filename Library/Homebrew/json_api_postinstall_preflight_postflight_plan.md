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

RuboCop checks reject formulae or casks that define both a legacy Ruby block
and the matching steps block. Runtime handling follows the same precedence:
steps run if present; the legacy block is ignored with a warning. Post-install
or postflight steps are not sandboxed for this iteration because they run only
Homebrew-owned structured operations. The runner shape leaves room to sandbox
future step types that invoke non-Homebrew code.
Future cask work should sandbox all `*flight` run scripts from non-Homebrew and
non-system sources, for example scripts shipped by upstream artifacts.

For each future operation type, check `homebrew/core` and `homebrew/cask`
separately and add formula support only when needed by `homebrew/core` or cask
support only when needed by `homebrew/cask`.

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
   conflict checks against legacy blocks and conservative autocorrection from
   the matching legacy Ruby pattern.
3. Tap `homebrew/core`: convert formulae to the new DSL.
4. Tap `homebrew/cask`: convert casks to the new DSL.

Merge order is `1`, `3`, `4`, `2`. PR `1` ships the DSL and its allow-list so
taps can adopt it; PR `2` (the enforcing/autocorrecting cops) merges last so it
does not flag formulae or casks before the DSL is widely available. After PR `1`
is merged and before PRs `3` and `4` are merged, cut a new `Homebrew/brew`
stable release so `homebrew/core` and `homebrew/cask` CI have the new DSL.

## Formula Patterns

Local scan source: `homebrew/core` at `fb0ca6682b4`.

- `178` of `8,359` formulae define `post_install`.
- `post_install_defined` is the only install-time Ruby execution flag exposed
  through the formula JSON API for bottle installs. I did not find a
  caskfile-only-style source download gate for other formula DSL at bottle
  install time; formula source downloads for API-loaded formulae are used for
  source builds, local patches and resources rather than post-install metadata
  gaps.
- `73` create shared directories in `var`, `etc` or `HOMEBREW_PREFIX`.
  Examples: `glib`, `languagetool`, `mecab`.
- `71` write or patch default configuration/data files.
  Examples: `node@24`, `wemux`, PHP formulae.
- `35` rebuild desktop/cache databases.
  Examples: `gjs`, `geocode-glib`, `efl`.
- `27` initialise service data directories.
  Examples: `postgresql@14`, `mysql`, MariaDB formulae.
- `12` update certificate/trust state.
  Examples: `openssl@3`, `libressl`, `gnutls`.
- `9` only touch marker or lock files.
  Examples: `icecast`, `nethack`, `r`.

## Cask Patterns

Local scan source: `homebrew/cask` at `4ed4e04eaa5`.

- `204` of `7,646` casks currently require the Ruby source at install time
  through `Cask#caskfile_only?`: `181` because of legacy `*flight` blocks and
  `23` because of language blocks only. `27` casks have language blocks in
  total, so `4` have both language blocks and legacy `*flight` blocks.
- I did not find other current cask install-time Ruby source download gates.
  Ordinary artifacts, uninstall/zap directives, caveats, dependencies and
  `on_*` variations are serialised through API data. `*_steps` artifacts are
  also serialised and should not make `caskfile_only?` true.
- `78` flight blocks create directories, touch files or write small files.
  Examples: `86box`, `autogram`, `dante-via`.
- `27` move, copy or symlink files during install or uninstall.
  Examples: `klayout`, `libcblite`, `docker-desktop`.
- `23` change permissions and `37` change ownership.
  Examples: `bitcoin-core`, `anaconda`, `parallels`.
- `16` invoke `/usr/bin/security` for keychain certificate cleanup.
  Examples: `charles`, `autofirma`, `betwixt`.
- `27` casks use language blocks. Large examples include `firefox`,
  `libreoffice-language-pack` and `thunderbird`.

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

## Install Step Examples

- `languagetool`: `post_install_steps { mkdir "log/languagetool", base: :var }`.
- `icecast`: `post_install_steps` with one `mkdir` and two `touch` steps
  under `var/"log/icecast"`.
- `openssl@3`: `post_install_steps` with a forced `symlink` from
  `ca-certificates` `pkgetc/"cert.pem"` into the formula `pkgetc`.
- `86box`: `preflight_steps` with a home-directory `mkdir` for
  the shared ROM directory.
- `klayout`: `preflight_steps` with `move_children` from the
  staged root into the nested `KLayout` directory.
- `libcblite`: `postflight_steps` with relative `symlink` steps
  marked for uninstall cleanup.

## Implementation Checklist

- [x] PR 1, shared install steps framework.
  Commit: `Add install steps framework`.
  Scope: shared ordered step data, a confined steps DSL, a shared runner, cask
  stanza ordering, RuboCop registration, conflict checks and the refactor plan.
  This PR does not wire formula or cask JSON API output or run steps from
  install phases.
  Estimated existing formulae/casks affected: `0` runtime behaviour changes.
  It creates the guardrails for the later `178` formulae with `post_install`
  blocks and `181` casks with flight blocks, but no existing formula or cask
  opts into the new DSL yet.
  Notes for the next PRs: keep the step payload as an ordered array; keep
  `_steps` blocks literal-only; when a phase gets wired in, add the runtime
  warning that steps win over the legacy Ruby block; add conservative
  autocorrection only where every legacy statement maps mechanically.
- [x] PR 2, formula `post_install_steps`.
  Commit: `Add formula install steps`.
  Scope: formula DSL, formula JSON API data, API formula loading, installer and
  `brew postinstall` execution, formula cookbook docs and formula fixture.
  Estimated existing formulae affected: `178` formulae currently define
  `post_install`. The first useful conversion surface is roughly `73` formulae
  creating shared directories and `9` touching marker or lock files; parts of
  the `27` service data directory and `12` certificate/trust formulae may also
  move once their operations fit the supported step set. Runtime behaviour
  changes only for formulae that opt into `post_install_steps`.
  Notes for implementation: default `mkdir`/`touch` to `var` and source/target
  paths to `prefix`; expose the ordered array through `FormulaStruct`; make
  `post_install_steps` take precedence over `post_install`; document that the
  two forms must not be mixed. Keep the tap-wide autocorrect audit in a
  follow-up commit so the implementation can land before converted formulae.
- [x] PR 3, cask flight steps.
  Commit: `Add cask install steps`.
  Scope: cask artifacts for `preflight_steps`, `postflight_steps`,
  `uninstall_preflight_steps` and `uninstall_postflight_steps`, cask API
  serialisation through artifact data, installer casts, cask cookbook docs,
  cask fixture/API loader coverage.
  Estimated existing casks affected: `181` casks currently use flight blocks.
  The first useful conversion surface is roughly `78` casks that create/touch
  files or directories and the supported subset of `27` casks that move or
  symlink files. Runtime behaviour changes only for casks that opt into the
  new `*_steps` stanzas.
  Notes for implementation: default all relative cask paths to `staged_path`;
  keep steps as normal cask artifacts so API loader round-trips work; make
  steps remove/override the matching Ruby flight artifact with a warning; keep
  `uninstall: true` symlink cleanup available for install-phase steps. Keep
  the tap-wide autocorrect audit in a follow-up commit so the implementation
  can land before converted casks.
- [x] PR 4, desktop and cache rebuild actions.
  Estimated existing formulae/casks affected: about `35` formulae run rebuild
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
  Estimated existing formulae/casks affected: about `71` formulae write or
  patch default configuration/data files, and a subset of the `78` file-prep
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
  - [ ] PR 5.2, add the `write` enforcing RuboCops in `Homebrew/brew`.
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
- [ ] PR 6, database and service data directory initialisation.
  Estimated existing formulae/casks affected: about `27` formulae initialise
  service data directories.
  Notes for implementation: model `unless_exists`, CI skip semantics,
  ownership/permission needs and service user assumptions explicitly. Keep
  shell-outs out of the DSL until the sandbox story is decided.
- [ ] PR 7, certificate and trust store actions.
  Estimated existing formulae/casks affected: about `12` formulae update
  certificate/trust state and `16` casks invoke `/usr/bin/security` for
  keychain certificate cleanup.
  Notes for implementation: separate formula-owned symlinked certificate
  actions from keychain mutations; keychain work likely counts as non-Homebrew
  code and should be prepared for sandbox policy decisions.
- [ ] PR 8, cask permission and ownership actions.
  Estimated existing casks affected: about `23` casks change permissions and
  `37` change ownership.
  Notes for implementation: match the existing flight mini-DSL
  `set_permissions` and `set_ownership` semantics first; define sudo/root
  requirements and uninstall behaviour before adding API output.
- [ ] PR 9, cask language variations in API data.
  Estimated existing casks affected: `27` casks use language blocks, with large
  examples including `firefox`, `libreoffice-language-pack` and `thunderbird`.
  Notes for implementation: represent language-specific URLs, checksums and
  returned values without evaluating cask Ruby before fetch; keep the public API
  shape friendly to clients that need to choose one language deterministically.
