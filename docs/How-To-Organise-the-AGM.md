---
last_review_date: "2025-11-26"
---
# How To Organise the AGM

The Annual General Meeting (AGM) is our combination of a business meeting, yearly work planning session, and opportunity to meet others in our international team in person.

This document is a _guide_ that assumes that the meeting will be held in person.
If a situation occurs that prevents that, it is acceptable to execute it virtually, as was done in 2021 and 2022 during the COVID-19 pandemic.

<!-- TOC start -->

* [Roles](#roles)
* [Logistics Timeline](#logistics-timeline)
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
  * [Dietary Requirements](#dietary-requirements)

<!-- TOC end -->

## Roles

Expected participants:

|Who|Role|
|---|---|
|Project Leader (PL)|Should be physically present if possible, dialed-in if not. Regardless, needed to provide content for meeting.|
|Lead Maintainers (LM)|Should be physically present if possible, dialed-in if not. Regardless, needed to provide content for meeting.|
|Maintainers|Should dial-in or participate in person if possible.|

Delegated maintainer roles of responsibility for planning and execution:

|Who|Role|
|---|---|
|Logistics Coordinator (LC)|Coordinates with meeting venue, restaurants, vendors, maintainers|
|Agenda Coordinator (AC)|Coordinates agenda and content to be presented|
|Technology Coordinator (TC)|Coordinates video conference audiovisual setup|

A person may have more than one role but one person should not have all roles.

## Logistics Timeline

Past practice and future intent is for AGM to coincide with [FOSDEM](https://fosdem.org "Free and Open Source Developers European Meeting"), which is held in Brussels, Belgium annually typically on the Saturday and Sunday of the fifth ISO-8601 week of the calendar year, calculable with:

    ruby -rdate -e "s=ARGV[0].to_i;s.upto(s+4).map{|y|Date.commercial(y,5,6)}.each{|y|puts [y,y+1].join(' - ')}" 2026

AGM should be held on the Friday before or the Monday following FOSDEM.

:information_source: _Regenerate the dates for the WHEN lines in the next several headers
using this quick command:_

    ruby -rdate -e "YEAR=ARGV[0].to_i;puts ([[49,YEAR-1]]+(1.upto(4).map{|wk|[wk, YEAR]})).map{|wk,yr|Date.commercial(yr,wk).to_s}" 2026

### Two months prior

**When:** Week 49 of YEAR-1 :date: `2025-12-01`

* [ ] LC: Seek informal count of maintainers intending to attend in person.
* [ ] PL: Review maintainer activity per [Homebrew Governance](Homebrew-Governance.md).
* [ ] PL: Open travel assistance pre-approval process.
  * This is primarily to enable maintainers to begin planning travel by
    asking for time off, requesting employer reimbursement,
    arranging childcare or pet sitters,
    [applying for a visa](https://5195.f2w.bosa.be/en/themes/entry/border-control/visa/visa-type-c)
    which may [take 2–7 weeks](https://dofi.ibz.be/en/themes/third-country-nationals/short-stay/processing-time-visa-application),
    etc.
* [ ] PL: Remind those traveling from countries exempt from EU visa requirements (e.g. US, UK, AU, CA) to file for [ETIAS travel authorization](https://travel-europe.europa.eu/etias_en) (generally processed in minutes but could take up to 30 days), advisable to get processed _before_ buying airfare.

### Four weeks prior

**When:** Week 1 of YEAR :date: `2025-12-29`

* [ ] PL: Solicit changes to [Homebrew Governance](Homebrew-Governance.md) in the form of PRs to the `private` repository.

### Three weeks prior

**When:** Week 2 of YEAR :date: `2026-01-05`

* [ ] PL: Close travel assistance pre-approval process.

### Two weeks prior

**When:** Week 3 of YEAR :date: `2025-01-06`

* [ ] AC: Create agenda, solicit agenda items from PL and LM.
* [ ] LC: Seek committed maintainer attendance and dietary requirements for each.
* [ ] PL: Close proposals for new Governance changes.

### 10 days prior

**When:** Week 3 of YEAR :date: `2026-01-12`

* [ ] PL: Resolve all open Governance PRs, roll-up changes, and open PR with changes to `docs/Homebrew-Governance.md` on `homebrew/brew`.

### One week prior

**When:** Week 4 of YEAR :date: `2026-01-19`

* [ ] PL: Open voting for PL and Governance changes.
* [ ] AC: Solicit agenda items from maintainers.
* [ ] LC: Secure a venue and reservation for dinner.

### Day before

* [ ] LC: Confirm reservation count for dinner with attendees
* [ ] LC: Hand-off venue AV contact to TC

### Day-of

* [ ] LC: Confirm reservation count for dinner with venue
* [ ] TC: Connect to video conference, ensure audiovisual equipment is ready and appropriately placed and leveled periodically
* [ ] AC: Keep the meeting paced to the agenda, keep time for timeboxed discussions, cut people off if they're talking too long, ensure remote attendees can get a word in

## Pre-planning

### Finding a Meeting Venue

In the past, Homebrew hosted the AGM at the
[THON Hotel Brussels City Centre](https://www.thonhotels.com/conference/belgium/brussels/thon-hotel-brussels-city-centre/?Persons=20)
and arranged for a room block checking in the day before FOSDEM and AGM weekend, generally on Friday, and checking out the day after, generally Tuesday when the AGM is Monday.

### Who Qualifies For AGM Travel Assistance

Travel assistance is available for AGM participants who are expected to attend the AGM in-person.
Those who have employers able to cover all or a part of the costs of attending FOSDEM should exhaust that
source of funding before seeking Homebrew funding.

PL, LM and maintainers can expect to have all reasonable, in-policy expenses covered.

See also the [Expense and Reimbursement Travel Policy](Expense-and-Reimbursement-Policy.md#travel-policy) for process and details on what is covered.
It is important that all attendees expecting reimbursement stay in-policy.

### Dietary Requirements

Track dietary requirements centrally for in-person participants.
