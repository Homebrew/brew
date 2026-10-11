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
- **Ops Team**: Maintainers responsible for operating Homebrew's infrastructure.
- **Project Leader (PL)**: A Maintainer elected from the Lead Maintainers to serve as Homebrew’s primary public representative and project-wide coordinator.
- **Deputy Project Leader (DPL)**: A Maintainer elected from the Lead Maintainers to act as Project Leader when the Project Leader is unavailable.
- **Quarterly activity criteria**: Around 50 meaningful maintainer contributions per quarter to Primary Homebrew repositories to remain in good standing as a Maintainer.
  Lead Maintainers have mandatory numerical requirements, defined below.
- **Quarter**: A Homebrew reporting quarter, defined as one of the following periods: December–February, March–May, June–August, or September–November.
  Quarterly reporting covers the Maintainers listed in Homebrew/brew's README at the end of the quarter.
  The report's `potential new role` column uses preceding full quarterly reports to apply multi-quarter role requirements.
  Its recommendations require review against Maintainer discretion, Security and Ops Team exceptions and non-numerical eligibility criteria before role changes are made.
- **Meaningful maintainer contributions**: Merged pull requests by the Maintainer, pull requests created by others that GitHub reports as both reviewed and approved by the Maintainer, or merged co-authored commits in Primary Homebrew repositories.
  A pull request opened and merged by the same Maintainer counts only once for that Maintainer.
  Review attribution uses GitHub's `review:approved reviewed-by:USERNAME` search as an intentionally ambiguous, 100-result-capped activity proxy, not a precise approval audit.
  Repository-scoped follow-up searches ensure that capped counts do not affect role activity checks.
