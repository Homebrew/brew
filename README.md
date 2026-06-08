# 🍺 Homebrew

[![Latest GitHub release](https://img.shields.io/github/release/Homebrew/brew.svg)](https://github.com/Homebrew/brew/releases)
[![BSD-2-Clause License](https://img.shields.io/github/license/Homebrew/brew)](https://github.com/Homebrew/brew/blob/HEAD/LICENSE.txt)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/homebrew?label=GitHub%20Sponsors)](https://github.com/sponsors/Homebrew)
[![Open Collective backers and sponsors](https://img.shields.io/opencollective/all/homebrew?label=Open%20Collective)](https://opencollective.com/homebrew)

See [Homebrew's homepage at `brew.sh`](https://brew.sh) for installation instructions, what homebrew does, packages, `brew bundle` and more.

<img src="https://brew.sh/assets/img/brew-install.gif" alt="Homebrew install demo" width="580" height="424">

## 💸 Donations

Homebrew is a non-profit project run entirely by volunteers, not employees.
We need your funds to pay for software, hardware and hosting around continuous integration and future improvements to the project.
Every donation will be spent on making Homebrew better for our users.

Please consider a regular donation through [GitHub Sponsors](https://github.com/sponsors/Homebrew), [Open Collective](https://opencollective.com/homebrew) or [Patreon](https://www.patreon.com/homebrew).
Homebrew is fiscally hosted by the [Open Source Collective](https://opencollective.com/opensource).

## 📚 Documentation

Read the Homebrew manual with [`man brew`](https://docs.brew.sh/Manpage).

Read [installation](https://docs.brew.sh/Installation),
[troubleshooting](https://docs.brew.sh/Troubleshooting),
[contribution](https://github.com/Homebrew/brew/blob/HEAD/docs/How-To-Open-a-Homebrew-Pull-Request.md)
including the [FAQ](https://docs.brew.sh/FAQ) on [`docs.brew.sh`](https://docs.brew.sh/).

Read the [Homebrew Blog](https://brew.sh/blog/) for release notes, project updates and announcements.

## 📦 Packages
Find [formulae](https://formulae.brew.sh/formula/), [casks](https://formulae.brew.sh/cask/), dependencies, versions and package metadata on [`formulae.brew.sh`](https://formulae.brew.sh).

View anonymised install, build and operating system usage data at [`formulae.brew.sh/analytics`](https://formulae.brew.sh/analytics/).
Read how Homebrew uses [Anonymous Analytics](https://docs.brew.sh/Analytics).

## 🔧 Get Help

First, please run `brew update` and run (and **read**) `brew doctor`.

Second, read the [Troubleshooting Checklist](https://docs.brew.sh/Troubleshooting).

**If you don't read these it will take us far longer to help you with your problem.**

After this, if you still need help, please ask in
[Homebrew/discussions](https://github.com/orgs/Homebrew/discussions)
or follow (and **read**) the
[Homebrew/brew new issue chooser](https://github.com/Homebrew/brew/issues/new/choose).

## 💬 Social

Follow Homebrew on [Mastodon](https://fosstodon.org/@homebrew),
[Bluesky](https://bsky.app/profile/brew.sh),
[𝕏 (Twitter)](https://x.com/MacHomebrew) or subscribe to the
[newsletter](https://buttondown.email/homebrew).

## 🤝 Contributing

We'd love you to join us and >10,000 others by contributing to Homebrew!

First, please read our [Contribution Guide](CONTRIBUTING.md) and [Code of Conduct](https://github.com/Homebrew/.github/blob/HEAD/CODE_OF_CONDUCT.md#code-of-conduct).

A good starting point for contributing is:

- `brew tap --force homebrew/core` or `brew tap --force homebrew/cask` (depending on whether you'd rather work on formulae or casks)
- perform a strict audit on a package you use e.g. `brew audit --strict ffempg` for FFmpeg
- if no warnings, run `brew audit --strict` to run on all packages and pick one to fix
- read through the warnings and fix them until `brew audit --strict <package>` shows no results
- [submit a pull request](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request) with your fixes

Alternatively, for something more substantial, check out one of the open issues in
[Homebrew/brew](https://github.com/homebrew/brew/issues),
[Homebrew/homebrew-core](https://github.com/homebrew/homebrew-core/issues) or
[Homebrew/homebrew-cask](https://github.com/homebrew/homebrew-cask/issues).

If you've had inspiration for a new feature or bug fix: we don't need you to open an issue first, just [open a pull request](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request) with your implementation and we'll review it.

Good luck!

## 🔐 Security

Please see [our security policy](https://github.com/Homebrew/.github/blob/HEAD/SECURITY.md) for how to report security issues and what is in scope.

## 👥 Who We Are

Homebrew's [Project Leader](https://docs.brew.sh/Homebrew-Governance#project-leader) is [Mike McQuaid](https://github.com/MikeMcQuaid).

Homebrew's [Lead Maintainers](https://docs.brew.sh/Homebrew-Governance#lead-maintainer) are [Bevan Kay](https://github.com/bevanjkay), [Bo Anderson](https://github.com/Bo98), [Branch Vincent](https://github.com/branchv), [Carlo Cabrera](https://github.com/carlocab), [Dustin Rodrigues](https://github.com/dtrodrigues), [FX Coudert](https://github.com/fxcoudert), [Issy Long](https://github.com/issyl0), [Justin Krehel](https://github.com/krehel), [Michael Cho](https://github.com/cho-m), [Michka Popoff](https://github.com/iMichka), [Mike McQuaid](https://github.com/MikeMcQuaid), [Nanda H Krishna](https://github.com/nandahkrishna), [Patrick Linnane](https://github.com/p-linnane), [Rui Chen](https://github.com/chenrui333), [Ruoyu Zhong](https://github.com/ZhongRuoyu), [Sam Ford](https://github.com/samford), [Sean Molenaar](https://github.com/SMillerDev) and [Thierry Moisan](https://github.com/Moisan).

Homebrew's other Maintainers are [Anton Melnikov](https://github.com/botantony), [Caleb Xu](https://github.com/alebcay), [Daeho Ro](https://github.com/daeho-ro), [Douglas Eichelberger](https://github.com/dduugg), [Eric Knibbe](https://github.com/EricFromCanada), [Klaus Hipp](https://github.com/khipp), [Markus Reiter](https://github.com/reitermarkus), [Rylan Polster](https://github.com/Rylan12), [Štefan Baebler](https://github.com/stefanb) and [William Woodruff](https://github.com/woodruffw).

Homebrew was originally created by [Max Howell](https://github.com/mxcl).

## 📜 License

Code is under the [BSD 2-clause "Simplified" License](LICENSE.txt).
Documentation is under the [Creative Commons Attribution license](https://creativecommons.org/licenses/by/4.0/).

## 💛 Sponsors

Our macOS continuous integration infrastructure is hosted by [MacStadium's Orka](https://www.macstadium.com/customers/homebrew).

[![Powered by MacStadium](https://cloud.githubusercontent.com/assets/125011/22776032/097557ac-eea6-11e6-8ba8-eff22dfd58f1.png)](https://www.macstadium.com)

Secure password storage and syncing is provided by [1Password for Teams](https://1password.com/teams/).

[<img src="https://i.1password.com/akb/featured/1password-icon.svg" alt="1Password" height="64">](https://1password.com)

<https://brew.sh>'s DNS is [resolving with DNSimple](https://dnsimple.com/resolving/homebrew).

[![DNSimple](https://cdn.dnsimple.com/assets/resolving-with-us/logo-light.png)](https://dnsimple.com/resolving/homebrew#gh-light-mode-only)
[![DNSimple](https://cdn.dnsimple.com/assets/resolving-with-us/logo-dark.png)](https://dnsimple.com/resolving/homebrew#gh-dark-mode-only)

Homebrew is generously supported by [Joshua Baer](https://github.com/joshuabaer), [Randy Reddig](https://github.com/ydnar), [Codecademy](https://github.com/Codecademy), [b.well](https://github.com/icanbwell), [Workbrew](https://github.com/Workbrew), [GitHub](https://github.com/github), [Custom Ink](https://github.com/customink), [SAP](https://github.com/SAP), [ZachryWilsn](https://github.com/ZachryWilsn), [mikadelbert](https://github.com/mikadelbert) and many other users and organisations via [GitHub Sponsors](https://github.com/sponsors/Homebrew).

[![GitHub](https://github.com/github.png?size=64)](https://github.com/github)
