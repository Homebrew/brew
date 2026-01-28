---
last_review_date: "2025-11-10"
---

# Support Tiers

Homebrew defines three support tiers to help users understand how well Homebrew is expected to work on different systems.

These tiers describe the level of compatibility, automation coverage, and community support that the project actively maintains. They also set expectations for how we handle issues, pull requests, and regressions.

## Tier 1

A Tier 1 configuration is considered fully supported. These configurations receive the highest level of CI coverage and are prioritized during issue review and formula development.

Users can expect:

- the most reliable experience using Homebrew
- reproducible bugs to be investigated and, where possible, fixed by Homebrew maintainers
- no warning output related to system configuration
- full CI coverage for testing and bottle builds
- support through Homebrew’s GitHub issue trackers
- pull requests to be blocked if they fail on Tier 1 systems

### macOS

To qualify as Tier 1, a macOS configuration must meet all of the following:

- On official Apple hardware (not a Hackintosh or virtual machine)
- Running the latest patch release of a macOS version supported by Apple for that hardware and included in Homebrew’s CI coverage (typically the latest stable or prerelease version and the two preceding versions)
- Installed in the default prefix:
  - `/opt/homebrew` on Apple Silicon
  - `/usr/local` on Intel x86_64
- Using a supported architecture (Apple Silicon or Intel x86_64)
- Not building official packages from source (i.e. using bottles)
- Installed on the Mac’s internal storage (not external or removable drives)
- Running with `sudo` access available
- Xcode Command Line Tools installed and up to date

### Linux

To qualify as Tier 1, a Linux configuration must meet all of the following:

- Running on:
  - Ubuntu within its [standard support window](https://ubuntu.com/about/release-cycle) or
  - a Homebrew-provided Docker image
- Using a system `glibc` version ≥ 2.35
- Using a Linux kernel version ≥ 3.2
- Installed in the default prefix: `/home/linuxbrew/.linuxbrew`
- Using a supported architecture (ARM64/AArch64 or Intel x86_64 with SSSE3 support)
- Not building official packages from source (i.e. using bottles)
- Running with `sudo` access available

## Tier 2

A Tier 2 configuration is not fully supported. These configurations are outside the scope of complete CI coverage and may not consistently function as expected.

The following conditions typically apply:

- Homebrew may be usable but with reduced reliability or performance
- Pull requests that fix issues specific to these configurations may be considered, but maintainers do not commit to resolving related bugs
- `brew doctor` will output warnings related to configuration
- CI coverage may be incomplete; bottles may be unavailable or fail to install
- Issues that only affect these configurations may be closed without investigation
- Support is generally limited to community responses on Homebrew’s Discussions

Tier 2 configurations include:

- macOS prerelease versions before they are promoted to Tier 1
- Linux systems with `glibc` versions between 2.13 and 2.34 (Homebrew’s own `glibc` formula will be installed automatically)
- Homebrew installed outside the default prefix, requiring source builds for official packages (i.e. installing outside `/opt/homebrew`, `/usr/local`, or `/home/linuxbrew/.linuxbrew`)
- Architectures not yet officially supported by Homebrew
- Macs using OpenCore Legacy Patcher with a Westmere or newer Intel CPU

## Tier 3

A Tier 3 configuration is not supported. These configurations fall far outside Homebrew’s testing infrastructure and may fail to function reliably, even if basic installation is possible.

The following conditions typically apply:

- Homebrew may work, but with a poor and unstable experience
- Migration to a Tier 1 or 2 configuration, or to a non-Homebrew tool, is strongly recommended
- Pull requests must meet a very high bar: they must resolve an issue (not merely work around it) and must not introduce high ongoing maintenance cost (e.g. patches must already be merged upstream)
- Homebrew maintainers do not commit to fixing bugs affecting these systems
- Functionality may regress intentionally if it benefits supported configurations
- Loud configuration warnings will be printed at runtime
- CI coverage is unavailable; bottles will rarely be built or published
- Issues affecting only these configurations may be closed without response
- Support is limited to community replies via Homebrew’s Discussions

Tier 3 configurations include:

- macOS versions no longer covered by CI and no longer receiving regular Apple security updates
- Systems that build official packages from source despite available bottles
- Homebrew installed outside the default prefix (e.g. `/opt/homebrew`, `/usr/local`, or `/home/linuxbrew/.linuxbrew` used on mismatched architectures)
- Installing formulae using `--HEAD`
- Installing deprecated or disabled formulae
- Macs using OpenCore Legacy Patcher with an Intel CPU older than Westmere

## Unsupported

An unsupported configuration is one in which:

- Homebrew will not run without third-party patches or modifications
- Migration to another tool is required (e.g. [MacPorts](https://www.macports.org), [Tigerbrew](https://github.com/mistydemeo/tigerbrew), or a native Linux package manager)

Unsupported configurations include:

- FreeBSD
- macOS Mojave 10.14 and earlier
- Beowulf clusters
- Nokia 3210s
- CPUs built inside of Minecraft
- Toasters

## Unsupported Software

Packages installed from third-party taps outside the Homebrew GitHub organization are unsupported by default.

While Homebrew may assist third-party maintainers in resolving issues related to the formula, cask, or tap system itself, it does not provide support for the behavior or operation of third-party software.

Bugs that occur only when using third-party formulae or casks may be closed without investigation.

## Future macOS Support

Apple has announced that macOS Tahoe 26 will be the final version of macOS to support Intel x86_64 hardware. In alignment with this change, Homebrew plans to remove support for macOS on Intel in a future release after that point.

The following timeline outlines expected Tier classifications based on Apple’s release cycle and Homebrew’s CI coverage.

- As of November 2025:

  Apple Silicon:
  - Tier 1: macOS Tahoe 26, Sequoia 15, Sonoma 14
  - Tier 3: macOS Big Sur 11 through Ventura 13

  Intel x86_64:
  - Tier 1: macOS Tahoe 26, Sequoia 15, Sonoma 14
  - Tier 3: macOS Catalina 10.15 through Ventura 13
  - Unsupported: macOS Mojave 10.14 and earlier

- Expected in or after September 2026:

  Apple Silicon:
  - Tier 1: macOS 27, Tahoe 26, Sequoia 15
  - Tier 3: macOS Big Sur 11 through Sonoma 14

  Intel x86_64:
  - Tier 3: macOS Big Sur 11 through Tahoe 26
  - Unsupported: macOS Catalina 10.15 and earlier

- Expected in or after September 2027:

  Apple Silicon:
  - Tier 1: macOS 28, 27, Tahoe 26
  - Tier 3: macOS Monterey 12 through Sequoia 15
  - Unsupported: macOS Big Sur 11

  Intel x86_64:
  - Unsupported: all macOS versions
