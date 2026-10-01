---
last_review_date: "2026-04-25"
---

# Working with Homebrew as an Upstream Project

If you maintain software packaged by Homebrew, thank you. The points below should help set expectations.

## How Homebrew works differently

- Formulae and casks in Homebrew's official taps, `homebrew/core` and `homebrew/cask`, are maintained by a shared pool of volunteer contributors and maintainers.
- The person opening an issue or pull request may be the first person who noticed a problem rather than someone with long-term context for that package.
- Homebrew prefers to package popular and widely used software in `homebrew/core` or `homebrew/cask` when it meets our requirements, even if upstream also ships a tap.
- Technical discussions should stay on GitHub where they can be linked later.
- Contentious decisions may also be discussed by maintainers in Slack or in person at our annual general meeting (AGM), but any decision made there should be summarised back on the relevant GitHub issue or pull request.

## If you need to discuss packaging

If a build failure report turns into a wider packaging or project relationship discussion:

- Open or continue a GitHub issue in the relevant repository.
- Explain the broader context: release policy, supported platforms, patch policy, packaging constraints or why Homebrew's current approach is causing problems.
- Use pull requests for targeted fixes.
- Use issues or discussions when the question is whether Homebrew should package the software differently.

## What to expect

- Homebrew's primary responsibility is to provide a good experience for its users. When we believe Homebrew users' and upstreams' desires are not aligned, we will prioritise Homebrew users of the upstream software.
- We may keep packaging software in Homebrew even if upstream would prefer users to install from an upstream tap instead. See [How to Create and Maintain a Tap](How-to-Create-and-Maintain-a-Tap.md#upstream-taps).
- Continued installs plus a lack of user reports that the software is completely broken to the point of uselessness will generally outweigh upstream claims that it is.
- We will not usually deprecate, disable or remove software only because upstream asks us to. Technical breakage, policy violations or broader project needs carry more weight. See [Acceptable Formulae](Acceptable-Formulae.md) and [Deprecating, Disabling and Removing](Deprecating-Disabling-and-Removing.md).
- Homebrew contributors and maintainers are usually better placed to decide how software should be packaged for Homebrew's users and infrastructure.
- If you release software under an open-source licence, Homebrew may package and redistribute it within the terms of that licence. If you need tighter control, proprietary licensing or other restrictions fit that goal better.
- On contentious packaging decisions, the weight of input generally decreases in this order: Project Leader, Lead Maintainers, Maintainers, contributors, upstreams, Homebrew users.
- We do want to work with upstream when possible, particularly on release tagging, stable download URLs, checksums, supported platforms and patches that can be sent upstream.
- We appreciate upstreams that cooperate constructively. Upstreams that make rude or abusive public claims about Homebrew or its maintainers should expect us to be less receptive to requests or demands.

## Escalation

If a packaging or communication discussion needs escalation:

- Ask [@MikeMcQuaid](https://github.com/MikeMcQuaid), Homebrew's current [Project Leader](Homebrew-Governance.md#project-leader), on the relevant issue or pull request.
- Use this for unresolved packaging or communication issues, not as a replacement for the normal review process.

## Further reading

If you want more detail on common upstream questions:

- See [Homebrew Governance](Homebrew-Governance.md), [Maintainer Guidelines](Maintainer-Guidelines.md) and [Creating a Homebrew Issue](Creating-a-Homebrew-Issue.md) for project structure, contributor and maintainer roles and how to raise or follow packaging discussions.
- See [Updating Software in Homebrew](Updating-Software-in-Homebrew.md), [Adding Software to Homebrew](Adding-Software-to-Homebrew.md) and [Versions](Versions.md) for update workflows, adding software and how Homebrew handles alternate versions.
- See [Analytics](Analytics.md) and [formulae.brew.sh](https://formulae.brew.sh/analytics/) for public install statistics and usage data.
- See [Deprecating, Disabling and Removing](Deprecating-Disabling-and-Removing.md) and [How to Create and Maintain a Tap](How-to-Create-and-Maintain-a-Tap.md) for removal policy, support boundaries and upstream taps.
