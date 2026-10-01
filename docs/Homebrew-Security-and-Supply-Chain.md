---
description: Homebrew security and supply chain defences, including formula and Cask trust models, checksums, signed metadata, bottles, Gatekeeper, sandboxing and tap trust.
redirect_from:
  - /Supply-Chain-Security
last_review_date: "2026-09-19"
---

# Homebrew Security and Supply Chain

Homebrew installs software from across the open source ecosystem.
That makes the security of the software supply chain, the humans involved, repositories, build systems and download servers that turn source code into something you run, a core concern for us.
This Homebrew security guide explains the recent supply-chain security incidents affecting other package managers, how Homebrew's trust model differs and the steps we have taken to protect our users.

* Table of Contents
{:toc}

## Recent incidents in other ecosystems

The npm and PyPI ecosystems have been repeatedly targeted by supply-chain attacks.
Recurring patterns include:

* **Maintainer account takeover.**
  Attackers phish or credential-stuff a package maintainer's account, then publish a malicious version of an otherwise-trusted package.
  In September 2025 a maintainer of widely-depended-on npm packages (including `chalk` and `debug`, together totalling billions of weekly downloads) was phished by an email impersonating an npm two-factor reset; the malicious versions were live for roughly two hours and shipped a crypto-stealer that rewrote wallet addresses in transactions.
* **Self-propagating worms.**
  The "Shai-Hulud" npm campaign used a compromised package to steal credentials (npm tokens, GitHub personal access tokens and cloud keys) from any developer who installed it, then used those stolen tokens to publish trojanised versions of further packages automatically, spreading across hundreds of packages without human involvement.
* **Typosquatting and slopsquatting.**
  Malicious packages are published under names close to popular ones, or under plausible-sounding names hallucinated by LLMs, so that a typo or an over-trusting AI agent installs malware.
* **Malicious install-time code.**
  Both npm (`preinstall`/`postinstall` lifecycle scripts) and PyPI (arbitrary code in `setup.py`) execute publisher-controlled code on the installing machine by design, so a single bad release runs immediately on every machine that installs it.
* **Instant, unreviewed publishing.**
  A new version is live for the whole world the moment it is pushed.
  There is no human in the loop and no delay, so a compromised release can reach huge numbers of machines before anyone notices.

The common thread is that these registries are designed for unilateral, instantaneous publishing by individual package authors, with code execution on install and no independent review.
A single compromised credential turns into immediate, automated, worldwide code execution.

## How Homebrew is different

The Homebrew team is aware of the supply-chain security issues with other package managers.
Homebrew's design differs in several structural ways that limit the blast radius of an upstream compromise.
Most of these protections long predate the recent wave of supply-chain attacks and the current focus on them; they are core to how Homebrew has always packaged software rather than a reaction to any single incident.

### Human review on all changes

