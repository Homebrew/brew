# How to Organize AGM

AGM is our combination of business meeting, yearly work planning session, and opportunity to meet others in our international team in person.

This document is a _guide_ that assumes that the meeting will be held in person.
If a situation occurs that prevents that, it is acceptable to execute it virtually, as was done in 2021 and 2022 during the COVID-19 pandemic.

<!-- TOC start -->

* [Roles](#roles)
* [Logistics Timeline](#logistics-timeline)
  * [Three months prior](#three-months-prior)
  * [Two months prior](#two-months-prior)
  * [Four weeks prior](#four-weeks-prior)
  * [Three weeks prior](#three-weeks-prior)
  * [Two weeks prior](#two-weeks-prior)
  * [10 days prior](#10-days-prior)
  * [One week prior](#one-week-prior)
  * [Day before](#day-before)
  * [Day-of](#day-of)
* [Pre-planning](#pre-planning)
  * [Finding a Meeting Venue](#finding-a-meeting-venue)
  * [Who Qualifies For AGM Travel Assistance](#who-qualifies-for-agm-travel-assistance)
* [Ideas for future AGMs](#ideas-for-future-agms)
  * [Meeting enhancements](#meeting-enhancements)
  * [Day-of enhancements](#day-of-enhancements)

<!-- TOC end -->

## Roles

Expected participants:

|Who|Role|
|---|---|
|Project Leadership Committee (PLC)|Should be physically present if possible, dialed-in if not. Several members must be present in person to run the event. Several members, regardless, needed to provide content for meeting.|
|Project Leader (PL)|Should be physically present if possible, dialed-in if not. Regardless, needed to provide content for meeting.|
|Technology Steering Committee (TSC)|Should be physically present if possible, dialed-in if not. Regardless, needed to provide content for meeting.|
|Members|Should dial-in or participate in person if possible.|

PLC members' roles of responsibility for planning and execution:

|Who|Role|
|---|---|
|Logistics Coordinator (LC)|Coordinates with meeting venue, restaurants, members, committees, vendors|
|Agenda Coordinator (AC)|Coordinates agenda and content to be presented|
|Technology Coordinator (TC)|Coordinates video conference audiovisual setup|

:information_source: _(A person may have more than one role but one person should not have all roles.)_

## Logistics Timeline

Past practice and future intent is for AGM to coincide with [FOSDEM](https://fosdem.org "Free and Open Source Developers European Meeting"), which is held in Brussels, Belgium annually typically on the Saturday and Sunday of the fifth ISO-8601 week of the calendar year, calculable with:

    ruby -rdate -e "s=ARGV[0].to_i;s.upto(s+4).map{|y|Date.commercial(y,5,6)}.each{|y|puts [y,y+1].join(' - ')}" 2024

AGM should be held on the Friday before or the Monday following FOSDEM.

:information_source: _Regenerate the dates for the WHEN lines in the next several headers
using this quick command:_

    ruby -rdate -e "YEAR=ARGV[0].to_i;puts ([[44,YEAR-1],[49,YEAR-1]]+(1.upto(4).map{|wk|[wk, YEAR]})).map{|wk,yr|Date.commercial(yr,wk).to_s}" 2024

### Three months prior

**When:** Week 44 of YEAR-1 :date: `2023-10-30`

* [ ] LC: Seek venue through previous contacts or RFP.
* [ ] PLC: Notify members of eligibility to attend AGM, with date to be determined.
  * This is primarily to enable members to begin planning travel by
      asking for time off, requesting employer reimbursement,
      arranging childcare or pet sitters,
      [applying for a visa](https://5195.f2w.bosa.be/en/themes/entry/border-control/visa/visa-type-c)
      which may [take 2–7 weeks](https://dofi.ibz.be/en/themes/third-country-nationals/short-stay/processing-time-visa-application),
      etc.

### Two months prior

**When:** Week 49 of YEAR-1 :date: `2023-12-04`

* [ ] LC: Seek informal count of members intending to attend in-person.
* [ ] PL: Review maintainer activity per [Governance/Maintainers](Homebrew-Governance.md#8-maintainers).
* [ ] PLC: Determine travel assistance budget.
* [ ] PLC: Open travel assistance pre-approval process.

### Four weeks prior

**When:** Week 1 of YEAR :date: `2024-01-01`

* [ ] PLC: Solicit changes to [Homebrew Governance](Homebrew-Governance.md) in the form of PRs on the `homebrew-governance-private` repo.

### Three weeks prior

**When:** Week 2 of YEAR :date: `2024-01-08`

* [ ] PLC: Close travel assistance pre-approval process.

### Two weeks prior

**When:** Week 3 of YEAR :date: `2024-01-15`

* [ ] AC: Create agenda, solicit agenda items from PLC and TSC.
* [ ] LC: Seek committed member attendance and dietary requirements for each.
* [ ] PLC: Close proposals for new Governance changes.

### 10 days prior

**When:** Week 4 of YEAR :date: `2024-01-22`

* [ ] PLC: Resolve all open Governance PRs, roll-up changes, and open PR with changes to `docs/Homebrew-Governance.md` on `homebrew/brew`.

### One week prior

**When:** Week 4 of YEAR :date: `2024-01-22`

* [ ] PLC: Open voting for PLC, PL, and Governance changes.
* [ ] AC: Solicit agenda items from membership.
* [ ] LC: Secure a venue and reservation for dinner

### Day before

* [ ] LC: Confirm reservation count for dinner with attendees
* [ ] LC: Hand-off venue AV contact to TC

### Day-of

* [ ] LC: Confirm reservation count for dinner with venue
* [ ] TC: Connect to video conference, ensure audiovisual equipment is ready and appropriately placed and leveled periodically
* [ ] AC: Keep the meeting paced to the agenda, keep time for timeboxed discussions, cut people off if they're talking too long, ensure remote attendees can get a word in

## Pre-planning

### Finding a meeting venue

In the past, PLC hosted the AGM at the
[THON Hotel Brussels City Centre](https://www.thonhotels.com/conference/belgium/brussels/thon-hotel-brussels-city-centre/?Persons=20)
and arranged for a room block checking in the day before FOSDEM and AGM weekend, generally on Friday, and checking out the day after, generally Tuesday when the AGM is Monday.

### Who qualifies for AGM travel assistance

Travel assistance is available for AGM participants who are expected to attend the AGM in-person.
Those who have employers able to cover all or a part of the costs of attending FOSDEM should exhaust that
source of funding before seeking Homebrew funding.

PLC, TSC, PL and maintainers can expect to have all reasonable, in-policy expenses covered while members will be considered on a case-by-case basis.

Read the Expense and Reimbursement policy document in `Homebrew/homebrew-governance-private`.
It contains the process and details on what is covered.
It is important that all attendees expecting reimbursement stay in-policy.

## Ideas for future AGMs

### Meeting enhancements

* Captioning or transcription, or both - [White Coat Captioning](https://whitecoatcaptioning.com) could handle the live captioning and provide us that for a transcript.
* Separate meeting runner
  * Keep PL ideally focused on content and not agenda or tracking who's asked to speak
  * Should be a PLC member who is not the AC, LC, or TC
  * Should be someone happy and willing to cut people off mid-sentence and, assertively but in a friendly manner, stop conversations that are not running to time

### Day-of enhancements

* Track dietary requirements centrally for in-person participants
