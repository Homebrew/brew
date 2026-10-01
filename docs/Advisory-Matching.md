---
last_review_date: "2026-09-16"
---

# Advisory Matching

`brew advisory-match` prepares candidate records for the [Homebrew advisory database](https://github.com/Homebrew/advisory-database).
It is an authoring tool, not the installed-package scanner provided by `brew vulns`.
Candidates still need [human review](https://github.com/Homebrew/advisory-database/blob/HEAD/CONTRIBUTING.md#reviewing-matched-candidates) before publication.

## Range accuracy and coverage

With history enabled, a candidate with a comparable current state and no reviewed range must have an affected interval that can be established from formula history.
This applies even when the current formula is known to be affected: knowing today's state does not establish when the affected range began.
An `introduced: "0"` boundary asserts that every earlier version is affected; it is not a marker for an unknown introduction.

Automatic matching deliberately favours range accuracy over coverage.
Unreadable or uncomparable history, disjoint affected intervals and affected and unaffected builds sharing a `pkg_version` can prevent a new record from being emitted.
The command warns and counts these as history-unavailable skips instead of inventing a boundary.
This includes a historical subject whose prerelease suffix changes its `SEMVER` range state compared with its release version.
A skip does not mean the formula is unaffected, so an ingest run can omit a currently affected formula and is not evidence of complete vulnerability coverage.
Reviewers must establish the ranges and matching provenance together from upstream evidence and formula build history, then contribute the record manually.

Current-version prerelease ambiguity produces an uncomparable review lead with no `range_state`, reduced confidence and `database_specific.review_reason: "prerelease_boundary"`.
Ingest drops these leads and lists their IDs by reason in its run summary.
An explicit `range_state` override for the formula and advisory resolves the current-state ambiguity; an `upstream_fixed_in` override alone does not.
Without a reviewed state override, existing reviewed records stay unchanged.

A reviewed state override does not establish historical boundaries.
When its state disagrees with comparable upstream evidence, or the upstream evidence cannot be checked, a new range needs manual review.
Existing reviewed ranges are preserved rather than replaced with guessed introductions; range transitions and changed provenance still require their own checks.

## History options

`--new-history` requires `--output` and reuses existing reviewed ranges where possible; a successful replay does not independently verify those boundaries.
`--json` without `--output` has no existing reviewed records to reuse, so history checks still apply to new comparable candidates.
`--no-history` explicitly uses unverified zero/current-version boundaries for new ranges and cannot be combined with `--new-history`.
It is an unchecked authoring mode, not a way to validate a skipped candidate.

## Reconciling existing ranges

`--reconcile-history --output advisories --overrides data/overrides.yml` explicitly revisits existing `source: matched`, bump-fixed records with one terminal interval.
It requires complete formula history and matching provenance, with the same result on the latest supported macOS and Linux for both ARM and Intel.
These simulations check declared formula and resource versions; they do not rebuild historical bottles or verify installation steps.
It can narrow an affected interval or delete a record proven never affected; it preserves other fields and updates `modified` only for a range change.
Generated records, patch fixes and open or multiple intervals are left unchanged.
For records missed by current matching, complete registry-resource evidence can supply versionless upstream queries even after a resource has been removed.
The fresh results must reproduce the stored upstream family and range basis, and every resource identity must occur in formula history on every platform.
Stored subject versions only reproduce the range basis; historical decisions use versions from the formula sources.
A missing historical resource holds the record as `resource_not_found`; a stored family absent from the fresh query results is `resource_not_rediscovered`.
Mixed, incomplete or non-resource provenance still requires current discovery.
These fallback queries cannot create records and respect formula skips and preserved Homebrew ranges.
When a prerelease suffix changes a subject’s `SEMVER` range state compared with its release version, `prerelease_boundary` holds the record for review.
The command reports skip reasons and the number of matched records it did not revisit; success does not establish complete coverage.

Before running this mode, protect hand-reviewed Homebrew boundaries with `preserve_homebrew_ranges: true` under the formula and advisory in `overrides.yml`.
The pin applies across advisory aliases and is separate from `upstream_fixed_in`, which describes the upstream fix.
Unavailable history or upstream records, changed subjects, conflicting platform results and advisory-specific patches require review.
A failed upstream lookup holds every record for that formula with `upstream_unavailable`; a failed batch query holds its entire formula batch.
A confirmed HTTP 404 while following an upstream link is cached as a missing target; a record with no resolved targets keeps its original evidence.
A 404 for a supplemental CPANSA CVE lookup uses the CPANSA evidence for that CVE, including on subsequent platform passes.
A 404 for an ID returned directly by a query still holds the formula, as do other request failures.
Reconciliation continues with the remaining formulae, so a successful command can include these holds.
Complete history includes earlier lifetimes of deleted and re-added formulae, skipping revisions where Git proves the formula path was absent.
A rename into the current formula name starts that name’s history; the old formula name’s builds are excluded.
Historical loading ignores obsolete `devel` blocks and uses the stable build.
It also accepts legacy `sha1` and `md5` declarations, `bottle :unneeded` and `plist_options` without fetching or building historical sources.
This compatibility applies to all `FormulaVersions` callers, including daily matching; ordinary current-formula loading is unchanged.
Any remaining unreadable build still holds the record, even when it appears before or after the affected interval.
A historical formula's `odie` option check becomes a failed load rather than terminating the command.
The reconciliation summary counts failed formula revisions and affected formulae separately from revision/platform failures and per-record hold reasons.
Reason counts, such as `history_unavailable`, count held records and may overlap.
With `--verbose`, each failed load includes its formula, revision, path, platform and original error, once per revision/path/platform for that formula.
Proven absent paths are not load failures; failed Git absence checks remain failures.
Unattributed patches and `inreplace` alone do not block reconciliation.
This mode cannot be combined with `--new-history`, `--no-history`, `--json` or `--index` and does not enable reconciliation in ordinary ingest runs.

For bounded daily or reconciliation runs, `--formula-list=<file>` selects newline-separated core formula names instead of `--all` or named arguments.
It requires `--new-history` or `--reconcile-history`, retains bulk queries and uses the Repology index without live per-formula fallbacks.
Only listed names still present in core are loaded; removed names are reported and their records remain unchanged.
An empty list performs no matching, and the unvisited-record summary is scoped to the list.
The advisory database partitions these lists by formula so each execution shard can be saved and retried independently.
