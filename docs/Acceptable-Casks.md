---
last_review_date: "1970-01-01"
---

# Acceptable Casks

Some casks should not go in [homebrew/cask](https://github.com/Homebrew/homebrew-cask). But there are additional [Interesting Taps and Forks](Interesting-Taps-and-Forks.md) and anyone can [start their own](How-to-Create-and-Maintain-a-Tap.md)!

* Table of Contents
{:toc}

## Finding a Home For Your Cask

We maintain separate taps for different types of binaries. Our nomenclature is:

* **Stable**: The latest version provided by the developer defined by them as such.
* **Beta, Development, Unstable**: Subsequent versions to **stable**, yet incomplete and under development, aiming to eventually become the new **stable**. Also includes alternate versions specifically targeted at developers.
* **Nightly**: Constantly up-to-date versions of the current development state.
* **Legacy**: Any **stable** version that is not the most recent.
* **Regional, Localized**: Any version that isn’t the US English one, when that exists.
* **Trial**: Time-limited version that stops working entirely after it expires, requiring payment to lift the limitation.
* **Freemium**: Gratis version that works indefinitely but with limitations that can be removed by paying.
* **Fork**: An alternate version of an existing project, with a based-on but modified source and binary.
* **Unofficial**: An *allegedly* unmodified compiled binary, by a third-party, of a binary that has no existing build by the owner of the source code.
* **Vendorless**: A binary distributed via means other than an official website, like a forum posting.
* **Walled**: When the download URL is both behind a login/registration form and from a host that differs from the homepage.
* **Font**: Data file containing a set of glyphs, characters, or symbols, that changes typed text.

### Stable versions

Stable versions live in the main repository at [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask). They should run on the latest major version of macOS.

### Beta, Unstable, Development, Nightly, or Legacy

These versions also live in the main repository at [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask). The filename and token should include `@beta`, `@nightly`, etc. to distinguish them from stable versions.

### Regional and Localized

When an app exists in more than one language or has different regional editions, [the `language` stanza should be used to switch between languages or regions](https://docs.brew.sh/Cask-Cookbook#stanza-language).

### Trial and Freemium versions

Before submitting a trial, make sure it can be made into a full working version without needing to be redownloaded. If an app provides a trial but the only way to buy the full version is via the Mac App Store, it does not belong in any of the official repositories. Freemium versions are fine.

### Forks and apps with conflicting names

Forks must have the vendor’s name as a prefix on the cask’s filename and token. If the original software is discontinued, forks still need to follow this rule so as to not be surprising to the user. There are two exceptions which allow the fork to replace the main cask:

1. The original discontinued software recommends that fork.
2. The fork is so overwhelmingly popular that it surpasses the original and is now the de facto project when people think of the name.

For unrelated apps that share a name, the most popular one (usually the one already present) stays unprefixed. Since this can be subjective, if you disagree with a decision, open an issue and make your case to the maintainers.

### Unofficial, Vendorless, and Walled builds

We do not accept these casks since they involve a higher-than-normal security risk.

## Apps that bundle malware

Unfortunately, in the world of software there are bad actors that bundle malware with their apps. Even so, Homebrew Cask has long decided it will not be an active gatekeeper ([macOS already has one](https://support.apple.com/en-us/HT202491)) and [users are expected to know about the software they are installing](#homebrew-cask-is-not-a-discoverability-service). This means we will not always remove casks that link to these apps, in part because there is no clear line between useful app, potentially unwanted program, and the different shades of malware—what is useful to one user may be seen as malicious by another.

But we’d still like for users to enjoy some kind of protection while minimising occurrences of legitimate developers being branded as malware carriers. To do so, we evaluate casks on a case-by-case basis and any user is free to bring a potential malware case to our attention. However, it is important to never forget the last line of defence is *always* the user.

If an app that bundles malware was not signed with an Apple Developer ID and you purposefully disabled or bypassed Gatekeeper, no action will be taken on our part. When you disable security features, you do so at your own risk. If, however, an app that bundles malware is signed, Apple can revoke its permissions and it will no longer run on the computers of users that keep security features on—we all benefit, Homebrew Cask users or not. To report a signed app that bundles malware, use [Apple’s Feedback Assistant](https://feedbackassistant.apple.com).

We are also open to removing casks where we feel there is enough evidence that the app is malicious. To suggest a cask for removal, submit a pull request to delete it along with your reasoning. Typically, this will mean presenting a [VirusTotal](https://www.virustotal.com) scan of the app showing it is malicious, ideally with some other reporting indicating it’s not a false positive.

Likewise, software which provides both “clean” and malware-infested versions might be removed from the repository; even if we could have access to the *good* version—if its developers push for users to install the *bad* version. We do so because in these cases there’s a higher than normal risk that both versions are (or will soon become) compromised in some manner.

If a cask you depend on was removed due to these rules, fear not. Removal of a cask from the official repositories means we won’t support it, but you can do so by [hosting your own tap](How-to-Create-and-Maintain-a-Tap.md).

## Exceptions to the notability threshold

Casks which do not reach a minimum notability threshold (see [Rejected Casks](#rejected-casks)) aren’t accepted in the main repositories because the increased maintenance burden doesn’t justify the poor usage numbers they will likely get. This notability check is performed automatically by the audit commands we provide, but its decisions aren’t set in stone. A cask which fails the notability check can be added if it is:

1. A popular app that has its own website but the developers use GitHub for hosting the binaries. That repository won’t be notable but the app may be.
2. Submitted by a maintainer or prolific contributor. A big part of the reasoning for the notability rule is unpopular software garners less attention and the cask gets abandoned, outdated, and broken. Someone with a proven investment in Homebrew Cask is less likely to let that happen for software they depend on.
3. A piece of software that was recently released to great fanfare—everyone is talking about it on Twitter and Hacker News and we’ve even gotten multiple premature submissions for it. That’d be a clear case of an app that will reach the threshold in no time so that’s a PR we won’t close immediately (but may wait to merge).

Note that none of these exceptions is a guarantee for inclusion, but examples of situations where we may take a second look.

## Not a fork (usually)

We will not add new casks using forks unless at least one of the following is true:

* the fork has been designated the official successor in the original source repository (e.g. in the README) or in a publicly verifiable way by the original author (e.g. in an issue or pull request comment)
* the fork has been used as the replacement by at least two other major distributions (e.g. Debian, Fedora, Arch, Gentoo, not smaller Linux distributions that are not widely used)

The fork should still meet all the other acceptable casks requirements (including those of e.g. popularity and self-submission).

An alternative to the fork replacing the original cask is a new cask. For example, if `MikeMcQuaid` forked `google-chrome` and it was very popular: a `mikemcquaid-google-chrome` cask might make sense.

## Homebrew Cask is not a discoverability service

From the inception of Homebrew Cask, various requests have fallen under the umbrella of this reply. Though a somewhat popular request, after careful consideration on multiple occasions we’ve always come back to the same conclusion: we’re not a discoverability service and our users are expected to have reasonable knowledge about the apps they’re installing through us before doing so. For example, [grouping casks by categories](https://github.com/Homebrew/homebrew-cask/issues/5425) is not within the scope of the project.

Amongst other things, the logistics of such requests are unsustainable for Homebrew Cask. Before making a request of this nature, you must read through previous related issues, as well as any other issues they link to, to get a full understanding of why that is the case, and why “but project *x* does *y*” arguments aren’t applicable, and how not every package manager is the same.

You should also be able to present clear actionable fixes to those concerns. Simply asking for it without solutions will get your issue closed.

However, there is a difference between discoverability (finding new apps you didn’t know about) and searchability (identifying the app you know about and want to install). While the former is unlikely to ever become part of our goals, the latter is indeed important to us, and we continue to work on it.

## Rejected Casks

Before submitting a cask to any of our repositories, you must read our [documentation on acceptable casks](#finding-a-home-for-your-cask) and perform a (at least quick) search to see if there were any previous attempts to introduce it.

Common reasons to reject a cask entirely:

* App fails with GateKeeper enabled on Homebrew supported macOS versions and platforms (e.g. unsigned apps will not launch on Apple Silicon Macs).
* App is too obscure. Examples:
  * An app from a code repository that is not notable enough (under 30 forks, 30 watchers, 75 stars).
  * [Electronic Identification (eID) software](https://github.com/Homebrew/homebrew-cask/issues/59021).
* App requires [SIP to be disabled](https://github.com/Homebrew/homebrew-cask/pull/41890) to be installed and/or used.
* App installer is a `pkg` that requires [`allow_untrusted: true`](https://docs.brew.sh/Cask-Cookbook#pkg-allow_untrusted).
* App is a trial version, and the only way to acquire the full version is through the Mac App Store.
  * Similarly (and trickier to spot), the app has moved to the Mac App Store but still provides old versions via direct download. We reject these in all official repositories so users don’t get stuck using an old version, wrongly thinking they’re using the most up-to-date one (which, amongst other things, might be a security risk).
* App is unmaintained, i.e. no releases in the last year, or [explicitly discontinued](https://github.com/Homebrew/homebrew-cask/pull/22699).
* App has no information on its homepage (example: a GitHub repository without a README).
* Cask has no public presence so `brew install` would be the only way to install the software, meaning users can’t easily verify its authenticity.
  * Or if the Cask has a download URL that is both behind a login/registration form and from a host that differs from the homepage.
* Cask is unreasonably difficult to maintain. Examples have included [Audacity](https://github.com/Homebrew/homebrew-cask/pull/27517) and [older Java development casks](https://github.com/Homebrew/homebrew-cask/issues/57387).
* Cask has been rejected before due to an issue we cannot fix, and the new submission doesn’t fix that. An example would be the [first submission of `soapui`](https://github.com/Homebrew/homebrew-cask/pull/4939), whose installation problems were not fixed in the two [subsequent](https://github.com/Homebrew/homebrew-cask/pull/9969) [submissions](https://github.com/Homebrew/homebrew-cask/pull/10606).
* Cask is a duplicate. These submissions mostly occur when the [token reference](https://docs.brew.sh/Cask-Cookbook#token-reference) was not followed.
* The author has [specifically asked us not to include it](https://github.com/Homebrew/homebrew-cask/pull/5342).
* App is both open-source and CLI-only (i.e. it only uses the `binary` artifact). In that case, and [in the spirit of deduplication](https://github.com/Homebrew/homebrew-cask/issues/15603), submit it first to [homebrew/core](https://github.com/Homebrew/homebrew-core) as a formula that builds from source. If it is rejected, you may then try again as a cask (link to the issue from your pull request so we can see the discussion and reasoning for rejection).
* App is open-source and has a GUI but no compiled versions (or only old ones) are provided. It’s better to have them in [homebrew/core](https://github.com/Homebrew/homebrew-core) so users don’t get perpetually outdated versions. See [`gedit`](https://github.com/Homebrew/homebrew-cask/pull/23360) for example.
* We have strong reasons to believe including the cask can put the whole project at risk. Happened only once so far, [with Popcorn Time](https://github.com/Homebrew/homebrew-cask/pull/3954).

Common reasons to reject a cask from the main `homebrew/cask` repository:

* Cask was submitted to the wrong repository. When drafting a cask, consult [Finding a Home For Your Cask](#finding-a-home-for-your-cask) to see where it belongs.

### No cask is guaranteed to be accepted

Follow the guidelines above and your submission has a great chance of being accepted. But remember that documentation tends to lag behind current decision-making and we can’t predict every case. Maintainers may override these rules when experience tells us it will lead to a better overall Homebrew.
