---
last_review_date: "1970-01-01"
---

# Homebrew Annual General Meeting 2021

## Minutes

- 2021-02-26 11:00-0800 Call to order
- 11:00–11:01 Adoption of the agenda

### Motions

- 11:01–11:05 Motion to adopt the voting system, Greg Brimble

  Greg Brimble moves to adopt the STV election method to elect the PLC and the Schulze method to elect the project leader. <https://github.com/Homebrew/brew/pull/10637>

  Motion carried unanimously.
- Shaun Jackman moves to suspend the rules requiring a three week waiting period and to adopt these election systems immediately.
  Motion carried unanimously.

### Reports

- 11:05-11:20 Project Leadership Committee's report, Jon Chang
- 11:20–11:25 Treasurer's report of the financial statements, Jon Chang
- 11:25–11:40 Technical Steering Committee's report, Misty De Meo
- 11:40–11:55 Project Leader's report, Mike McQuaid

### Elections

- 11:55–11:57 Election of the Project Leadership Committee

  Jonathan Chang and Issy Long are elected.
- 11:57–12:00 Election of the Project Leader

  Mike McQuaid elected by acclamation.
- 12:00–12:10 Recess

### Member presentations

- 12:10–12:20 Shaun Jackman - Bottle hosting
- 12:20–12:30 Daniel Nachun - Relocating bottles using binary patching
- 12:30–12:35 Caleb Xu - Quickbrew: native compiled brew <https://github.com/alebcay/quickbrew>
- 12:35–12:40 Rylan Polster - Renaming branches in Homebrew <https://github.com/Homebrew/brew/issues/10424>
- 12:40–12:45 Michka Popoff - Merging the cores <https://github.com/Homebrew/brew/issues/7028>
- 12:45–12:50 Michka Popoff - Linux CI for homebrew-core <https://github.com/Homebrew/brew/issues/10597>
- 12:50–13:55 Misty De Meo - Running Homebrew on Apple Silicon
- 12:55–13:00 Shaun Jackman - Speeding up install times/Git repository size <https://github.com/Homebrew/install/issues/523>
- 13:10 Meeting adjourned

## Resolutions

### Motion to adopt the voting system

#### Project Leader

The Homebrew Project Leader will be chosen by holding a [Schulze Condorcet method](https://en.wikipedia.org/wiki/Schulze_method) election. This popular method of voting is used by several organizations such as Wikimedia, Debian and Ubuntu. The single highest-ranked candidate, who is preferred over every other candidate in pairwise comparisons, will be elected to become the Project Leader.

Voting by proxy is permitted, and proxy votes count towards the quorum for the election.

#### Project Leadership Committee (PLC)

The Homebrew Project Leadership Committee will be chosen by holding a [Meek Single Transferable Vote (STV)](https://en.wikipedia.org/wiki/Counting_single_transferable_votes#Meek's_method) election. The quota (threshold) of votes for a candidate to be elected will be calculated using the [Droop quota](https://en.wikipedia.org/wiki/Droop_quota).

Voting by proxy is permitted, and proxy votes count towards the quorum for the election.
