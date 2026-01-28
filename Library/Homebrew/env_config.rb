# typed: strict
# frozen_string_literal: true

require "utils/output"

module Homebrew
  # Helper module for querying Homebrew-specific environment variables.
  #
  # @api internal
  module EnvConfig
    include Utils::Output::Mixin
    extend Utils::Output::Mixin

    module_function

    ENVS = T.let({
      HOMEBREW_ALLOWED_TAPS:                     {
        description: "A space-separated list of taps. Homebrew will refuse to install a " \
                     "formula unless it and all of its dependencies are in an official tap " \
                     "or in a tap on this list.",
      },
      HOMEBREW_API_AUTO_UPDATE_SECS:             {
        description: "Check Homebrew's API for new formulae or cask data every " \
                     "`$HOMEBREW_API_AUTO_UPDATE_SECS` seconds. Alternatively, disable API auto-update " \
                     "checks entirely with `$HOMEBREW_NO_AUTO_UPDATE`.",
        default:     450,
      },
      HOMEBREW_API_DOMAIN:                       {
        description:  "Use this URL as the download mirror for Homebrew JSON API. " \
                      "If metadata files at that URL are temporarily unavailable, " \
                      "the default API domain will be used as a fallback mirror.",
        default_text: "`https://formulae.brew.sh/api`.",
        default:      HOMEBREW_API_DEFAULT_DOMAIN,
      },
      HOMEBREW_ARCH:                             {
        description: "Linux only: Pass this value to a type name representing the compiler's `-march` option.",
        default:     "native",
      },
      HOMEBREW_ARTIFACT_DOMAIN:                  {
        description: "Prefix all download URLs, including those for bottles, with this value. " \
                     "For example, `export HOMEBREW_ARTIFACT_DOMAIN=http://localhost:8080` will cause a " \
                     "formula with the URL `https://example.com/foo.tar.gz` to instead download from " \
                     "`http://localhost:8080/https://example.com/foo.tar.gz`. " \
                     "Bottle URLs however, have their domain replaced with this prefix. " \
                     "This results in e.g. " \
                     "`https://ghcr.io/v2/homebrew/core/gettext/manifests/0.21` " \
                     "to instead be downloaded from " \
                     "`http://localhost:8080/v2/homebrew/core/gettext/manifests/0.21`",
      },
      HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK:      {
        description: "When `$HOMEBREW_ARTIFACT_DOMAIN` and `$HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK` are both set, " \
                     "if the request to `$HOMEBREW_ARTIFACT_DOMAIN` fails then Homebrew will error rather than " \
                     "trying any other/default URLs.",
        boolean:     true,
      },
      HOMEBREW_ASK:                              {
        description: "If set, pass `--ask` to all formulae `brew install`, `brew upgrade` and `brew reinstall` " \
                     "commands.",
        boolean:     true,
      },
      HOMEBREW_AUTO_UPDATE_SECS:                 {
        description:  "Run `brew update` once every `$HOMEBREW_AUTO_UPDATE_SECS` seconds before some commands, " \
                      "e.g. `brew install`, `brew upgrade` or `brew tap`. Alternatively, " \
                      "disable auto-update entirely with `$HOMEBREW_NO_AUTO_UPDATE`.",
        default_text: "`86400` (24 hours), `3600` (1 hour) if a developer command has been run " \
                      "or `300` (5 minutes) if `$HOMEBREW_NO_INSTALL_FROM_API` is set.",
      },
      HOMEBREW_BAT:                              {
        description: "If set, use `bat` for the `brew cat` command.",
        boolean:     true,
      },
      HOMEBREW_BAT_CONFIG_PATH:                  {
        description:  "Use this as the `bat` configuration file.",
        default_text: "`$BAT_CONFIG_PATH`.",
      },
      HOMEBREW_BAT_THEME:                        {
        description:  "Use this as the `bat` theme for syntax highlighting.",
        default_text: "`$BAT_THEME`.",
      },
      HOMEBREW_BOTTLE_DOMAIN:                    {
        description:  "Use this URL as the download mirror for bottles. " \
                      "If bottles at that URL are temporarily unavailable, " \
                      "the default bottle domain will be used as a fallback mirror. " \
                      "For example, `export HOMEBREW_BOTTLE_DOMAIN=http://localhost:8080` will cause all bottles " \
                      "to download from the prefix `http://localhost:8080/`. " \
                      "If bottles are not available at `$HOMEBREW_BOTTLE_DOMAIN` " \
                      "they will be downloaded from the default bottle domain.",
        default_text: "`https://ghcr.io/v2/homebrew/core`.",
        default:      HOMEBREW_BOTTLE_DEFAULT_DOMAIN,
      },
      HOMEBREW_BREW_GIT_REMOTE:                  {
        description: "Use this URL as the Homebrew/brew `git`(1) remote.",
        default:     HOMEBREW_BREW_DEFAULT_GIT_REMOTE,
      },
      HOMEBREW_BROWSER:                          {
        description:  "Use this as the browser when opening project homepages.",
        default_text: "`$BROWSER` or the OS's default browser.",
      },
      HOMEBREW_BUNDLE_USER_CACHE:                {
        description: "If set, use this directory as the `bundle`(1) user cache.",
      },
      HOMEBREW_CACHE:                            {
        description:  "Use this directory as the download cache.",
        default_text: "macOS: `~/Library/Caches/Homebrew`, " \
                      "Linux: `$XDG_CACHE_HOME/Homebrew` or `~/.cache/Homebrew`.",
        default:      HOMEBREW_DEFAULT_CACHE,
      },
      HOMEBREW_CASK_OPTS:                        {
        description: "Append these options to all `cask` commands. All `--*dir` options, " \
                     "`--language`, `--require-sha` and `--no-binaries` are supported. " \
                     "For example, you might add something like the following to your " \
                     "`~/.profile`, `~/.bash_profile`, or `~/.zshenv`:" \
                     "\n\n    `export HOMEBREW_CASK_OPTS=\"--appdir=${HOME}/Applications --fontdir=/Library/Fonts\"`",
      },
      HOMEBREW_CLEANUP_MAX_AGE_DAYS:             {
        description: "Cleanup all cached files older than this many days.",
        default:     120,
      },
      HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS:       {
        description: "If set, `brew install`, `brew upgrade` and `brew reinstall` will cleanup all formulae " \
                     "when this number of days has passed.",
        default:     30,
      },
      HOMEBREW_COLOR:                            {
        description: "If set, force colour output on non-TTY outputs.",
        boolean:     true,
      },
      HOMEBREW_CORE_GIT_REMOTE:                  {
        description:  "Use this URL as the Homebrew/homebrew-core `git`(1) remote.",
        default_text: "`https://github.com/Homebrew/homebrew-core`.",
        default:      HOMEBREW_CORE_DEFAULT_GIT_REMOTE,
      },
      HOMEBREW_CURLRC:                           {
        description: "If set to an absolute path (i.e. beginning with `/`), pass it with `--config` when invoking " \
                     "`curl`(1). " \
                     "If set but _not_ a valid path, do not pass `--disable`, which disables the " \
                     "use of `.curlrc`.",
      },
      HOMEBREW_CURL_PATH:                        {
        description: "Linux only: Set this value to a new enough `curl` executable for Homebrew to use.",
        default:     "curl",
      },
      HOMEBREW_CURL_RETRIES:                     {
        description: "Pass the given retry count to `--retry` when invoking `curl`(1).",
        default:     3,
      },
      HOMEBREW_CURL_VERBOSE:                     {
        description: "If set, pass `--verbose` when invoking `curl`(1).",
        boolean:     true,
      },
      HOMEBREW_DEBUG:                            {
        description: "If set, always assume `--debug` when running commands.",
        boolean:     true,
      },
      HOMEBREW_DEVELOPER:                        {
        description: "If set, tweak behaviour to be more relevant for Homebrew developers (active or " \
                     "budding) by e.g. turning warnings into errors.",
        boolean:     true,
      },
      HOMEBREW_DISABLE_DEBREW:                   {
        description: "If set, the interactive formula debugger available via `--debug` will be disabled.",
        boolean:     true,
      },
      HOMEBREW_DISABLE_LOAD_FORMULA:             {
        description: "If set, refuse to load formulae. This is useful when formulae are not trusted (such " \
                     "as in pull requests).",
        boolean:     true,
      },
      HOMEBREW_DISPLAY:                          {
        description:  "Use this X11 display when opening a page in a browser, for example with " \
                      "`brew home`. Primarily useful on Linux.",
        default_text: "`$DISPLAY`.",
      },
      HOMEBREW_DISPLAY_INSTALL_TIMES:            {
        description: "If set, print install times for each formula at the end of the run.",
        boolean:     true,
      },
      HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN: {
        description: "Use this base64 encoded username and password for authenticating with a Docker registry " \
                     "proxying GitHub Packages. If set to `none`, no authentication header will be sent. " \
                     "This can be used, if remote `$HOMEBREW_BOTTLE_DOMAIN` does not support any authentication. " \
                     "If `$HOMEBREW_DOCKER_REGISTRY_TOKEN` is set, it will be used instead.",
      },
      HOMEBREW_DOCKER_REGISTRY_TOKEN:            {
        description: "Use this bearer token for authenticating with a Docker registry proxying GitHub Packages. " \
                     "Preferred over `$HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN`.",
      },
      HOMEBREW_DOWNLOAD_CONCURRENCY:             {
        description: "Homebrew will download in parallel using this many concurrent connections. " \
                     "The default, `auto`, will use twice the number of available CPU cores " \
                     "(what our benchmarks showed to produce the best performance). " \
                     "If set to `1`, Homebrew will download in serial.",
        default:     "auto",
      },
      HOMEBREW_EDITOR:                           {
        description:  "Use this editor when editing a single formula, or several formulae in the " \
                      "same directory." \
                      "\n\n    *Note:* `brew edit` will open all of Homebrew as discontinuous files " \
                      "and directories. Visual Studio Code can handle this correctly in project mode, but many " \
                      "editors will do strange things in this case.",
        default_text: "`$EDITOR` or `$VISUAL`.",
      },
      HOMEBREW_ENV_SYNC_STRICT:                  {
        description: "If set, `brew *env-sync` will only sync the exact installed versions of formulae.",
        boolean:     true,
      },
      HOMEBREW_EVAL_ALL:                         {
        description: "If set, `brew` commands evaluate all formulae and casks, executing their arbitrary code, by " \
                     "default without requiring `--eval-all`. Required to cache formula and cask descriptions.",
        boolean:     true,
      },
      HOMEBREW_FAIL_LOG_LINES:                   {
        description: "Output this many lines of output on formula `system` failures.",
        default:     15,
      },
      HOMEBREW_FORBIDDEN_CASKS:                  {
        description: "A space-separated list of casks. Homebrew will refuse to install a " \
                     "cask if it or any of its dependencies is on this list.",
      },
      HOMEBREW_FORBIDDEN_CASK_ARTIFACTS:         {
        description: "A space-separated list of cask artifact types (e.g. `pkg installer`) that should be " \
                     "forbidden during cask installation. " \
                     "Valid values: `pkg`, `installer`, `binary`, `uninstall`, `zap`, `app`, `suite`, " \
                     "`artifact`, `prefpane`, `qlplugin`, `dictionary`, `font`, `service`, `colorpicker`, " \
                     "`inputmethod`, `internetplugin`, `audiounitplugin`, `vstplugin`, `vst3plugin`, " \
                     "`screensaver`, `keyboardlayout`, `mdimporter`, `preflight`, `postflight`, " \
                     "`manpage`, `bashcompletion`, `fishcompletion`, `zshcompletion`, `stageonly`.",
      },
      HOMEBREW_FORBIDDEN_FORMULAE:               {
        description: "A space-separated list of formulae. Homebrew will refuse to install a " \
                     "formula or cask if it or any of its dependencies is on this list.",
      },
      HOMEBREW_FORBIDDEN_LICENSES:               {
        description: "A space-separated list of SPDX license identifiers. Homebrew will refuse to install a " \
                     "formula if it or any of its dependencies has a license on this list.",
      },
      HOMEBREW_FORBIDDEN_OWNER:                  {
        description: "The person who has set any `$HOMEBREW_FORBIDDEN_*` variables.",
        default:     "you",
      },
      HOMEBREW_FORBIDDEN_OWNER_CONTACT:          {
        description: "How to contact the `$HOMEBREW_FORBIDDEN_OWNER`, if set and necessary.",
      },
      HOMEBREW_FORBIDDEN_TAPS:                   {
        description: "A space-separated list of taps. Homebrew will refuse to install a " \
                     "formula if it or any of its dependencies is in a tap on this list.",
      },
      HOMEBREW_FORBID_CASKS:                     {
        description: "If set, Homebrew will refuse to install any casks.",
        boolean:     true,
      },
      HOMEBREW_FORBID_PACKAGES_FROM_PATHS:       {
        description:  "If set, Homebrew will refuse to read formulae or casks provided from file paths, " \
                      "e.g. `brew install ./package.rb`.",
        boolean:      true,
        default_text: "true unless `$HOMEBREW_DEVELOPER` is set.",
      },
      HOMEBREW_FORCE_API_AUTO_UPDATE:            {
        description: "If set, update the Homebrew API formula or cask data even if " \
                     "`$HOMEBREW_NO_AUTO_UPDATE` is set.",
        boolean:     true,
      },
      HOMEBREW_FORCE_BREWED_CA_CERTIFICATES:     {
        description: "If set, always use a Homebrew-installed `ca-certificates` rather than the system version. " \
                     "Automatically set if the system version is too old.",
        boolean:     true,
      },
      HOMEBREW_FORCE_BREWED_CURL:                {
        description: "If set, always use a Homebrew-installed `curl`(1) rather than the system version. " \
                     "Automatically set if the system version of `curl` is too old.",
        boolean:     true,
      },
      HOMEBREW_FORCE_BREWED_GIT:                 {
        description: "If set, always use a Homebrew-installed `git`(1) rather than the system version. " \
                     "Automatically set if the system version of `git` is too old.",
        boolean:     true,
      },
      HOMEBREW_FORCE_BREW_WRAPPER:               {
        description: "If set, require `brew` to be invoked by the value of " \
                     "`$HOMEBREW_FORCE_BREW_WRAPPER` for non-trivial `brew` commands.",
      },
      HOMEBREW_FORCE_VENDOR_RUBY:                {
        description: "If set, always use Homebrew's vendored, relocatable Ruby version even if the system version " \
                     "of Ruby is new enough.",
        boolean:     true,
      },
      HOMEBREW_FORMULA_BUILD_NETWORK:            {
        description: "If set, controls network access to the sandbox for formulae builds. Overrides any " \
                     "controls set through DSL usage inside formulae. Must be `allow` or `deny`. If no value is " \
                     "set through this environment variable or DSL usage, the default behaviour is `allow`.",
      },
      HOMEBREW_FORMULA_POSTINSTALL_NETWORK:      {
        description: "If set, controls network access to the sandbox for formulae postinstall. Overrides any " \
                     "controls set through DSL usage inside formulae. Must be `allow` or `deny`. If no value is " \
                     "set through this environment variable or DSL usage, the default behaviour is `allow`.",
      },
      HOMEBREW_FORMULA_TEST_NETWORK:             {
        description: "If set, controls network access to the sandbox for formulae test. Overrides any " \
                     "controls set through DSL usage inside formulae. Must be `allow` or `deny`. If no value is " \
                     "set through this environment variable or DSL usage, the default behaviour is `allow`.",
      },
      HOMEBREW_GITHUB_API_TOKEN:                 {
        description: "Use this personal access token for the GitHub API, for features such as " \
                     "`brew search`. You can create one at <https://github.com/settings/tokens>. If set, " \
                     "GitHub will allow you a greater number of API requests. For more information, see: " \
                     "<https://docs.github.com/en/rest/overview/rate-limits-for-the-rest-api>" \
                     "\n\n    *Note:* Homebrew doesn't require permissions for any of the scopes, but some " \
                     "developer commands may require additional permissions.",
      },
      HOMEBREW_GITHUB_PACKAGES_TOKEN:            {
        description: "Use this GitHub personal access token when accessing the GitHub Packages Registry " \
                     "(where bottles may be stored).",
      },
      HOMEBREW_GITHUB_PACKAGES_USER:             {
        description: "Use this username when accessing the GitHub Packages Registry (where bottles may be stored).",
      },
      HOMEBREW_GIT_COMMITTER_EMAIL:              {
        description: "Set the Git committer email to this value.",
      },
      HOMEBREW_GIT_COMMITTER_NAME:               {
        description: "Set the Git committer name to this value.",
      },
      HOMEBREW_GIT_EMAIL:                        {
        description: "Set the Git author name and, if `$HOMEBREW_GIT_COMMITTER_EMAIL` is unset, committer email to " \
                     "this value.",
      },
      HOMEBREW_GIT_NAME:                         {
        description: "Set the Git author name and, if `$HOMEBREW_GIT_COMMITTER_NAME` is unset, committer name to " \
                     "this value.",
      },
      HOMEBREW_GIT_PATH:                         {
        description: "Linux only: Set this value to a new enough `git` executable for Homebrew to use.",
        default:     "git",
      },
      HOMEBREW_INSTALL_BADGE:                    {
        description:  "Print this text before the installation summary of each successful build.",
        default_text: 'The "Beer Mug" emoji.',
        default:      "🍺",
      },
      HOMEBREW_LIVECHECK_AUTOBUMP:               {
        description: "If set, `brew livecheck` will include data for packages that are autobumped by BrewTestBot.",
        boolean:     true,
      },
      HOMEBREW_LIVECHECK_WATCHLIST:              {
        description:  "Consult this file for the list of formulae to check by default when no formula argument " \
                      "is passed to `brew livecheck`.",
        default_text: "`${XDG_CONFIG_HOME}/homebrew/livecheck_watchlist.txt` if `$XDG_CONFIG_HOME` is set " \
                      "or `~/.homebrew/livecheck_watchlist.txt` otherwise.",
        default:      "#{ENV.fetch("HOMEBREW_USER_CONFIG_HOME")}/livecheck_watchlist.txt",
      },
      HOMEBREW_LOCK_CONTEXT:                     {
        description: "If set, Homebrew will add this output as additional context for locking errors. " \
                     "This is useful when running `brew` in the background.",
      },
      HOMEBREW_LOGS:                             {
        description:  "Use this directory to store log files.",
        default_text: "macOS: `~/Library/Logs/Homebrew`, " \
                      "Linux: `${XDG_CACHE_HOME}/Homebrew/Logs` or `~/.cache/Homebrew/Logs`.",
        default:      HOMEBREW_DEFAULT_LOGS,
      },
      HOMEBREW_MAKE_JOBS:                        {
        description:  "Use this value as the number of parallel jobs to run when building with `make`(1).",
        default_text: "The number of available CPU cores.",
        default:      lambda {
          require "os"
          require "hardware"
          Hardware::CPU.cores
        },
      },
      HOMEBREW_NO_ANALYTICS:                     {
        description: "If set, do not send analytics. Google Analytics were destroyed. " \
                     "For more information, see: <https://docs.brew.sh/Analytics>",
        boolean:     true,
      },
      HOMEBREW_NO_AUTOREMOVE:                    {
        description: "If set, calls to `brew cleanup` and `brew uninstall` will not automatically " \
                     "remove unused formula dependents.",
        boolean:     true,
      },
      HOMEBREW_NO_AUTO_UPDATE:                   {
        description: "If set, do not automatically update before running some commands, e.g. " \
                     "`brew install`, `brew upgrade` or `brew tap`. Preferably, " \
                     "run this less often by setting `$HOMEBREW_AUTO_UPDATE_SECS` to a value higher than the " \
                     "default. Note that setting this and e.g. tapping new taps may result in a broken  " \
                     "configuration. Please ensure you always run `brew update` before reporting any issues.",
        boolean:     true,
      },
      HOMEBREW_NO_BOOTSNAP:                      {
        description: "If set, do not use Bootsnap to speed up repeated `brew` calls.",
        boolean:     true,
      },
      HOMEBREW_NO_CLEANUP_FORMULAE:              {
        description: "A comma-separated list of formulae. Homebrew will refuse to clean up " \
                     "or autoremove a formula if it appears on this list.",
      },
      HOMEBREW_NO_COLOR:                         {
        description:  "If set, do not print text with colour added.",
        default_text: "`$NO_COLOR`.",
        boolean:      true,
      },
      HOMEBREW_NO_EMOJI:                         {
        description: "If set, do not print `$HOMEBREW_INSTALL_BADGE` on a successful build.",
        boolean:     true,
      },
      HOMEBREW_NO_ENV_HINTS:                     {
        description: "If set, do not print any hints about changing Homebrew's behaviour with environment variables.",
        boolean:     true,
      },
      HOMEBREW_NO_FORCE_BREW_WRAPPER:            {
        description: "`Deprecated:` If set, disables `$HOMEBREW_FORCE_BREW_WRAPPER` behaviour, even if set.",
        boolean:     true,
      },
      HOMEBREW_NO_GITHUB_API:                    {
        description: "If set, do not use the GitHub API, e.g. for searches or fetching relevant issues " \
                     "after a failed install.",
        boolean:     true,
      },
      HOMEBREW_NO_INSECURE_REDIRECT:             {
        description: "If set, forbid redirects from secure HTTPS to insecure HTTP." \
                     "\n\n    *Note:* while ensuring your downloads are fully secure, this is likely to cause " \
                     "sources for certain formulae hosted by SourceForge, GNU or GNOME to fail to download.",
        boolean:     true,
      },
      HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:    {
        description: "If set, do not check for broken linkage of dependents or outdated dependents after " \
                     "installing, upgrading or reinstalling formulae. This will result in fewer dependents " \
                     "(and their dependencies) being upgraded or reinstalled but may result in more breakage " \
                     "from running `brew install` <formula> or `brew upgrade` <formula>.",
        boolean:     true,
      },
      HOMEBREW_NO_INSTALL_CLEANUP:               {
        description: "If set, `brew install`, `brew upgrade` and `brew reinstall` will never automatically " \
                     "cleanup installed/upgraded/reinstalled formulae or all formulae every " \
                     "`$HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS` days. Alternatively, `$HOMEBREW_NO_CLEANUP_FORMULAE` " \
                     "allows specifying specific formulae to not clean up.",
        boolean:     true,
      },
      HOMEBREW_NO_INSTALL_FROM_API:              {
        description: "If set, do not install formulae and casks in homebrew/core and homebrew/cask taps using " \
                     "Homebrew's API and instead use (large, slow) local checkouts of these repositories.",
        boolean:     true,
      },
      HOMEBREW_NO_INSTALL_UPGRADE:               {
        description: "If set, `brew install` <formula|cask> will not upgrade <formula|cask> if it is installed but " \
                     "outdated.",
        boolean:     true,
      },
      HOMEBREW_NO_UPDATE_REPORT_NEW:             {
        description: "If set, `brew update` will not show the list of newly added formulae/casks.",
        boolean:     true,
      },
      HOMEBREW_NO_VERIFY_ATTESTATIONS:           {
        description: "If set, Homebrew will not verify cryptographic attestations of build provenance for bottles " \
                     "from homebrew-core.",
        boolean:     true,
      },
      HOMEBREW_PIP_INDEX_URL:                    {
        description:  "If set, `brew install` <formula> will use this URL to download PyPI package resources.",
        default_text: "`https://pypi.org/simple`.",
      },
      HOMEBREW_PRY:                              {
        description: "If set, use Pry for the `brew irb` command.",
        boolean:     true,
      },
      HOMEBREW_SIMULATE_MACOS_ON_LINUX:          {
        description: "If set, running Homebrew on Linux will simulate certain macOS code paths. This is useful " \
                     "when auditing macOS formulae while on Linux.",
        boolean:     true,
      },
      HOMEBREW_SKIP_OR_LATER_BOTTLES:            {
        description: "If set along with `$HOMEBREW_DEVELOPER`, do not use bottles from older versions " \
                     "of macOS. This is useful in development on new macOS versions.",
        boolean:     true,
      },
      HOMEBREW_SORBET_RECURSIVE:                 {
        description: "If set along with `$HOMEBREW_SORBET_RUNTIME`, enable recursive typechecking using Sorbet. " \
                     "Auomatically enabled when running tests.",
        boolean:     true,
      },
      HOMEBREW_SORBET_RUNTIME:                   {
        description: "If set, enable runtime typechecking using Sorbet. " \
                     "Set by default for `$HOMEBREW_DEVELOPER` or when running some developer commands.",
        boolean:     true,
      },
      HOMEBREW_SSH_CONFIG_PATH:                  {
        description:  "If set, Homebrew will use the given config file instead of `~/.ssh/config` when " \
                      "fetching Git repositories over SSH.",
        default_text: "`~/.ssh/config`",
      },
      HOMEBREW_SUDO_THROUGH_SUDO_USER:           {
        description: "If set, Homebrew will use the `$SUDO_USER` environment variable to define the user to " \
                     "`sudo`(8) through when running `sudo`(8).",
        boolean:     true,
      },
      HOMEBREW_SVN:                              {
        description:  "Use this as the `svn`(1) binary.",
        default_text: "A Homebrew-built Subversion (if installed), or the system-provided binary.",
      },
      HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY:        {
        description: "If set in Homebrew's system-wide environment file (`/etc/homebrew/brew.env`), " \
                     "the system-wide environment file will be loaded last to override any prefix or user settings.",
        boolean:     true,
      },
      HOMEBREW_TEMP:                             {
        description:  "Use this path as the temporary directory for building packages. Changing " \
                      "this may be needed if your system temporary directory and Homebrew prefix are on " \
                      "different volumes, as macOS has trouble moving symlinks across volumes when the target " \
                      "does not yet exist. This issue typically occurs when using FileVault or custom SSD " \
                      "configurations.",
        default_text: "macOS: `/private/tmp`, Linux: `/var/tmp`.",
        default:      HOMEBREW_DEFAULT_TEMP,
      },
      HOMEBREW_UPDATE_TO_TAG:                    {
        description: "If set, always use the latest stable tag (even if developer commands " \
                     "have been run).",
        boolean:     true,
      },
      HOMEBREW_UPGRADE_GREEDY:                   {
        description: "If set, pass `--greedy` to all cask upgrade commands.",
        boolean:     true,
      },
      HOMEBREW_UPGRADE_GREEDY_CASKS:             {
        description: "A space-separated list of casks. Homebrew will act as " \
                     "if `--greedy` was passed when upgrading any cask on this list.",
      },
      HOMEBREW_USE_INTERNAL_API:                 {
        description: "If set, test the new beta internal API for fetching formula and cask data.",
        boolean:     true,
      },
      HOMEBREW_VERBOSE:                          {
        description: "If set, always assume `--verbose` when running commands.",
        boolean:     true,
      },
      HOMEBREW_VERBOSE_USING_DOTS:               {
        description: "If set, verbose output will print a `.` no more than once a minute. This can be " \
                     "useful to avoid long-running Homebrew commands being killed due to no output.",
        boolean:     true,
      },
      HOMEBREW_VERIFY_ATTESTATIONS:              {
        description: "If set, Homebrew will use the `gh` tool to verify cryptographic attestations " \
                     "of build provenance for bottles from homebrew-core.",
        boolean:     true,
      },
      SUDO_ASKPASS:                              {
        description: "If set, pass the `-A` option when calling `sudo`(8).",
      },
      all_proxy:                                 {
        description: "Use this SOCKS5 proxy for `curl`(1), `git`(1) and `svn`(1) when downloading through Homebrew.",
      },
      ftp_proxy:                                 {
        description: "Use this FTP proxy for `curl`(1), `git`(1) and `svn`(1) when downloading through Homebrew.",
      },
      http_proxy:                                {
        description: "Use this HTTP proxy for `curl`(1), `git`(1) and `svn`(1) when downloading through Homebrew.",
      },
      https_proxy:                               {
        description: "Use this HTTPS proxy for `curl`(1), `git`(1) and `svn`(1) when downloading through Homebrew.",
      },
      no_proxy:                                  {
        description: "A comma-separated list of hostnames and domain names excluded " \
                     "from proxying by `curl`(1), `git`(1) and `svn`(1) when downloading through Homebrew.",
      },
    }.freeze, T::Hash[Symbol, T::Hash[Symbol, T.untyped]])

    sig { params(env: Symbol, hash: T::Hash[Symbol, T.untyped]).returns(String) }
    def env_method_name(env, hash)
      method_name = env.to_s
                       .sub(/^HOMEBREW_/, "")
                       .downcase
      method_name = "#{method_name}?" if hash[:boolean]
      method_name
    end

    CUSTOM_IMPLEMENTATIONS = T.let(Set.new([
      :HOMEBREW_MAKE_JOBS,
      :HOMEBREW_CASK_OPTS,
      :HOMEBREW_FORBID_PACKAGES_FROM_PATHS,
      :HOMEBREW_DOWNLOAD_CONCURRENCY,
      :HOMEBREW_USE_INTERNAL_API,
    ]).freeze, T::Set[Symbol])

    FALSY_VALUES = T.let(%w[false no off nil 0].freeze, T::Array[String])

    ENVS.each do |env, hash|
      # Needs a custom implementation.
      next if CUSTOM_IMPLEMENTATIONS.include?(env)

      method_name = env_method_name(env, hash)
      env = env.to_s

      if hash[:boolean]
        define_method(method_name) do
          env_value = ENV.fetch(env, nil)

          env_value.present? && FALSY_VALUES.exclude?(env_value.downcase)
        end
      elsif hash[:default].present?
        define_method(method_name) do
          ENV[env].presence || hash.fetch(:default).to_s
        end
      else
        define_method(method_name) do
          ENV[env].presence
        end
      end
    end

    sig { returns(String) }
    def make_jobs
      jobs = ENV["HOMEBREW_MAKE_JOBS"].to_i
      return jobs.to_s if jobs.positive?

      ENVS.fetch(:HOMEBREW_MAKE_JOBS)
          .fetch(:default)
          .call
          .to_s
    end

    sig { returns(T::Array[String]) }
    def cask_opts
      Shellwords.shellsplit(ENV.fetch("HOMEBREW_CASK_OPTS", ""))
    end

    sig { returns(T::Boolean) }
    def cask_opts_binaries?
      cask_opts.reverse_each do |opt|
        return true if opt == "--binaries"
        return false if opt == "--no-binaries"
      end

      true
    end

    sig { returns(T::Boolean) }
    def cask_opts_quarantine?
      cask_opts.reverse_each do |opt|
        return true if opt == "--quarantine"
        return false if opt == "--no-quarantine"
      end

      true
    end

    sig { returns(T::Boolean) }
    def cask_opts_require_sha?
      cask_opts.include?("--require-sha")
    end

    sig { returns(T::Boolean) }
    def forbid_packages_from_paths?
      # Undocumented opt-out for internal use.
      return false if ENV["HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS"].present?

      return true if ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"].present?

      # Provide an opt-out for tests and developers.
      # Our testing framework installs formulae from file paths all over the place.
      ENV["HOMEBREW_TESTS"].blank? && ENV["HOMEBREW_DEVELOPER"].blank?
    end

    sig { returns(T::Boolean) }
    def automatically_set_no_install_from_api?
      ENV["HOMEBREW_AUTOMATICALLY_SET_NO_INSTALL_FROM_API"].present?
    end

    sig { returns(T::Boolean) }
    def devcmdrun?
      Homebrew::Settings.read("devcmdrun") == "true"
    end

    sig { returns(Integer) }
    def download_concurrency
      concurrency = ENV.fetch("HOMEBREW_DOWNLOAD_CONCURRENCY", "auto")
      concurrency = if concurrency == "auto"
        require "os"
        require "hardware"
        Hardware::CPU.cores * 2
      else
        concurrency.to_i
      end

      [concurrency, 1].max
    end

    sig { returns(T::Boolean) }
    def use_internal_api?
      # TODO: re-enable this when the internal API is ready again.
      false
    end
  end
end
