---
last_review_date: "2026-07-18"
---

# Package Acceptance Policy

This policy contains acceptance criteria shared by formulae and casks in Homebrew's official taps, [`homebrew/core`](https://github.com/Homebrew/homebrew-core) and [`homebrew/cask`](https://github.com/Homebrew/homebrew-cask).
Repository-specific requirements remain in [Acceptable Formulae](Acceptable-Formulae.md) and [Acceptable Casks](Acceptable-Casks.md).
[Working with Homebrew as an Upstream Project](Working-with-Homebrew-as-an-Upstream-Project.md) contains additional guidance for upstream developers.

* Table of Contents
{:toc}

## Scope and third-party taps

Homebrew's official repositories accept software that the project can verify, maintain and support for a broad user base.
Software that does not meet the official criteria can generally be maintained in a [third-party tap](How-to-Create-and-Maintain-a-Tap.md).
Distribution through a third-party tap does not imply Homebrew endorsement or support.

## Public presence and maintenance

A package must represent software with a public presence independent of Homebrew and a homepage that explains the project.
The software must be actively maintained upstream, have no known unpatched security vulnerabilities and remain practical for Homebrew to support.
Discontinued software and software that relies on Homebrew-specific patches to compensate for an unmaintained upstream are not eligible.

## Notability

A new package must demonstrate public interest beyond its author.
A GitHub project normally satisfies this requirement by meeting one of these thresholds:

* at least 30 forks, 30 watchers or 75 stars.
* at least 90 forks, 90 watchers or 225 stars for a self-submission by the repository owner.

Equivalent public evidence may be considered for software hosted elsewhere.
The metrics apply to the canonical upstream repository, not an unendorsed mirror or code-hosting fork.
A code repository less than 30 days old is normally not eligible.
Repository-specific exceptions may apply when these metrics do not represent the software's actual use or maintenance prospects.

## Discoverability and searchability

Homebrew's official repositories are not editorial curation or recommendation services.
Packages are intended to make known software straightforward to install.
Categories, recommendations and editorial collections for discovering new software are outside their scope.
Searchability and disambiguation remain in scope because users must be able to identify the correct package for known software.

## Forks that replace an existing project

A new package cannot replace an existing project with a fork unless it meets a repository-specific replacement criterion or at least one of these conditions:

* The original project or author has publicly designated the fork as its official successor.
* At least two other major software distributions use the fork as the replacement for the original project.

The fork must meet every other acceptance requirement for its repository.
A fork that does not qualify as a successor may still be proposed under a distinct name when the repository-specific policy permits it and users will not confuse it with the original project.

## Adult content

Homebrew serves users in many countries and does not apply one culture's view of adult content to every user.
Reviewing a package must not unexpectedly expose maintainers to graphic adult or violent material.

A package may contain adult content only when its `homepage` and the root page of its `url` domain are safe to open in a normal workplace review.
Those pages may contain a factual text description of the software but must not display graphic adult or violent images without an additional deliberate action.

## Project risk

Homebrew may reject or remove a package when carrying it creates a material legal, infrastructure, safety or project-continuity risk.

## Maintainer discretion

Meeting the documented criteria does not guarantee acceptance and missing one criterion does not require rejection in every case.
A documented exception will be made when it improves the overall reliability, security or usefulness of Homebrew.
New submissions may be held to a higher standard than existing packages because accepting a package creates an ongoing maintenance commitment.
