# New Maintainer Checklist

**Existing maintainers and project leadership uses this guide to invite and onboard new maintainers and project leaders.**
**General Homebrew users might find it interesting but there's nothing here _users_ should have to know.**

- [Homebrew Maintainers](#maintainers)
- [Project Leadership Committee](#plc)
- [Technical Steering Committee](#tsc)
- [Owners](#owners)
- [General Members](#members)

## Maintainers

There's someone who has been making consistently high-quality contributions to Homebrew and shown themselves able to make slightly more advanced contributions than just e.g. formula updates? Let's invite them to be a maintainer!

First, send them the invitation email:

```markdown
The Homebrew team and I really appreciate your help on issues, pull requests and
your contributions to Homebrew.

We would like to invite you to have commit access and be a Homebrew maintainer.
If you agree to be a maintainer, you should spend a significant proportion of
the time you are working on Homebrew applying and self-merging widely used
changes (e.g. version updates), triaging, fixing and debugging user-reported
issues, or reviewing user pull requests. You should also be making contributions
to Homebrew at least once per quarter.

You should watch or regularly check Homebrew/brew and/or Homebrew/homebrew-core
and/or Homebrew/homebrew-cask. Let us know which so we can grant you commit
access appropriately.

If you're no longer able to perform all of these tasks, please continue to
contribute to Homebrew, but we will ask you to step down as a maintainer.

A few requests:

- Please make pull requests for any changes in the Homebrew repositories (instead
  of committing directly) and don't merge them unless you get at least one approval
  and passing tests.
- Please review the Maintainer Guidelines at https://docs.brew.sh/Maintainer-Guidelines
- Please review the team-specific guides for whichever teams you will be a part of.
  Here are links to these guides:
    - Homebrew/brew: https://docs.brew.sh/Homebrew-brew-Maintainer-Guide
    - Homebrew/homebrew-core: https://docs.brew.sh/Homebrew-homebrew-core-Maintainer-Guide
    - Homebrew/homebrew-cask: https://docs.brew.sh/Homebrew-homebrew-cask-Maintainer-Guide
- Continue to create branches on your fork rather than in the main repository.
  Note GitHub's UI will create edits and reverts on the main repository if you
  make edits or click "Revert" on the Homebrew/brew repository rather than your
  own fork.
- If still in doubt please ask for help and we'll help you out.
- Please read:
    - https://docs.brew.sh/Maintainer-Guidelines
    - the team-specific guides linked above and in the maintainer guidelines
    - anything else you haven't read on https://docs.brew.sh

How does that sound?

Thanks for all your work so far!
```

If they accept, follow a few steps to get them set up:

- Invite them to the [**@Homebrew/maintainers** team](https://github.com/orgs/Homebrew/teams/maintainers) (or any relevant [subteams](https://github.com/orgs/Homebrew/teams/maintainers/teams)) to give them write access to relevant repositories (but don't make them owners). They will need to enable [GitHub's Two Factor Authentication](https://help.github.com/articles/about-two-factor-authentication/).
- Invite them as a full member to the [`machomebrew` private Slack](https://machomebrew.slack.com/admin/invites) (and ensure they've read the [communication guidelines](Maintainer-Guidelines.md#communication)) and ask them to use their real name there (rather than a pseudonym they may use on e.g. GitHub).
- Ask them to disable SMS as a 2FA device or fallback on their GitHub account in favour of using one of the other authentication methods.
- Ask them to (regularly) review remove any unneeded [GitHub personal access tokens](https://github.com/settings/tokens).
- Start the process to [add them as Homebrew members](#members), for formal voting rights and the ability to hold office for Homebrew.

If there are problems, ask them to step down as a maintainer.

When they cease to be a maintainer for any reason, revoke their access to all of the above.

In the interests of loosely verifying maintainer identity and building camaraderie, if you find yourself in the same town (e.g living, visiting or at a conference) as another Homebrew maintainer you should make the effort to meet up. If you do so, you can [expense your meal](https://docs.opencollective.com/help/expenses-and-getting-paid/submitting-expenses) (within [Homebrew's reimbursable expense policies](https://opencollective.com/homebrew/expenses)). This is a more relaxed version of similar policies used by other projects, e.g. the Debian system to meet in person to sign keys with legal ID verification.

Now sit back, relax and let the new maintainers handle more of our contributions.

## PLC

If a maintainer or member is elected to the Homebrew's [Project Leadership Committee](https://docs.brew.sh/Homebrew-Governance#4-project-leadership-committee):

- Invite them to the [**@Homebrew/plc** team](https://github.com/orgs/Homebrew/teams/plc/members)
- Make them [billing managers](https://github.com/organizations/Homebrew/settings/billing) and [moderators](https://github.com/organizations/Homebrew/settings/moderators) on the Homebrew GitHub organisation
- Invite them to the [`homebrew` private 1Password](https://homebrew.1password.com/people) and add them to the "plc" group.

When they cease to be a PLC member, revoke or downgrade their access to all of the above.

## TSC

If a maintainer is elected to the Homebrew's [Technical Steering Committee](https://docs.brew.sh/Homebrew-Governance#7-technical-steering-committee):

- Invite them to the [**@Homebrew/tsc** team](https://github.com/orgs/Homebrew/teams/tsc/members)
- Make them [billing managers](https://github.com/organizations/Homebrew/settings/billing) and [moderators](https://github.com/organizations/Homebrew/settings/moderators) on the Homebrew GitHub organisation

When they cease to be a TSC member, revoke or downgrade their access to all of the above.

## Owners

The Project Leader, one other PLC member (ideally a maintainer) and one other TSC member should be made owners on GitHub and Slack:

- Make them owners on the [Homebrew GitHub organisation](https://github.com/orgs/Homebrew/people)
- Make them owners on the [`machomebrew` private Slack](https://machomebrew.slack.com/admin)
- Make them owners on the [`homebrew` private 1Password](https://homebrew.1password.com/people)

When they cease to be am owner, revoke or downgrade their access to all of the above.

## Members

People who are either not eligible or willing to be Homebrew maintainers but have shown continued involvement in the Homebrew community may be admitted by a majority vote of the [Project Leadership Committee](https://docs.brew.sh/Homebrew-Governance#4-project-leadership-committee) to join the Homebrew GitHub organisation as [members](https://docs.brew.sh/Homebrew-Governance#2-members).

When admitted as members:

- Invite them to the [**@Homebrew/members** team](https://github.com/orgs/Homebrew/teams/members), to give them access to the private governance repository.
- Invite them as a single-channel guest to the #members channel on the [`machomebrew` private Slack](https://machomebrew.slack.com/admin/invites) (and ensure they've read the [communication guidelines](Maintainer-Guidelines.md#communication)) and ask them to use their real name there (rather than a pseudonym they may use on e.g. GitHub).
- Add them to the current year's membership list in the [governance archives](https://github.com/Homebrew/brew/tree/master/docs/governance).

If they are interested in doing ops/infrastructure/system administration work:

- Invite them to the [`homebrew` private 1Password](https://homebrew.1password.com/people) and add them to the "ops" group.

If they are interested in doing security work:

- Invite them to the [`homebrew` private 1Password](https://homebrew.1password.com/people) and add them to the "security" group.

See [Homebrew Governance](Homebrew-Governance.md) for when an individual's membership expires.
