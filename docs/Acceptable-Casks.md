---
last_review_date: "2026-08-25"
---

# Acceptable Casks

This page contains the cask-specific requirements for [`homebrew/cask`](https://github.com/Homebrew/homebrew-cask).
The [shared package acceptance policy](Package-Acceptance-Policy.md) also applies.

* Table of Contents
{:toc}

## Requirements for `homebrew/cask`

<a data-proofer-ignore name="stable-versions"></a>
<a data-proofer-ignore name="but-there-is-no-stable-version"></a>

### Default and alternative release channels

The unversioned cask normally tracks the upstream release channel recommended for most users.
That channel is not necessarily the newest available release.
Concurrent upstream channels may use distinct tokens such as `@latest`, `@beta` or `@nightly`.
Channel names are defined by upstream and do not imply a universal ordering or stability level.

A release line pinned to a particular version is eligible only while upstream actively maintains it.
Continued download availability or user demand does not make an end-of-life release eligible.
The [Cask Cookbook](Cask-Cookbook.md#casks-pinned-to-specific-versions) documents token conventions for versioned releases and alternative channels.

### Platform compatibility and macOS security protections

* A cask may support macOS, Linux or both when Homebrew supports its artifact types on those operating systems.
* A cask is not required to support both operating systems.
* A cask must work on every operating system and architecture it declares.
* A cask that supports macOS must work on the latest major version of macOS.
* On macOS, apps, installers and other executable artefacts that Gatekeeper can assess must pass Homebrew's [Gatekeeper checks](Homebrew-Security-and-Supply-Chain.md#casks-have-a-different-trust-model) and must not require System Integrity Protection or Gatekeeper to be disabled or bypassed.

Apple's [Rosetta 2 transition documentation](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment/) says general application support will remain available through macOS 27, with only a narrower legacy-games-focused subset beyond that.
Casks that require [`requires_rosetta`](Cask-Cookbook.md#caveats-mini-dsl) remain eligible while the latest major macOS release provides that general support.
Under Apple's announced timeline, new `requires_rosetta` casks will become ineligible when macOS 27 is the latest stable macOS version.
Existing `requires_rosetta` casks are expected to be deprecated while macOS 27 is current, then disabled or removed after macOS 28 becomes the latest stable macOS version.

### Regional and localised editions

Language and regional editions of the same application should normally be represented by one cask using the [`language` stanza](Cask-Cookbook.md#stanza-language), rather than by separate casks.

### Trials and optional paid features

* A time-limited trial is eligible only when the same download can be activated as the full version without being downloaded again.
* The trial cask is not eligible when the full version is available only through the Mac App Store.
* A free version that works indefinitely with optional paid features is eligible.
* An obsolete direct-download build is not eligible when the developer distributes the current version exclusively through the Mac App Store.

### Appropriate package type

Casks distribute applications and other pre-built files published by the upstream developer.
Open-source command-line-only software normally belongs in [`homebrew/core`](https://github.com/Homebrew/homebrew-core) as a formula built from source.
Open-source graphical software without a current compiled distribution also normally belongs in `homebrew/core`.
A rejection from `homebrew/core` does not by itself make the software eligible for `homebrew/cask`.
The [Adding Software to Homebrew](Adding-Software-to-Homebrew.md#choose-a-package-type) guide describes the distinction between formulae and casks.

### Verifiable upstream distribution

* A cask must use a download published by the developer or by a distribution source the developer publicly endorses.
* An unendorsed third-party build, a binary available only through a forum or similar posting or a download hidden behind account registration on a host unrelated to the homepage is not eligible.
* An installer package that requires certificate verification to be disabled is not eligible.

### Forks and apps with conflicting names

A fork packaged alongside the original software must use the vendor's name as a prefix in its filename and token.
This remains necessary when the original project is discontinued so users can distinguish its lineage.
A fork may replace the original cask when it meets the [shared fork criteria](Package-Acceptance-Policy.md#forks-that-replace-an-existing-project).
A cask-specific exception is also possible when clear evidence shows that the fork is so overwhelmingly adopted that users understand the original name to mean the fork.

For unrelated applications with the same name, the existing or more widely recognised application normally keeps the unprefixed token.
Evidence that this choice would mislead users may justify a different token.
A duplicate cask for the same software, release and channel is not eligible.

### Notability exceptions

* The [shared notability metrics](Package-Acceptance-Policy.md#notability) may not represent the notability of an established application when the repository is used only to host its binaries.
* A cask backed by an established maintainer or prolific contributor may also receive further consideration because it has a clearer maintenance path.
* A recently released application may receive further consideration when there is substantial, independently verifiable public interest and multiple requests for inclusion.

These circumstances permit further review but do not guarantee inclusion.

## Security and malware

Homebrew does not certify that every application distributed by a cask is safe.
Malware allegations are evaluated case by case because security products do produce false positives and potentially unwanted behaviour is not always unambiguous.
A rejection or removal decision requires evidence that identifies the exact downloaded file and version, provides its checksum and includes more than one source where possible.
A [VirusTotal](https://www.virustotal.com/) result can support a decision but is not sufficient without context.

Homebrew may remove a cask when evidence shows that the application is malicious or when the developer steers users towards a malicious variant.
Removal from `homebrew/cask` means that Homebrew no longer distributes or supports the cask.
