---
last_review_date: "2025-03-28"
---

# Support Tiers

Homebrew has 3 support tiers.
These set expectations for how well Homebrew will run on a given configuration.

## Tier 1

A Tier 1 supported configuration is one in which:

- you get the best experience using Homebrew
- we will aim to fix bugs affecting this platform
- we will not output warnings running on this platform
- we have CI coverage for testing and building bottles for this platform
- your support is best met through Homebrew's issue trackers

### macOS

For Tier 1 support Homebrew on macOS must be all of:

- running on official Apple hardware (e.g. not a "Hackintosh" or VM)
- running a version of macOS supported by Apple on that hardware (e.g. not using OpenCore Legacy Patcher)
- running a version of macOS with Homebrew CI coverage (i.e. the latest stable or prerelease version, two preceding versions)
- installed Homebrew in the default prefix (i.e. `/opt/homebrew` on Apple Silicon, `/usr/local` on Intel x86_64)
- running on a supported architecture (i.e. Apple Silicon or Intel x86_64)
- not building official packages from source

### Linux

For Tier 1 support Homebrew on Linux must be all of:

- running on Ubuntu or a Homebrew-provided Docker image
- have a system `glibc` >= 2.13
- if running Ubuntu, running an Ubuntu version in "standard support": <https://ubuntu.com/about/release-cycle>
- installed Homebrew in the default prefix (i.e. `/home/linuxbrew/.linuxbrew`)
- running on a supported architecture (i.e. Intel x86_64)

## Tier 2

A Tier 2 supported configuration is one in which any of:

- you get a subpar but potentially still usable experience using Homebrew
- we review PRs that fix bugs affecting this platform but will not aim to fix bugs
- we will output `brew doctor` warnings running on this platform
- we are missing some CI coverage for testing and building bottles for this platform
- we will close issues only affecting this platform
- your support is best met through Homebrew's Discussions

Tier 2 configurations include:

- macOS prereleases before we state they are Tier 1 (e.g. in March 2025, macOS 16, whatever it ends up being called)
- Linux versions where a system `glibc` < 2.13, so the Homebrew `glibc@*` formula is automatically installed
- using official packages that need to be built from source due to installing Homebrew outside the default prefix (i.e. `/opt/homebrew` on Apple Silicon, `/usr/local` on Apple Intel x86_64, `/home/linuxbrew/.linuxbrew` for Linux)
- running on a not-yet-supported architecture (i.e. Linux ARM64/AARCH64)

## Tier 3

A Tier 3 supported configuration is one in which:

- you get a poor but not completely broken experience using Homebrew
- we strongly recommend migrating to a Tier 1 or 2 configuration or a non-Homebrew tool
- we will not review PRs or aim to fix bugs only affecting this platform
- we may intentionally regress functionality on this platform if it e.g. improves things for other platforms
- we will output noisy warnings running on this platform
- we are lacking any CI coverage for testing or building bottles for this platform
- we will close without response issues only affecting this platform
- your support is best met through Homebrew's Discussions

Tier 3 configurations include:

- macOS versions for which we no longer provide CI coverage and Apple no longer provides most security updates for (e.g. as of March 2025, macOS Monterey/12 and older)
- building official packages from source when binary packages are available
- installing Homebrew outside the default prefix (i.e. `/opt/homebrew` on Apple Silicon, `/usr/local` on Apple Intel x86_64, `/home/linuxbrew/.linuxbrew` for Linux)

## Unsupported

An unsupported configuration is one in which:

- Homebrew will refuse to run at all without third-party patching.
- You must migrate to another tool (e.g. Tigerbrew, MacPorts, Linux system package managers etc.)

## Unsupported Software

Note that all packages installed from third-party taps outside of the Homebrew GitHub organisation are unsupported by default.

We may assist the maintainers/contributors/developers of such packages to fix bugs with the Homebrew formula/cask/tap system, but we are not responsible for resolving issues when using that software.

Bugs that only manifest when using third-party formulae/casks may be closed.