- **Primary Homebrew repositories**: The three highest-traffic, security-critical repositories in the Homebrew project:
  - [Homebrew/brew](https://github.com/Homebrew/brew) ([contributions](https://github.com/Homebrew/brew/graphs/contributors)),
  - [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) ([contributions](https://github.com/Homebrew/homebrew-core/graphs/contributors)),
  - [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) ([contributions](https://github.com/Homebrew/homebrew-cask/graphs/contributors))

## 2. Roles

### Maintainer

**Privileges:**

- Write access on assigned GitHub repositories.
- Participation in maintainer-only technical discussions and informal decision-making.
- Voting rights on governance and project direction.
- May become eligible for Lead Maintainer status through sustained contributions and initiative.

**Expectations:**

- Maintains consistent quarterly contribution activity, as defined in Homebrew's activity criteria.
- Contributions require write access e.g. review of pull requests and not just fork access e.g. opening pull requests.

**Accession:**

- Regular Maintainer status has no in-person meeting requirement.
- Any Lead Maintainer may nominate for Maintainer any person with positive contribution activity and voting commences immediately.
- The nominee becomes a Maintainer upon approval by a simple majority vote of Lead Maintainers who respond within 7 days.
- A Maintainer remains a Maintainer until resignation or removal for inactivity.

**Removal for Inactivity:**

The Project Leader applies this policy after considering other essential work under the quarterly activity criteria.
Security Team members may be exempt from this Maintainer inactivity policy.
Ops Team members may also retain Maintainer status if the Project Leader determines that their Ops activity has been substantial, timely and reliable.

- Missing the activity threshold for 1 quarter triggers a private warning.
- If the Maintainer meets the activity threshold in the following quarter, the warning is cleared and the process resets.
- If a Maintainer has a disclosed medical emergency preventing activity, they will be removed as usual but their tenure is not reset when being reconsidered for Maintainer or Lead Maintainer in the future once activity levels resume.
- Missing the activity threshold for 2 consecutive quarters results in immediate removal from the Maintainer role.

---

### Lead Maintainer

Lead Maintainers act collectively as Homebrew’s leadership.

**Privileges:**

- Maintain access on all GitHub repositories.
- Voting rights on governance and project direction.

**Expectations:**

- Must make at least 50 meaningful maintainer contributions in total and at least 25 in each of any two Primary Homebrew repositories per quarter.
  These numerical requirements are mandatory for eligibility and retention and cannot be waived or replaced by other work.
- A higher level of responsibility and responsiveness than standard maintainers e.g. timely pull request review, timely responses in Slack, pulling weight on shared project tasks and not just whatever is personally most interesting.

**Eligibility Criteria:**

- 3 years tenure of continuous Maintainer status.
- Has met the Lead Maintainer quarterly activity expectation defined above in all four quarters of the preceding year.
- Must have attended at least one in-person AGM (or another official Homebrew event) to verify identity and participation within the community.
  As a fallback: must have met at least one other Homebrew Lead Maintainer in person before becoming a Lead Maintainer.
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
- Upon demotion, the contributor's Maintainer inactivity record is not reset.
  Only quarters that also fail the Maintainer activity criteria count towards removal under the Maintainer inactivity policy, subject to its discretion and Security and Ops Team exceptions.

---

### Project Leader

**Responsibilities:**

- Serves as the primary point for formal communications and external coordination, and may delegate public representation to other Lead Maintainers as needed.
- Coordinates day-to-day operations, executes addition and removal of Maintainers under the eligibility criteria and inactivity policies defined in this document, and ensures project-level decisions are followed through.
- Organises Lead Maintainer discussions.
- Executes and ensures decision-making processes as required by this governance document.
- Facilitates AGM planning and/or appoints designees to do so.

**Expectations:**

- The highest level of responsibility and responsiveness of all maintainers e.g. timely pull request review, timely responses in Slack, pulling weight on shared project tasks and not just whatever is personally most interesting.

**Term:**

- The Project Leader serves a two-year term.
- Candidates must be Lead Maintainers at the time of election.
- Ceasing to be a Maintainer vacates the Project Leader position; ceasing to be a Lead Maintainer does not.
- If the existing Project Leader is the only Lead Maintainer standing as a candidate, that person remains Project Leader without a vote.
- If more than one Lead Maintainer stands as a candidate, the Project Leader is chosen by a simple majority of Lead Maintainers who respond within 7 days.
- If the position is vacant, a new election will be held within 14 days to fill the Project Leader spot for the remainder of the term.
- If no Lead Maintainer stands as a candidate, the current Project Leader remains in office until a successor is elected.

**Removal:**

- The Project Leader may be removed before the end of their term by a ⅔ supermajority vote of all current Lead Maintainers.
- A removal vote may be initiated by any Lead Maintainer submitting a non-anonymous request to all Lead Maintainers.
- The removal vote will be conducted among all current Lead Maintainers via a public GitHub pull request or other transparent mechanism.

---

### Deputy Project Leader

**Responsibilities:**

- Acts as Project Leader when the Project Leader is unavailable or the position is vacant, until the Project Leader returns or a successor takes office.
- While acting as Project Leader, exercises the same responsibilities and decision-making authority, subject to the same limits and review requirements.

**Eligibility:**

- Must be a Lead Maintainer at the time of election and cannot simultaneously hold the Project Leader position.

**Term and removal:**

- The first Deputy Project Leader will be elected at the 2027 AGM for a term ending at the 2029 AGM.
- Elected every second year for a two-year term, with Project Leader and Deputy Project Leader elections held in alternate years.
- Ceasing to be a Maintainer vacates the Deputy Project Leader position; ceasing to be a Lead Maintainer does not.
- Where not otherwise specified, the Project Leader's term and removal rules apply equally to the Deputy Project Leader.

---

## 3. Decision-making

- Formal governance decisions are made by vote of all Maintainers.
- Major financial decisions (i.e. changes to existing documented financial processes or new one-time expenditures) are made by vote of the Lead Maintainers.
- Minor financial approvals (i.e. approving expected Open Collective expenses) can be made by any Lead Maintainer.

- Informal decisions may proceed by discussion unless a vote is requested by any Lead Maintainer.
- Formal votes require a simple majority.

- In emergencies, the Project Leader may make an immediate decision. The Project Leader must submit the matter, decision and rationale for exercising emergency powers, for review and confirmation by a majority vote of Lead Maintainers, within 7 days.
- In the event of a tie or procedural ambiguity, the Project Leader will make the final decision, even if they have already voted.

- A vote is resolved (a) the moment an option secures a simple majority of all votes, or (b) automatically after 7 days, with the option receiving the most votes winning.

- When voting is conducted using pull request review:
  - Voting will begin when the pull request is opened.
  - Voting is conducted as follows:
    - To vote in favour: Submit a ✅ review approval, or if lacking write permissions, a comment review with a ✅ emoji in the comment.
    - To vote against: Submit a ❌ "request changes" review, or if lacking write permissions, a comment review with a ❌ emoji in the comment.
    - To abstain: Submit a comment review containing the word "abstain".

---

## 4. Security & emergency actions

- The Security Team comprises the Project Leader and any number of Maintainers appointed by the Project Leader, serving until resignation or removal from the team by the Project Leader.
- Before joining the Security or Ops Team or becoming a human GitHub organisation owner, Maintainers must have met a Homebrew Lead Maintainer in person, preferably at an in-person AGM or another official Homebrew event.
- Security Team members may be exempt from Maintainer numerical contribution requirements and may instead be evaluated by the Project Leader on qualitative security observations, such as their helpfulness to the project's security goals.
  This exemption does not waive the mandatory numerical requirements for becoming or remaining a Lead Maintainer.
- Only Security Team members may make Homebrew/brew releases, whether directly or through automation.
- GitHub organisation owners must include the Project Leader, Deputy Project Leader and at least one other Maintainer, preferably from the Security Team.
  At least three human owners must be retained, including while an elected position is vacant.
- Only Security Team members may hold owner or equivalent top-level administrative access to Slack, 1Password or other project services apart from GitHub.
  Ops Team members may also hold AWS AdministratorAccess; this exception is limited to AWS.
  Leaving the Security Team requires revocation of release access and any administrative permissions no longer authorised by this policy.
- Only Security Team members who are GitHub organisation owners may be granted bypass permissions on GitHub repository rules.
  Maintainer and Lead Maintainer roles do not grant repository Admin or bypass permissions; organisation owners retain their inherited administrative access.
- GitHub organisation owners are granted the necessary technical permissions on all primary Homebrew repositories to immediately revoke access in emergencies.
  The Project Leader and at least 2 other Security Team members hold the equivalent emergency permissions for other project infrastructure.
- In emergencies (e.g. malicious commits, compromised credentials, abuse of access), any Security Team member or Lead Maintainer may immediately revoke access using their existing permissions and must notify all other Lead Maintainers.
  Where additional permissions are needed, they must request action from a GitHub organisation owner or the Security Team as appropriate.
- A formal review must occur within 7 days and be published to all Maintainers within 21 days.
- Restoration or permanent removal is determined by a simple majority vote of Lead Maintainers.

---

## 5. Transparency & updates

- This document will be reviewed annually.

### Amendment process

- **Who can propose changes:** Any Maintainer or Lead Maintainer may propose amendments to this document.
- **How to propose:** Proposed changes must be submitted as a pull request with a clear rationale and summary.
- **Review period:** All proposed amendments must be open for review and comment by all eligible to vote for at least 7 days before a vote is held.
- **Approval:** Amendments require approval by a majority vote of all Maintainers. Voting is conducted using the pull request review method described in [Section 3: Decision-Making](#3-decision-making).
- **Effective date:** Approved amendments take effect immediately upon merging.

---

## 6. Code of conduct

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
