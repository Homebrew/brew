---
last_review_date: "2025-02-08"
---

# New Maintainer Checklist

**Existing maintainers and project leadership uses this guide to invite and onboard new maintainers and project leaders.**
**General Homebrew users might find it interesting but there's nothing here _users_ should have to know.**

- [Homebrew Maintainers](#maintainers)
- [Lead Maintainers](#lead-maintainers)
- [Ops Team](#ops-team)
- [Security Team](#security-team)
- [Owners](#owners)

## Maintainers

There's someone who has been making consistently high-quality contributions to Homebrew and shown themselves able to make slightly more advanced contributions than just e.g. formula updates? Let's invite them to be a maintainer!

First, send them the invitation email:

```markdown
The Homebrew team and I really appreciate your help on issues, pull requests and
your contributions to Homebrew.

We would like to invite you to have commit access and be a Homebrew maintainer.
If you agree to be a maintainer, you should spend the majority of the time you
are working on Homebrew (in descending order of priority):

- reviewing pull requests (from users and other maintainers)
- triaging, debugging and fixing user-reported issues and applying
- opening PRs for widely used changes (e.g. version updates)

You should also be making contributions to Homebrew at least once per quarter.

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
- Create branches in the main repository rather than on your fork to ease collaboration
  with other maintainers and allow security assumptions to be made based on GitHub access.
- If still in doubt please ask for help and we'll help you out.
- Please read:
    - https://docs.brew.sh/Maintainer-Guidelines
    - the team-specific guides linked above and in the maintainer guidelines
    - anything else you haven't read on https://docs.brew.sh

How does that sound?

Thanks for all your work so far!
```

If they accept, follow a few steps to get them set up:

- Invite them to the [**@Homebrew/maintainers** team](https://github.com/Homebrew/private/blob/main/user-management/.tfvars#L23) (or any relevant subteams) by making a pull request to linked file. This gives them write access to relevant repositories (but doesn't make them owners). They will need to enable [GitHub's Two Factor Authentication](https://help.github.com/articles/about-two-factor-authentication/).
- Invite them as a full member to the [`machomebrew` private Slack](https://machomebrew.slack.com/admin/invites) (and ensure they've read the [communication guidelines](Maintainer-Guidelines.md#communication)) and ask them to use their real name there (rather than a pseudonym they may use on e.g. GitHub).
- Ask them to disable SMS as a 2FA device or fallback on their GitHub account in favour of using one of the other authentication methods.
- Ask them to (regularly) review remove any unneeded [GitHub personal access tokens](https://github.com/settings/tokens).

If there are problems, ask them to step down as a maintainer.

When they cease to be a maintainer for any reason, revoke their access to all of the above, and don't forget to remove them from the [user-management tooling](https://github.com/Homebrew/private/blob/main/user-management/.tfvars#L23).

In the interests of loosely verifying maintainer identity and building camaraderie, if you find yourself in the same town (e.g living, visiting or at a conference) as another Homebrew maintainer you should make the effort to meet up. If you do so, you can [expense your meal](https://docs.opencollective.com/help/expenses-and-getting-paid/submitting-expenses) (within [Homebrew's reimbursable expense policies](https://opencollective.com/homebrew/expenses)). This is a more relaxed version of similar policies used by other projects, e.g. the Debian system to meet in person to sign keys with legal ID verification.

Now sit back, relax and let the new maintainers handle more of our contributions.

## Lead Maintainers

If a maintainer or member is elected to the Homebrew's Lead Maintainers:

- Invite them to the [**@Homebrew/lead-maintainers** team](https://github.com/orgs/Homebrew/teams/lead-maintainers/members)

When they cease to be a Lead Maintainer member, remove them from this team.

## Ops Team

If maintainers are interested in doing ops/infrastructure/system administration work:

- Invite them to the [**@Homebrew/ops** team](https://github.com/orgs/Homebrew/teams/ops)
- Invite them to the [`homebrew` private 1Password](https://homebrew.1password.com/people) and add them to the "ops" group.

When they cease to be doing ops work, revoke or downgrade their access to all of the above.

## Security Team

If maintainers are interested in doing security work:

- Invite them to the [**@Homebrew/security** team](https://github.com/orgs/Homebrew/teams/security)
- Invite them to the [`homebrew` private 1Password](https://homebrew.1password.com/people) and add them to the "security" group.

When they cease to be doing security work, revoke or downgrade their access to all of the above.

## Owners

The Project Leader and two other Lead Maintainers (ideally on the Security Team) should be made owners on GitHub and Slack:

- Make them owners on the [Homebrew GitHub organisation](https://github.com/orgs/Homebrew/people)
- Make them owners on the [`machomebrew` private Slack](https://machomebrew.slack.com/admin)
- Make them owners on the [`homebrew` private 1Password](https://homebrew.1password.com/people)

When they cease to be an owner, revoke or downgrade their access to all of the above.