Every change to a Homebrew repository, including all our official taps (such as [homebrew/core](https://github.com/Homebrew/homebrew-core) and [homebrew/cask](https://github.com/Homebrew/homebrew-cask)), goes through a pull request that is reviewed and merged by a human maintainer.
Upstream authors cannot publish directly into official Homebrew repositories.
There is always a human in the loop between an upstream release and that release reaching Homebrew users.
The stale lead maintainer PR approval workflow is a narrow `Homebrew/brew` exception that can approve only non-fork, non-draft PRs by lead maintainers after recent maintainer review activity, Copilot review, passing CI, at least 48 hours open with no human review, a weekday approval window and a check that the PR does not modify sensitive paths.
These laxer standards are acceptable in `Homebrew/brew` because most users run the stable branch and a human must still carry out a `Homebrew/brew` release before those changes reach stable Homebrew users.

### Maintainers, not package owners

All package maintainers are Homebrew maintainers, not the individual upstream authors of each package.
Trust is concentrated in a vetted team that reviews changes across the whole repository, rather than being delegated to thousands of independent publishers each of whom is a single point of failure.

Maintainer access and activity are reviewed regularly.
Maintainers are expected to make a minimum number of meaningful contributions each quarter; those who fall below the threshold receive a private warning and are removed if they remain inactive.
Maintainers must also enable two-factor authentication on their GitHub account, avoid SMS as a second factor and regularly remove unneeded personal access tokens, reducing the chance of the account takeovers that have compromised other ecosystems.

### Curated package namespaces

Names in Homebrew's official taps are maintainer-curated, not first-come-first-served.
A new formula or cask name is accepted only through the same reviewed pull request process as the package definition itself, so typosquats, slopsquats and misleading names can be rejected before they exist in the official namespace.
Removed formulae and casks can only be restored through maintainer-reviewed pull requests, and we generally avoid reusing old names unless there is a good reason.
Strangers cannot unilaterally claim removed names; old names remain under Homebrew's control through the official repositories, rename metadata and migration metadata.
This makes the official Homebrew namespace structurally resistant to the typosquatting and revival-hijack attacks that affect open registries.

### No trust in third-party repositories

Homebrew does not trust, recommend or automatically install from any third-party non-Homebrew repositories.
Only official Homebrew taps and built-in commands are trusted by default.
A non-official tap is executable code, not plain metadata, so loading it can run Ruby with your user's privileges.
Non-official taps require explicit trust by default, and `brew trust` lets you trust a single formula, cask or command rather than a whole tap.
See [Tap Trust](Tap-Trust.md) for how to trust only what you need with `brew trust`, `brew untrust` and the `Brewfile` `trusted: true` option.

Homebrew's [tap migrations](Migrating-A-Formula-To-A-Tap.md) stay within the Homebrew organisation: a formula or cask is only ever migrated into or within official Homebrew taps, never out to a third-party tap.
A rename or move therefore cannot silently redirect users to a non-Homebrew repository.
When GitHub redirects a tap after its owner or repository is renamed, Homebrew follows the verified redirect, retargets the local tap to the new canonical remote and invalidates trust entries for the old tap name rather than silently carrying trust across.

### Not automatically deferring to upstream

Homebrew's primary responsibility is to its users, not to upstream vendors.
We will not usually deprecate, disable or remove a package, or redirect it to an upstream tap, only because upstream asks us to; technical breakage, policy violations or the wider project's needs carry more weight.
This is itself a defence against upstream compromise: an attacker who takes over an upstream account cannot use a takedown or redirect request to push Homebrew users towards a malicious replacement.
See [Working with Homebrew as an Upstream Project](Working-with-Homebrew-as-an-Upstream-Project.md).

### Checksummed downloads pinned in reviewed metadata

A formula pins each download to an explicit `sha256` checksum that lives in the formula file.
The checksum is part of the human-reviewed change, and Homebrew refuses to install a download whose contents do not match.
An attacker who swaps out a tarball on an upstream server after the fact causes a checksum mismatch and a failed install rather than silent compromise.
Updating the checksum requires another reviewed pull request, and we review these checksum changes to verify they do not appear malicious.

### Signed JSON API metadata

Formulae and casks are Ruby package definitions, and Ruby cannot be safely inspected without executing it.
For default installs from official taps, Homebrew mitigates that by consuming precomputed JSON API metadata instead of evaluating core formula or cask Ruby locally.
The default API files, including `formula.jws.json`, `cask.jws.json` and the internal package JSON files used for installs, are JWS-signed and verified by Homebrew before use.
That means normal bottled installs consume signed, structured package data generated by Homebrew rather than executable package definitions from the user's local machine.
These signed files are uploaded through the separate [`Homebrew/formulae.brew.sh`](https://github.com/Homebrew/formulae.brew.sh) repository, adding another separation between the `Homebrew/brew` client, the `Homebrew/homebrew-core` and `Homebrew/homebrew-cask` package repositories and JSON API publishing.
Developers and users can still opt out with `HOMEBREW_NO_INSTALL_FROM_API`, for example when editing formulae locally or building unsupported paths from source.

### Bottles built by Homebrew

The vast majority of users install [bottles](Bottles.md), the precompiled binary packages Homebrew builds itself on [BrewTestBot](BrewTestBot.md) from the reviewed formula, rather than running upstream build scripts on their own machine.
`homebrew/core` formulae are built from source by Homebrew's own sandboxed CI, not uploaded prebuilt by upstream, and each build runs on an ephemeral CI runner that is discarded afterwards, so a compromised build cannot persist between packages or exfiltrate long-lived secrets.
The resulting binaries are themselves checksummed in the formula.
Even separate bottling stages do not blindly trust one another's inputs and outputs.
`brew test-bot` tracks bottle JSON and tarball checksums, rejects missing, changed or unexpected bottle artifacts, and only reuses a cached bottle when its bottle JSON points to a tap revision where the formula and its relevant dependencies have not changed.
Some artifact-handling steps run with `HOMEBREW_DISABLE_LOAD_FORMULA=1`, so cached bottle artifacts can be fetched and verified without evaluating formula Ruby.
Building from source has already protected Homebrew users: in the 2026 Trivy compromise the upstream advisory noted that the `homebrew/core` formula was unaffected because it was built from source rather than from the retagged release binaries.

Homebrew only builds and supports bottles for `homebrew/core`, and casks for `homebrew/cask`; third-party taps are [unsupported](Support-Tiers.md).
When you deviate from these supported paths, such as building from source or installing from an untrusted tap, Homebrew warns you loudly that the configuration is unsupported.

### Bottle provenance attestations

Checksums prove that the downloaded bytes match the reviewed metadata.
Bottle provenance attestations add a different check: who built those bytes and from what source.
Homebrew ships bottle attestation verification in `Library/Homebrew/attestation.rb`; when `HOMEBREW_VERIFY_ATTESTATIONS` is set, Homebrew uses GitHub's attestation tooling to verify `homebrew/core` bottle build provenance before installation.
Homebrew can also verify bottles from supported third-party GitHub taps against that tap's own GitHub Actions identity.
Homebrew CI also emits bottle attestations with `actions/attest`, binding bottle artifacts to the GitHub Actions identity and build context that produced them.
Third-party taps can do the same for their own bottles.
We hope to make attestation verification the default in future once it can be implemented in pure Ruby rather than depending on the `gh` tool.

These attestations are backed by Sigstore's transparency log, which is the one cross-check in this pipeline that is not hosted by GitHub.
An attacker who can upload a bottle and alter GitHub-hosted metadata still has to produce a matching, publicly logged provenance attestation for the expected Homebrew build identity.

### Layered infrastructure with cross-checks

Homebrew's pipeline is split across several components: the [`Homebrew/brew`](https://github.com/Homebrew/brew) client, which most users run from tagged stable releases rather than the latest commit; the [`Homebrew/homebrew-core`](https://github.com/Homebrew/homebrew-core) and [`Homebrew/homebrew-cask`](https://github.com/Homebrew/homebrew-cask) repositories of formulae and casks; the [`formulae.brew.sh`](https://formulae.brew.sh) JSON API, generated and served from GitHub Pages; and the `homebrew/core` bottles, hosted on GitHub Packages.

These are all hosted by GitHub rather than on wholly separate infrastructure, so they are not fully independent trust boundaries.
They do, however, cross-check one another.
For example, an exploited token granting GitHub Packages access could upload a malicious bottle, but that bottle would not match the `sha256` checksum recorded in the GitHub-hosted repository, and changing that checksum requires a pull request reviewed by a human maintainer.
The signed JSON API and bottle attestations add further cross-checks: API metadata must verify against Homebrew's JWS signing key, and bottle provenance must verify against the expected build identity and public transparency log.
An attacker therefore has to subvert more than one component at once to reach users.

Because GitHub underpins most of this, we enable every new GitHub security feature as soon as we can, including mandatory two-factor authentication, disallowing SMS as a second factor, required branch protections on all Homebrew repositories and immutable GitHub releases.
Dependabot updates are opened through pull requests with cooldowns across Homebrew repositories, so the package manager's own automation does not immediately ingest a freshly-published dependency release.
The checked-in [Dependabot configuration](https://github.com/Homebrew/brew/blob/HEAD/.github/dependabot.yml) is synced from the shared [`Homebrew/.github`](https://github.com/Homebrew/.github) repository, which keeps common repository policy files aligned across Homebrew repositories.
Homebrew also keeps the number of GitHub organisation owners minimal and limits high-privilege 1Password access to the people and teams documented in [Homebrew Governance](Homebrew-Governance.md) and the [New Maintainer Checklist](New-Maintainer-Checklist.md).
Privileged pull request events are used sparingly: the [pull request checker](https://github.com/Homebrew/brew/blob/HEAD/.github/workflows/check-prs.yml) is the only `pull_request_target` workflow in this repository, refuses to run after a checkout and only reads trusted base-branch files through the GitHub API.
Most workflows avoid `actions/checkout` unless they need a checkout; when it is used, it is pinned and normally sets `persist-credentials: false`.
The stale lead maintainer PR approval workflow can only approve non-fork, non-draft `Homebrew/brew` PRs that meet its review and CI requirements during a weekday approval window, and it refuses to approve changes to sensitive paths.

### Homebrew's own supply chain

Homebrew itself is Ruby code distributed from the `Homebrew/brew` repository.
Most users run tagged stable releases; developer mode can track the latest commit on `main`, but that is not the default user path.
Homebrew's runtime Ruby dependencies are vendored in-tree and pinned in `Library/Homebrew/Gemfile.lock`, rather than resolved live from RubyGems during normal `brew` execution.
Updates to those dependencies are reviewed like other Homebrew changes, with Dependabot cooldowns providing an additional delay for newly published gem releases.
This reduces the package manager's own dependency chain as an attack surface, a recurring weak point in ecosystems where package-manager plugins or runtime libraries are resolved dynamically at execution time.

### Static analysis and linting

Homebrew errs on the side of "all the lints", because mechanical review catches entire classes of supply-chain mistakes before human reviewers need to spot them manually.
For Ruby, `brew style` prefers enabling RuboCop's default cops where practical, then layers Homebrew-specific RuboCops from `Library/Homebrew/rubocops` on top for package-manager rules that generic Ruby tooling cannot know.
For shell and workflow code, CI runs ShellCheck, `actionlint` and `zizmor`; `zizmor` uploads SARIF security results for GitHub Actions workflows, and the shared `.github` `zizmor` policy keeps Homebrew action pinning policy consistent across repositories.
For types, `brew typecheck` uses Sorbet, and Homebrew pushes `# typed: strict` across all possible non-test Ruby files; the small number of bootstrap files that load before normal runtime support are covered with RBI type declarations and static checks where possible.
`brew lgtm` combines typechecking, changed-file style fixing and relevant tests so local and CI feedback use the same guardrails.
Mike McQuaid's [Ruby on guard rails](https://mikemcquaid.com/ruby-on-guard-rails/) describes the broader philosophy: automate the noisy, repeatable checks so reviewers can spend their attention on correctness, security and judgement.

### Secure and responsible AI usage

AI-assisted changes are treated as untrusted contributions, not as a way around Homebrew's review model.
Homebrew's [Responsible AI Usage](Responsible-AI-Usage.md) guide requires contributors to review, understand, test and disclose AI-assisted work before asking maintainers to review it.
Contributors using agents are encouraged to isolate them with sandboxed git worktrees, limited credentials and separate branches, as described in Mike McQuaid's [sandboxed agent worktrees](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/).
The same defences in this document still apply to AI-assisted work: small diffs, human review, `brew lgtm`, CI, tap trust and sandboxed package execution.
That keeps AI useful as automation while preserving the human accountability and layered checks that Homebrew relies on.

### No arbitrary code execution on install by default

Installing a bottle uses reviewed, prebuilt files, reducing the need to run upstream build scripts on your machine.
Homebrew uses sandboxing to limit package-supplied code where supported, but some installations require trusting vendor code with broader access (see below).

### Sandboxing

Homebrew uses sandboxing on macOS and Linux to limit what package processing, builds, supported installation steps and tests can access.
The aim is least privilege: give each operation only the filesystem, network and credential access it needs.
This reduces the risk that a malicious or faulty package can alter unrelated software, damage Homebrew or expose personal data.

Sandbox permissions are defined by Homebrew's reviewed code.
Sandboxing complements maintainer review, download verification and explicit trust decisions; it does not make arbitrary third-party code safe to run.
The separate trust requirements for taps and vendor-provided casks still apply.

Available protections depend on the operating system and configuration.
Some operations can continue with a warning when sandboxing is unavailable or Homebrew relies on an external sandbox.

### Environment filtering

Homebrew limits which environment settings reach package code, reducing accidental exposure of secrets and unexpected configuration.

### Casks have a different trust model

Formulae and casks share Homebrew's reviewed package metadata and signed JSON API, but they do not share the same artefact security model.
`homebrew/core` formulae are open source build recipes based on checksummed source.
Homebrew builds bottles for formulae in its own controlled, ephemeral CI and checksums the result, so users normally trust Homebrew's reviewed source-to-bottle pipeline rather than a binary supplied and signed by the upstream developer.
All formula installations run without `sudo`.

[Casks](Cask-Cookbook.md) instead install prebuilt applications and installers supplied directly by the upstream developer.
This is necessary for native macOS applications and proprietary software, but Homebrew usually cannot reproduce those binaries from source or compare them with an independently produced build.
A cask's `sha256` proves that the downloaded bytes match the package metadata, but it does not prove who produced those bytes or whether the program inside is trustworthy.
Some casks must use `sha256 :no_check` because their download URL changes contents in place, while self-updating applications can replace themselves outside Homebrew entirely.
Cask installation artefacts are treated as trusted vendor installation actions once a cask is accepted, so users must still trust the vendor.
Vendor installer scripts and macOS package installers run outside Homebrew's sandbox and may change files beyond Homebrew's directories.
Some cask installations run without `sudo`.
Others require elevated privileges, such as those that use macOS `.pkg` installers.

On macOS, code signing, notarisation and Gatekeeper provide independent checks that compensate for this weaker artefact model:

* A [Developer ID signature](https://developer.apple.com/developer-id/) ties the artefact to a certificate Apple issued to a registered developer and lets macOS detect changes made after it was signed.
* [Apple's notary service](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) automatically scans submitted software for known malicious content and code-signing problems, records the result and issues a ticket that Apple can later revoke.
* [Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) checks the developer identity, notarisation ticket and signature when quarantined software is first opened or installed.

Homebrew applies macOS quarantine attributes to Cask downloads so Gatekeeper performs these checks instead of Homebrew bypassing them.
Homebrew also audits apps, installers and other executable artefacts in official macOS casks that Gatekeeper can assess and requires them to pass on a default macOS configuration.
These controls are not a guarantee that an application is harmless: notarisation is an automated malware check, not a source review or App Store review.
They are nevertheless a meaningful additional trust layer outside the upstream download server and Homebrew's metadata, with an attributable developer, tamper detection and a revocation path if malicious software is discovered later.
For a `sha256 :no_check` cask, this can be the principal validation of changing download contents that is independent of the upstream server.

This requirement can make older casks ineligible even when users have run earlier versions without incident.
That history does not authenticate the next download, detect later tampering or provide a revocable identity for it.
Keeping such a cask would also require users to override the same macOS protection that Homebrew relies on for vendor-built artefacts.
Homebrew therefore [deprecates, disables and eventually removes](Deprecating-Disabling-and-Removing.md#when-to-deprecate-casks) casks that fail Gatekeeper checks rather than normalising a security bypass.
Removal does not mean Homebrew has determined that the software is malware; it means the upstream artefact no longer meets the security baseline for distribution through `homebrew/cask`.
The cask can become eligible again when upstream provides artefacts that pass the checks.

### Cooldowns on riskier ecosystems

For ecosystems with a track record of fast-moving supply-chain attacks, Homebrew applies a download cooldown: a freshly-published upstream version is not adopted immediately, giving the wider community time to detect and report a malicious release before Homebrew users are exposed.
Cooldowns have been added for:

* [Bundler](https://github.com/Homebrew/brew/pull/22555)
* [RubyGems livecheck](https://github.com/Homebrew/brew/pull/22253)
* [npm and pip defaults](https://github.com/Homebrew/brew/pull/21919)
* [PyPI resource resolution](https://github.com/Homebrew/brew/pull/21920)
* [npm and PyPI in `bump`](https://github.com/Homebrew/brew/pull/21888)

Homebrew applies these cooldowns narrowly, only to the language ecosystems that have actually suffered fast-moving supply-chain attacks, rather than as a blanket delay on every package.
A blanket cooldown would trade a small, speculative reduction in supply-chain risk for a real, across-the-board delay in shipping critical fixes: when a zero-day in something like OpenSSL is being exploited in the wild, Homebrew works to get the fix to users as fast as possible, and Homebrew's design means upgrading one package can require upgrading others.
Across Homebrew's history far more users have been protected by shipping zero-day fixes quickly than have been exposed to npm-style token-theft or crypto-mining attacks, so a global cooldown would be a net negative for most users' security.
The deeper reason Homebrew does not need a general cooldown is that, unlike language package managers, it already separates publishing from distribution: an upstream release does not reach users until it has passed human review, CI and checksum verification, which is the very review window that language-ecosystem cooldowns are trying to recreate.

Homebrew is also a rolling-release package manager, so there is a genuine balance to strike: delivering a coordinated zero-day fix immediately, as with the OpenSSL Heartbleed vulnerability, versus delaying updates to blunt supply-chain attacks.
Given our trust model, risk profile and the breadth of ecosystems we support, we prefer to apply cooldowns when we bump an upstream package rather than imposing a second Homebrew-specific cooldown on end users as they upgrade; doing both would be a "double cooldown" that delays security fixes twice over for little extra benefit.

### Prioritising security over backwards compatibility

When the two conflict, Homebrew prioritises security over backwards compatibility.
Homebrew's [deprecation](Deprecating-Disabling-and-Removing.md) policy and regular major and minor releases let us deprecate, then disable, then entirely remove a risky behaviour or default across successive releases, often within roughly six to nine months.
Being willing to break compatibility on that timescale is a large part of why Homebrew has been able to respond to new supply-chain threats faster than ecosystems that must preserve old behaviour indefinitely.

## Trust model comparison

| Property                            | Homebrew                                                        | npm / PyPI                               |
| ----------------------------------- | --------------------------------------------------------------- | ---------------------------------------- |
| Who can publish a change            | Homebrew maintainers, via pull request                          | Any package owner, directly              |
| Human review of each release        | Always                                                          | None                                     |
| Time from upstream release to users | Reviewed, plus a cooldown for riskier ecosystems                | Immediate                                |
| Download integrity                  | Pinned `sha256` in reviewed metadata                            | Trust the registry at install time       |
| What most users install             | Bottles built by Homebrew CI                                    | Publisher-uploaded artifacts             |
| Code execution on install           | Sandboxed installation steps where supported                    | `preinstall`/`postinstall` or `setup.py` |
| Build and install isolation         | Filesystem, network and credential restrictions where supported | None by default                          |
| Trust concentration                 | Vetted, 2FA-required maintainer team                            | Per-package owner credentials            |

## Looking ahead

This is not a solved problem and we do not claim Homebrew is immune.
Homebrew combines human review, sandboxing, restricted access to sensitive data and cooldowns for riskier ecosystems to mitigate these risks.
We will continue to monitor the supply-chain security landscape and take further steps as needed.

## Local trust model

Homebrew is designed for a single trusted owning account on macOS or Linux.
Homebrew provides no security guarantees when users with write permissions to the Homebrew prefix are considered untrusted.
This also applies when Homebrew is installed or upgraded through MDM.
See [Support Tiers](Support-Tiers.md#unsupported) for unsupported multi-user configurations.
