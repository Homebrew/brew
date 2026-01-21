---
last_review_date: "2026-01-13"
---

# Homebrew Governance

Homebrew’s governance is grounded in the principle that only active contributors should decide the project’s direction.

---

## 1. Definitions

- The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).
- **AGM**: Annual General Meeting, a typically in-person event hosted by the Project Leader that all maintainers may attend.
- **Maintainer**: Active contributors with commit access to one or more Primary Homebrew repositories (defined below).
- **Lead Maintainer**: A Maintainer with sustained, long-term impact and leadership within the project with commit access to all Homebrew repositories.
- **Security Team**: A security-focused subteam of Maintainers and the Project Leader, some of whom may have increased access rights than otherwise needed.
- **Project Leader (PL)**: A Lead Maintainer elected to serve as Homebrew’s primary public representative and project-wide coordinator.
- **Quarterly activity criteria**: Around 50 meaningful maintainer contributions or other work considered essential by the Project Leader per quarter to Primary Homebrew repositories to remain in good standing.
- **Quarter**: A calendar quarter, defined as one of the following periods: December–February, March–May, June–August, or September–November.
- **Meaningful maintainer contributions**: Merged pull requests, reviewed pull requests created by others, or merged co-authored commits in Primary Homebrew repositories.
- **Primary Homebrew repositories**: The three highest-traffic, security-critical repositories in the Homebrew project:
  - [Homebrew/brew](https://github.com/Homebrew/brew) ([contributions](https://github.com/Homebrew/brew/graphs/contributors)),
  - [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) ([contributions](https://github.com/Homebrew/homebrew-core/graphs/contributors)),
  - [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) ([contributions](https://github.com/Homebrew/homebrew-cask/graphs/contributors))

## 2. Roles

### Maintainer

**Privileges:**

- Commit/merge access on assigned repositories.
- Participation in maintainer-only technical discussions and informal decision-making.
- Voting rights on governance and project direction.
- May become eligible for Lead Maintainer status through sustained contributions and initiative.

**Expectations:**

- Maintains consistent quarterly contribution activity, as defined in Homebrew's activity criteria.
- Contributions require write access e.g. review of pull requests and not just fork access e.g. opening pull requests.

**Accession:**

- Any Lead Maintainer may nominate for Maintainer any person with positive contribution activity and voting commences immediately.
- The nominee becomes a Maintainer upon approval by a simple majority vote of Lead Maintainers who respond within 7 days.
- A Maintainer remains a Maintainer until resignation or removal for inactivity.

**Removal for Inactivity:**

- Missing the activity threshold for 1 quarter triggers a private warning.
- If the Maintainer meets the activity threshold in the following quarter, the warning is cleared and the process resets.
- If a Maintainer has a disclosed medical emergency preventing activity, they will be removed as usual but their tenure is not reset when being reconsidered for Maintainer or Lead Maintainer in the future once activity levels resume.
- Missing the activity threshold for 2 consecutive quarters results in immediate removal from the Maintainer role.

---

### Lead Maintainer

Lead Maintainers act collectively as Homebrew’s leadership.
No single person holds special authority beyond the Project Leader role.

**Privileges:**

- Commit/merge access on all repositories.
- Voting rights on governance and project direction.

**Expectations:**

- A higher level of consistent quarterly contribution activity than standard maintainers.
- A higher level of responsibility and responsiveness than standard maintainers e.g. timely pull request review, timely responses in Slack, pulling weight on shared project tasks and not just whatever is personally most interesting.

**Eligibility Criteria:**

- 3 years tenure of continuous Maintainer status.
- Has met the quarterly activity criteria (as defined above) in all four quarters of the preceding year.
  - In addition, must have made at least 25 meaningful maintainer contributions per quarter in each of at least two primary Homebrew repositories, reflecting the broader scope of Lead Maintainer responsibilities.
- Must have attended at least one in-person AGM (or another official Homebrew event) to verify identity and participation within the community.
  Where this is impossible due to e.g. medical reasons, an in-person verification of government ID from another Lead Maintainer will suffice.
- Demonstrates initiative beyond personal contributions, including leadership in review, policy, tooling, or infrastructure.

**Accession:**

- After reviewing contribution activity each quarter, the Project Leader shall provide to the Lead Maintainers a complete list of all Maintainers who meet the eligibility criteria for promotion.
- Any Maintainer who believes they meet the criteria may self-nominate for consideration, and voting commences immediately if they meet the eligibility criteria. If they do not, they are notified and voting does not occur.
- The Maintainer becomes a Lead Maintainer upon approval by a simple majority vote of Lead Maintainers who respond within 7 days, with a minimum quorum of 3 responses.
  If the quorum is not met, the voting period will be extended by 7 days.
  If there are still insufficient responses after the extension, the proposal will be considered unsuccessful and may be resubmitted at a later date.
- A Lead Maintainer remains a Lead Maintainer until resignation or removal for inactivity.

**Removal for Inactivity:**

- Missing the activity threshold for 1 quarter triggers a private warning.
- Missing the activity threshold for 2 consecutive quarters results in a change of status to Maintainer.
- Upon demotion, the contributor's inactivity record is not reset. The individual's missed quarters as Lead Maintainer count toward the Maintainer inactivity policy.
  If the demoted individual has already missed 2 consecutive quarters (as Lead Maintainer and/or Maintainer), they are subject to immediate removal in accordance with the Maintainer policy.

---

### Project Leader

**Responsibilities:**

- Serves as the primary point for formal communications and external coordination, and may delegate public representation to other Lead Maintainers as needed.
- Coordinates day-to-day operations, executes addition and removal of Maintainers under the eligibility criteria and inactivity policies defined in this document, and ensures project-level decisions are followed through.
- Organizes Lead Maintainer discussions.
- Executes and ensures decision-making processes as required by this governance document.
- Facilitates AGM planning and/or appoints designees to do so.

**Expectations:**

- The highest level of responsibility and responsiveness of all maintainers e.g. timely pull request review, timely responses in Slack, pulling weight on shared project tasks and not just whatever is personally most interesting.

**Term:**

- The Project Leader serves a two-year term.
- If the existing Project Leader is the only Lead Maintainer standing as a candidate, that person remains Project Leader without a vote.
- If more than one Lead Maintainer stands as a candidate, the Project Leader is chosen by a simple majority of Lead Maintainers who respond within 7 days.
- If the position is vacant, a new election will be held within 14 days to fill the Project Leader spot for the remainder of the term.
- If no Lead Maintainer stands as a candidate, the current Project Leader remains in office until a successor is elected.

**Removal:**

- The Project Leader may be removed before the end of their term by a ⅔ supermajority vote of all current Lead Maintainers.
- A removal vote may be initiated by any Lead Maintainer submitting a non-anonymous request to all Lead Maintainers.
- The removal vote will be conducted among all current Lead Maintainers via a public GitHub pull request or other transparent mechanism.

---

## 3. Decision-Making

Formal governance decisions are made by vote of all Maintainers.
Major financial decisions (i.e. changes to existing documented financial processes or new one-time expenditures) are made by vote of the Lead Maintainers.
Minor financial approvals (i.e. approving expected OpenCollective expenses) can be made by any Lead Maintainer.

- Informal decisions may proceed by discussion unless a vote is requested by any Lead Maintainer.
- Formal votes require a simple majority.

- In emergencies, the Project Leader may make an immediate decision. The Project Leader must submit the matter, decision and rationale for exercising emergency powers, for review and confirmation by a majority vote of Lead Maintainers, within 7 days.
- In the event of a tie or procedural ambiguity, the Project Leader will make the final decision, even if they have already voted.

- A vote is resolved (a) the moment an option secures a simple majority of all votes, or (b) automatically after 7 days, with the option receiving the most votes winning.

- When voting is conducted using pull request review:
  - Voting will begin when the pull request is opened.
  - Voting is conducted as follows:
    - To vote in favor: Submit a ✅ review approval, or if lacking write permissions, a comment review with a ✅ emoji in the comment.
    - To vote against: Submit a ❌ "request changes" review, or if lacking write permissions, a comment review with a ❌ emoji in the comment.
    - To abstain: Submit a comment review containing the word "abstain".

---

## 4. Security & Emergency Actions

- The Security Team is comprised of any number of Maintainers appointed by the Project Leader, serving until resignation or removal from the team by the Project Leader.
- The Project Leader and 2 other Lead Maintainers are granted the necessary technical permissions (e.g. Owner or Admin roles) on all primary Homebrew repositories and infrastructure to immediately revoke access in emergencies.
  When possible, these 2 Lead Maintainers should be members of the Security Team.
  If there are not enough eligible Lead Maintainers on the Security Team, the Project Leader will appoint other Lead Maintainers to fulfill this role, with the appointments subject to confirmation by a simple majority vote of all Lead Maintainers.
- In emergencies (e.g. malicious commits, compromised credentials, abuse of access), any Lead Maintainer may immediately revoke access and must notify all other Lead Maintainers.
- A formal review must occur within 7 days and be published to all Maintainers within 21 days.
- Restoration or permanent removal is determined by a simple majority vote of Lead Maintainers.

---

## 5. Transparency & Updates

- This document will be reviewed annually.

### Amendment Process

- **Who can propose changes:** Any Maintainer or Lead Maintainer may propose amendments to this document.
- **How to propose:** Proposed changes must be submitted as a pull request with a clear rationale and summary.
- **Review period:** All proposed amendments must be open for review and comment by all eligible to vote for at least 7 days before a vote is held.
- **Approval:** Amendments require approval by a majority vote of all Maintainers. Voting is conducted using the pull request review method described in [Section 3: Decision-Making](#3-decision-making).
- **Effective date:** Approved amendments take effect immediately upon merging.

---

## 6. Code of Conduct

All contributors, Maintainers and Lead Maintainers must follow the Homebrew [Code of Conduct](https://github.com/Homebrew/.github/blob/HEAD/CODE_OF_CONDUCT.md).

**Code of Conduct Maintainer Enforcement Process:**

- **Reporting:** Any maintainer may report a suspected violation by any other maintainer by contacting any Lead Maintainer directly on Slack.
- **Initial Review:** Upon receiving a report, at least two Lead Maintainers not involved in the report will review the case. The subject of the report will be notified and given an opportunity to respond to the reviewing Lead Maintainers.
- **Decision:** The Lead Maintainers will determine, by simple majority excluding the accuser and the accused, whether a violation occurred. If they determine that a violation occurred, they will discuss in a private Slack channel omitting the accuser and the accused, what action is appropriate and take action. Due to the sensitive nature, there are no fixed timelines or timescales here.
- **Notification:** The outcome will be communicated to the involved parties. Where appropriate, a public statement may be made to the community.
- **Appeals:** The subject of an enforcement action may appeal the decision by requesting a re-review by all Lead Maintainers not accused of a violation in the case. The appeal decision is final.

**Possible Enforcement Actions:**

The Lead Maintainers may take one or more of the following actions in response to a Code of Conduct violation, depending on the severity and context:

- Removal from the Maintainer or Lead Maintainer role.
- Temporary or permanent block from Homebrew's GitHub organisation.

The Lead Maintainers may use their discretion to determine the most appropriate action(s) based on the circumstances of each case.
