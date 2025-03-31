---
last_review_date: "2025-03-28"
---

# Support Tiers

Homebrew has three support tiers.
These set expectations for how well Homebrew will run on a given configuration.

## Tier 1

A Tier 1 supported configuration is one in which:

- you're setup to get the best experience using Homebrew
- we will aim to fix reproducible bugs affecting this configuration
- we will not output warnings about running on this configuration
- we have CI coverage for automated testing and building bottles for this configuration
- your support is best met through Homebrew's issue trackers
- Homebrew may block merging a PR if it doesn't build properly on this configuration

### macOS

For Tier 1 support, Homebrew on macOS must be all of:

- running on official Apple hardware (e.g. not a "Hackintosh" or VM)
- running a version of macOS supported by Apple on that hardware (e.g. not using OpenCore Legacy Patcher)
- running a version of macOS with Homebrew CI coverage (i.e. the latest stable or prerelease version, two preceding versions)
- installed in the default prefix (i.e. `/opt/homebrew` on Apple Silicon, `/usr/local` on Intel x86_64)
- running on a supported architecture (i.e. Apple Silicon or Intel x86_64)
- not building official packages from source
- installed on your Mac's built-in hard-drive (i.e. not external/removable storage)
- you have `sudo` access on your system
- the Xcode Command Line Tools are installed and fully up-to-date

### Linux

For Tier 1 support, Homebrew on Linux must be all of:

- running on Ubuntu or a Homebrew-provided Docker image
- have a system `glibc` >= 2.35
- if running Ubuntu, running an Ubuntu version in "standard support": <https://ubuntu.com/about/release-cycle>
- installed in the default prefix (i.e. `/home/linuxbrew/.linuxbrew`)
- running on a supported architecture (i.e. Intel x86_64)
- not building official packages from source
- you have `sudo` access on your system

## Tier 2

A Tier 2 supported configuration is one in which any of:

- you get a subpar but potentially still usable experience using Homebrew
- we review PRs that fix bugs affecting this configuration but will not aim to fix bugs
- we will output `brew doctor` warnings running on this configuration
- we have partial CI coverage for testing and building bottles for this configuration so some bottles will not be available
- we will close issues only affecting this configuration
- your support is best met through Homebrew's Discussions

Tier 2 configurations include:

- macOS prereleases before we state they are Tier 1 (e.g. in March 2025, macOS 16, whatever it ends up being called)
- Linux versions where a system `glibc` < 2.35 (but still >= 2.13), so the Homebrew `glibc` formula is automatically installed
- using official packages that need to be built from source due to installing Homebrew outside the default prefix
  (i.e. `/opt/homebrew` on Apple Silicon, `/usr/local` on Apple Intel x86_64, `/home/linuxbrew/.linuxbrew` for Linux)
- running on a not-yet-supported architecture (i.e. Linux ARM64/AARCH64)

## Tier 3

A Tier 3 supported configuration is one in which:

- you get a poor but not completely broken experience using Homebrew
- we strongly recommend migrating to a Tier 1 or 2 configuration or a non-Homebrew tool
- we will only review PRs with a very high bar: any changes must be proven by the author to fix (not work around) an issue and not come with high maintainability costs (no patches)
- we will generally not aim to fix bugs ourselves affecting this configuration
- we may intentionally regress functionality on this configuration if it e.g. improves things for other configuration
- we will output noisy warnings running on this configuration
- we are lacking any CI coverage for testing or building bottles for this configuration so few bottles will be available
- we will close without response issues only affecting this configuration
- your support is best met through Homebrew's Discussions

Tier 3 configurations include:

- macOS versions for which we no longer provide CI coverage and Apple no longer provides most security updates for (e.g. as of March 2025, macOS Monterey/12 and older)
- building official packages from source when binary packages are available
- installing Homebrew outside the default prefix (i.e. `/opt/homebrew` on Apple Silicon, `/usr/local` on Apple Intel x86_64, `/home/linuxbrew/.linuxbrew` for Linux)
- installing formulae using `--HEAD`
- installing deprecated or disabled formulae

## Unsupported

An unsupported configuration is one in which:

- Homebrew will refuse to run at all without third-party patching
- You must migrate to another tool (e.g. Tigerbrew, MacPorts, Linux system package managers etc.)

Tier 3 configurations include:

- FreeBSD
- macOS 10.6
- Beowulf clusters
- Nokia 3210s
- CPUs built inside of Minecraft
- toasters

## Unsupported Software

Note that all packages installed from third-party taps outside of the Homebrew GitHub organisation are unsupported by default.

We may assist the maintainers/contributors/developers of such packages to fix bugs with the Homebrew formula/cask/tap system, but we are not responsible for resolving issues when using that software.

Bugs that only manifest when using third-party formulae/casks may be closed.
