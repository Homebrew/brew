# Sigstore Attestations

## Goal

Every Homebrew/core bottle is verified against its Sigstore build provenance
before it is poured, by default, with no `gh`, no GitHub token and no GitHub
API request on users' machines.

- Verification is pure Ruby, local and works offline from a cache.
- Bundles come anonymously from GitHub Packages alone, inside the one
  manifest Homebrew fetches for each bottle. A valid cache hit makes no
  network request.
- Every manifest read for a Homebrew/core bottle is checked against a
  digest from the formula or the signed JSON API.
- Only Homebrew's publishing jobs need GitHub attestation access and a
  token, and only to upload bundles to GitHub Packages.
- Wherever verification is enabled, missing or invalid provenance is fatal.
  `HOMEBREW_NO_VERIFY_ATTESTATIONS` remains the documented escape hatch.

This is a living document: edit or remove steps as they are implemented so
it always describes the remaining work.

End each implementation commit body with this exact line:

```text
This change is part of [`plans/sigstore-attestations.md`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/plans/sigstore-attestations.md)
```

Any benchmark quoted in a commit message must be the full hyperfine output
from `brew benchmark` (using its `--exec` mode for bespoke workloads), never
hand-summarised numbers.

Pull requests must always fill in the repository's pull request template
(`.github/PULL_REQUEST_TEMPLATE.md`), never bypass it (e.g. with
`gh pr create --fill`).

## Current state (13 November 2026)

### Client

- `attestation.rb`: `Homebrew::Attestation.check_attestation` shells out to
  `gh attestation verify` and raises `GhAuthNeeded` without
  `GitHub::API.credentials`. `gh_executable` installs `gh` on demand and
  `sort_formulae_for_install` (called from `cmd/install.rb`, `cmd/upgrade.rb`
  and `cmd/reinstall.rb`) forces `gh` to install first.
  `Bundle::Installer.prepare_attestation_verification!` and the `gh`
  exemption in `FormulaInstaller#verify_bottle_attestation?` exist for the
  same bootstrapping cycle.
- `Attestation.prefetch` lists bundles for a whole install plan through
  `POST /orgs/{org}/attestations/bulk-list` and hands them to `gh --bundle`.
  It needs a token and is called from `Install.fetch_formulae`,
  `Install.prelude_fetch_formulae` and `FormulaInstaller#fetch_dependencies`.
- Policy today is `gh --repo Homebrew/homebrew-core` with no workflow or ref
  constraint, a subject name equal to the bottle filename (any tag of the
  same name and version for `:all` bottles) and a fallback to
  `trailofbits/homebrew-brew-verify` backfill attestations with the subject
  `<SHA-256 of bottle URL>--<filename>` and `BACKFILL_CUTOFF`. Invalid
  attestations are retried five times with exponential back-off.
- `download_queue.rb`: `DownloadQueue#enqueue(check_attestation:)` runs
  `Utils::Attestation.check_attestation` inside the bottle's download
  future, after the download, as one `gh` process per bottle.
- `utils/attestation.rb` maps failures to `CannotInstallFormulaError`.
  `UnsupportedTapError` only warns and `GhAuthInvalid` silently disables
  verification unless the user opted in.
- `env_config.rb`: `HOMEBREW_VERIFY_ATTESTATIONS` opts in and
  `HOMEBREW_NO_VERIFY_ATTESTATIONS` opts out. Homebrew/brew CI
  (`.github/workflows/tests.yml`) and `brew test-bot --only-formulae` for
  Homebrew/core opt in; `test_bot/formulae.rb` special-cases `gh`.
- `dev-cmd/verify.rb`: `brew verify` requires `gh`.
- `Bottle#github_packages_manifest_resource` (`Resource::BottleManifest`)
  fetches the OCI image index anonymously through the mutable tag
  `manifests/<version>[-<rebuild>]`. It has no expected digest, so it is only
  parsed. Bottle blobs are fetched by digest and checked against the formula
  SHA-256.
- `sigstore` 0.3.0 and its five `protobug*` gems are vendored. Nothing
  loads them yet.

### Publishing

- `github_packages.rb`: `GitHubPackages#upload_bottle` builds an OCI layout
  (image index, one image manifest per bottle tag, config and bottle layer)
  and pushes it with `skopeo copy --all`. It knows nothing about
  attestations.
- Homebrew/core signs in `publish-commit-bottles.yml`,
  `dispatch-build-bottle.yml` and `dispatch-rebottle.yml`. Each runs
  `actions/attest` over the bottle tarballs immediately before
  `brew pr-upload`, so the bundle is on the runner (the action's
  `bundle-path` output) when bottles are uploaded.
- The `brew tap-new` workflow template (`tap-new-publish.yml`) attests after
  `brew pr-pull` has already uploaded.

### Measurements

Single samples from one network against production services. PR 7 repeats
them properly.

| Check | Result |
|---|---|
| Anonymous `GET /repos/Homebrew/homebrew-core/attestations/<digest>` | 200 in 0.4 to 2.9 s, limited to 60 requests per hour |
| Anonymous organisation list and `bulk-list` | 401 |
| GitHub Packages `GET .../referrers/<digest>` | 404 `MANIFEST_UNKNOWN`: Referrers API unsupported |
| Anonymous manifest request to `ghcr.io` | 0.12 to 0.13 s on a warm HTTP/2 connection, 0.17 to 0.21 s with a new one, never compressed |
| Anonymous blob request | 307 to `pkg-containers.githubusercontent.com`: 0.15 s warm, 0.37 s with two new connections |
| `hello` image index | 15.3 KB for six bottle tags |
| Current bundle | v0.3 JSON, Rekor v1 `dsse` entry with inclusion promise, proof and checkpoint, no timestamp authority response |
| Bundle size | 10.8 KB for one subject, 17.4 KB (9.2 KB gzipped) for 35 subjects across seven formulae: about 200 bytes per extra subject |
| Bundles per formula | `hello`: two for six bottle tags (five tags share the publishing run's bundle); `figlet`: 13 for 13 tags, as backfilled and `dispatch-build-bottle` bottles have one each |
| Backfilled bundle | `application/vnd.dev.sigstore.bundle+json;version=0.2` with a certificate chain, 10.8 KB |
| `sigstore` 0.3.0 on Homebrew's Ruby 4.0.9 and OpenSSL 4.0.3 | verified all three bundle kinds with sockets blocked in 1 to 3 ms each after a 78 ms cold `require` (92 files, no bootsnap) |
| Same, negative cases | wrong digest and wrong workflow return failures; a tampered payload or log time raises `Sigstore::Error` |
| `sigstore` 0.3.0 dependencies | ten gems (five `protobug*`, `net-http`, `net-protocol`, `timeout`, `uri`, `logger`), about 0.9 MB of Ruby |

Signer identities seen so far: `publish-commit-bottles.yml` and
`dispatch-build-bottle.yml` at `refs/heads/main` of Homebrew/homebrew-core
(repository ID 52855516, owner ID 1503512, `workflow_dispatch`) and
`backfill_signatures.yml` at `refs/heads/main` of
trailofbits/homebrew-brew-verify (repository ID 754716714).

### Prior art

Andrew Nesbitt's survey
[Signing and Attestations Across Package Registries](https://nesbitt.io/2026/10/30/signing-and-attestations-across-package-registries.html)
(October 2026) lists Homebrew's attestation check as opt-in and no surveyed
registry client as checking attestations by default at install time. Its
lessons shape this plan:

- A valid signature only proves a Sigstore identity signed. The verifier
  must supply the expected identity, and npm's trust configurations were
  attacked through being bound to a repository name instead of its ID.
- Attestations prove which workflow published, not that the workflow was
  honest: the first malicious Ultralytics releases carried valid ones.
- PEP 740 lets attestations arrive after the file, so collectors must
  re-fetch. A missing bundle is therefore never cached.
- conda's CEP 50 lists attestation digests in signed repodata, the closest
  analogue to the manifest digests below.

## Threat model and trust policy

Trusted:

1. The Homebrew/brew checkout delivered by `brew update`: code, the vendored
   verifier and the pinned Sigstore trusted root.
2. The JWS-signed JSON API, or the user's tap checkout, which supplies each
   bottle's expected SHA-256.
3. Sigstore's public-good instance: the Fulcio CA, the Rekor and certificate
   transparency logs and the timestamp authority.
4. GitHub's OIDC issuer and hosted runners executing the allow-listed
   workflows on `main` of Homebrew/homebrew-core.

Untrusted: everything served by GitHub Packages (blobs, manifests, tags and
referrers), the network, `HOMEBREW_ARTIFACT_DOMAIN` and
`HOMEBREW_BOTTLE_DOMAIN` mirrors, the local cache and the bundle bytes
themselves.

A bottle is accepted only if its bytes hash to the formula's SHA-256 and
that digest was signed by an allow-listed Homebrew workflow run and logged
publicly. An attacker who can change checksum metadata (a malicious push to
the tap, the API signing key or the API host) or the registry still needs
the publishing workflow to sign their bottle.

Out of scope, and documented as such:

- A compromised allow-listed workflow or its inputs produces valid
  attestations. Bottles are built in pull request CI and attested by the
  publishing workflow, so the provenance says "published by this workflow
  from `main` at commit X", not "built from source revision Y". The bottle
  manifest's `org.opencontainers.image.revision` annotation does name the
  tap revision a bottle was built at, but it is a different commit from the
  signed one (`29209e1` against `0da385d` for `hello` 2.12.3) and the
  manifest is unauthenticated. The signed commit is recorded, not enforced,
  although the bottle manifest digest below at least authenticates the
  manifest's build revision.
- Rolling back to an older, still valid bottle needs control of the checksum
  metadata too and is not detected.
- Withholding or corrupting bundles denies service: verification fails
  closed.

Accepted for third-party taps, which are a stretch goal (decision 12):

- Until PR 22 no third-party tap bottle is verified on the new path.
- From PR 22, a tap bottle whose block has no `manifest_sha256` is fetched
  by tag, so whoever controls the registry, a mirror or the tag can remove
  its bundle. The bottle then installs unverified with no warning, as every
  tap bottle does today for users who have not opted in.

Expected claims:

| Claim | Homebrew/core | Backfill |
|---|---|---|
| OIDC issuer | `https://token.actions.githubusercontent.com` | same |
| Repository | `Homebrew/homebrew-core`, repository ID 52855516, owner ID 1503512 | `trailofbits/homebrew-brew-verify`, repository ID 754716714 |
| Signer workflow | `publish-commit-bottles.yml`, `dispatch-build-bottle.yml` or `dispatch-rebottle.yml` | `backfill_signatures.yml` |
| Ref | `refs/heads/main` | `refs/heads/main` |
| Runner | GitHub-hosted | GitHub-hosted |
| Signing time | inside the certificate's validity, from the log or a timestamp authority | same, and no later than `BACKFILL_CUTOFF` |
| Statement | in-toto v1 with a SLSA provenance v1 predicate | same |
| Subject digest | SHA-256 of the downloaded tarball, equal to the formula's | same |
| Subject name | the bottle filename, which binds formula, version, tag and rebuild; any tag of the same name and version for `:all` | `<SHA-256 of bottle URL>--<filename>` |

The mirror census in PR 11 must confirm the workflow and ref lists against
every published bottle before PR 6's allow-list is final. A comment in
`Attestation.check_core_attestation` says some backfill bundles were signed
from a `backfill` branch. None has been seen, so that ref is not listed
unless the census finds one. Until PR 13 a bundle the Ruby policy rejects is
retried through `gh`, so a ref missing from the list costs a retry, not an
install.

## Design decisions

1. Use the official `sigstore` gem, vendored and pinned to an exact
   version. No hand-written cryptography: gaps are fixed upstream. It is
   required lazily, only when a bundle is verified.
2. Verification is always offline. The bundle carries its own Rekor proof
   and the trusted root is pinned in the repository, so installs make no
   Rekor, Fulcio, TUF or GitHub API request. A Sigstore or GitHub API outage
   can only stop publishing.
3. GitHub Packages is the only client-side source. The bundle travels as
   an annotation in the bottle's per-platform manifest, and the client
   fetches that manifest by digest in place of the index it fetches today,
   so verification adds no request and the download shrinks. Homebrew
   already carries multi-KB JSON that way (`sh.brew.tab`). The digest
   comes from the signed JSON API; a client without one starts from the
   digest in the bottle block and fetches the index first. Both digests
   are mandatory for Homebrew/core bottles and optional for third-party
   taps.
4. Performance is a design constraint, not a later optimisation: no extra
   request for API installs and one, overlapping the bottle download, for
   clients that start from a bottle block; none on a cache hit; and added
   wall-clock that does not grow with the number of bottles installed in
   parallel. A client downloads only its own platform's copy of a bundle
   and cryptographically verifies each distinct bundle once per process,
   however many bottles it covers.
5. Publish bundles where they are created. `brew pr-upload` receives the
   bundle from `actions/attest` and uploads it with the bottle, before the
   bottle commit lands, so no bottle is installable before its bundle is
   retrievable. The attestation API is used once, by an authenticated job
   that mirrors bundles for bottles already published.
6. The same verifier and policy run at publish time and at install time.
   Nothing is published or mirrored that a client would reject, so policy
   or trusted root drift breaks a publishing job, not users.
7. Bundles are untrusted wherever they come from, including the cache, and
   are fully verified on every use. Content addressing is for integrity and
   caching convenience, never for trust.
8. Identity is tighter than `gh --repo`: workflow allow-list, ref, numeric
   repository and owner IDs and hosted runners.
9. Every PR is small, independently mergeable and behaviour-neutral for
   users who have not opted in, until the rollout PRs. The existing opt-in
   keeps working throughout for Homebrew/core: the `gh` path is removed
   only once the new path covers every Homebrew/core bottle.
10. Rollout gates are measured by Homebrew's own CI and a catalogue sweep,
    not by new user telemetry. A failed gate holds the rollout at its stage
    rather than weakening verification.
11. `HOMEBREW_NO_VERIFY_ATTESTATIONS` already exists and is the opt-out at
    every stage. From PR 5 every fatal verification message names it as the
    workaround, until the stable stage has soaked, and specs prove it is
    honoured on every path.
12. Third-party taps are a stretch goal, left to the final PRs (21 and 22)
    so nothing else waits for them. Their manifests are pinned regardless:
    `brew pr-upload` writes `manifest_sha256` for every tap, and a pinned
    manifest's bundle cannot be removed on the registry side. Attestation
    stays opt-in for a tap, but how a tap opts in is left to PR 21. The
    digest cannot be the signal, as every tap that uploads gets one. The
    aim is that existing taps gain attestations with nothing asked of
    their authors, or failing that by default from the `brew tap-new`
    workflows, and that a tap's workflow is checked for that logic to tell
    whether its bottles must verify. Bundles are verified against the
    tap's own repository as today and there is no API fallback. A
    published bundle that does not verify is fatal. Until a tap is known
    to attest, a bottle with no bundle is not verified and does not fail,
    and a block with no digest is fetched by tag, so its bundle can be
    removed unnoticed: an accepted risk in the threat model above.
13. Only bottles of current formula versions matter. Superseded versions
    are neither mirrored nor counted in coverage.

### Distribution format

Chosen on 13 November 2026, with GitHub Packages behaviour still to be
confirmed by PR 7: the bundle is an annotation on the bottle's
per-platform manifest, and the client fetches that manifest alone.

- `brew pr-upload` writes each bottle's bundle into its per-platform
  manifest, not the index, and the digest of the index into the bottle
  block.
- The API generator writes the digest of each platform's manifest, as
  `bottle_manifest_checksum` beside `bottle_checksum`, in that platform's
  file
  (`api/internal/packages.<tag>.jws.json`), which already holds exactly
  one bottle checksum per formula. It holds no manifest digest today.
- A client installing from the API fetches its per-platform manifest by
  that digest, checks the bytes against it and reads its tab and bundle
  from that one file. It never fetches the index.
- A client with no API digest (a tap checkout under
  `HOMEBREW_NO_INSTALL_FROM_API`, or a third-party tap) fetches the index
  by the bottle block's digest, checks it and then fetches the
  per-platform manifest the index lists, beside the bottle download.
- A bottle with neither digest, which once PR 11 is complete can only be
  a third-party tap's, is fetched by tag as today.

The options compared, with the letters used while choosing. C was chosen:

| Option | Where the bundle lives | Extra requests per bottle | Bottles already published |
|---|---|---|---|
| A | Annotation in the bottle index, stored once per bundle | 0 | index rewritten once |
| C | Annotation on the bottle's per-platform manifest, fetched by digest in place of the index | 0 | new platform manifest and index rewritten once |
| E | As C, with the index still fetched first | 1 | as C |

Three more were discarded earlier:

- B embedded a standard OCI 1.1 artifact manifest in the index through
  `data`. It cost 1.8 times A's bytes, no existing tool reads a bundle
  there and an artifact has one `subject` where a Homebrew bundle covers
  many bottles.
- D put the bundle behind the standard referrers tag
  `sha256-<platform manifest digest>`. It leaves existing indexes alone
  and standard tools can list the bundles, though not verify them, as
  they expect the attested subject to be the image and not the bottle
  tarball. But the tag is mutable and outside the manifest digest pin, so
  a bundle can be removed unnoticed, a bottle can be published without
  one, every bottle tag adds a tagged package version that clutters the
  package page and is left behind on deletion, and it needs a request per
  bottle.
- A plain referrers chain of tag, artifact manifest and blob needs two or
  three requests per bottle.

Sizes in KB of what a client on `arm64_golden_gate` downloads per package,
measured on 13 November 2026 with exact bundles for these packages:

| Package | Bottle tags | Bundles | Index today | A: index | C: platform manifest | E: both |
|---|---|---|---|---|---|---|
| `hello` | 6 | 2 | 15.3 | 45.1 | 14.9 | 15.3 + 14.9 |
| `figlet` | 13 | 13 | 18.9 | 164.8 | 14.6 | 18.9 + 14.6 |
| `openssl@3` | 5 | 1 | 20.3 | 33.6 | 17.7 | 20.3 + 17.7 |
| `wget` | 5 | 1 | 58.1 | 70.7 | 22.6 | 58.1 + 22.6 |
| `git` | 5 | 1 | 88.4 | 100.9 | 20.6 | 88.4 + 20.6 |
| `python@3.14` | 5 | 1 | 108.0 | 122.4 | 35.0 | 108.0 + 35.0 |
| `node` | 5 | 1 | 151.1 | 163.7 | 40.3 | 151.1 + 40.3 |
| `ffmpeg-full` | 5 | 1 | 631.4 | 648.1 | 127.9 | 631.4 + 127.9 |

`brew install ffmpeg-full` needs 103 packages: 682 bottle tags, 260
distinct bundles and 228 MB of bottles for this machine. Its manifests
total 4.5 MB today, 7.7 MB under A, about 2.0 MB under C and 6.5 MB under
E, which also makes 103 more requests. Bundles for the 95 packages not
named above are modelled at 10.9 KB plus 195 bytes per extra subject,
which was 3% low on average against ten exact bundles.

The whole download flow was timed against GitHub Packages as the download
queue runs it: every manifest first, then every bottle, each request its
own `curl` process on a pool of twice the core count, with E's
per-platform manifest queued on the same pool beside its bottle. C was
not part of this run. Files that do not exist yet were
stood in for by real manifests of the nearest size. Medians:

| Workload | Pool | Today | A | E |
|---|---|---|---|---|
| `hello` alone, 55 KB (25 runs) | n/a | 0.52 s | +16 ms | +0 ms |
| `wget` alone, 1.6 MB (25 runs) | n/a | 0.62 s | +8 ms | +4 ms |
| 30 smallest bottles of the chain, 4 MB (9 runs) | 36 | 0.74 s | +0.12 s | +0.26 s |
| Same | 16 | 1.19 s | +0.07 s | +0.49 s |
| 70 smallest bottles, 31 MB (5 runs) | 36 | 1.48 s | +0.05 s | +0.39 s |
| All 103, 228 MB (3 runs) | 36 | 4.27 s | +0.49 s | +0.14 s |

For one package E is free, as its extra request overlaps the bottle
download. For many packages A is faster, because E's extra requests take
slots in the pool, and more so on a machine with fewer cores. The full
chain is within noise: two identical bottle phases differed by 0.3 s. On
a slow connection A's extra bytes count for more: the chain's 1.2 MB
difference is half a second at 20 Mbit/s. A real
`brew fetch --force` of the same 103 packages took 65 to 104 s, so either
option is under 1% of the command.

Only the official client matters, and not older versions of it once a
stable tag supports the new layout. That changes C. The per-platform
manifest already carries every annotation the client reads from the index,
with identical values, because `GitHubPackages#upload_bottle` writes them
to both: 83% of the chain's platform manifest bytes are such copies. So a
client that knows its platform manifest's digest can skip the index and
fetch that one file: its own tab and its own bundle. That is C. E keeps
the index: the client fetches it as today, then its per-platform manifest
for the bundle, beside the bottle download.

A random sample of 420 packages, as fetched by a client on
`arm64_golden_gate`, split by how many bundles a package's bottles have.
Timings are the whole download, every manifest and then every bottle, for
30 packages of each group and for one package of median size, each request
its own `curl` process. Medians of 12 runs of each manifest phase, 7 of
each bottle phase and 15 for one package.

Normal, 1 to 4 bundles (84% of packages, median bottle 1.8 MB):

| | Today | A | C | E |
|---|---|---|---|---|
| Manifest requests per package | 1 | 1 | 1 | 2 |
| Manifest download per package, median | 18.1 KB | 41.3 KB | 16.5 KB | 33.2 KB |
| All manifest bytes against today | | +25% | -52% | +48% |
| Change as a share of manifest plus bottle, median | | +0.8% | 0% | +1.2% |
| 30 packages, pool of 36 | 0.95 s | -7 ms | -71 ms | +64 ms |
| 30 packages, pool of 16 | 1.22 s | +9 ms | -63 ms | +421 ms |
| One package alone | 0.55 s | +8 ms | -10 ms | -8 ms |

Many, 5 or more bundles (16%, median bottle 146 KB):

| | Today | A | C | E |
|---|---|---|---|---|
| Manifest requests per package | 1 | 1 | 1 | 2 |
| Manifest download per package, median | 18.7 KB | 165.0 KB | 14.5 KB | 33.1 KB |
| All manifest bytes against today | | +564% | -27% | +73% |
| Change as a share of manifest plus bottle, median | | +84% | -2.5% | +9.0% |
| 30 packages, pool of 36 | 0.75 s | +132 ms | -12 ms | +155 ms |
| 30 packages, pool of 16 | 1.21 s | +174 ms | -16 ms | +376 ms |
| One package alone | 0.51 s | +23 ms | -14 ms | -21 ms |

Single runs of a phase varied by up to a factor of two, so differences
under about 0.1 s for 30 packages are noise. Against a real
`brew fetch --force hello` at 0.65 s, one package alone is within 4% for
every option. `brew install` could not be run in the measuring sandbox;
it adds pouring, so shares of a whole install are smaller still.

- C is smaller and no slower than today for both groups.
- A matches today for the 84% and costs 0.13 to 0.17 s per 30 packages of
  the 16%, whose manifests grow ninefold because every bottle has its own
  bundle. Across the catalogue it adds a mean 37 KB per package.
- E costs nothing for one package, as its second request overlaps the
  bottle, and 0.06 to 0.42 s per 30 packages, more on a smaller pool, as
  those requests take slots beside the bottles.
- A variant of E was measured and rejected: moving the tabs out of the
  index, so that it shrinks to a median 3.7 KB, cuts E to 20.3 and
  24.4 KB per package, but the tab then needs two requests one after the
  other. One package alone took 0.18 s longer (+33%) and 30 packages were
  no faster than E.

What each would cost to build:

- A: one annotation written by `write_image_index` and read from the
  index the client already fetches.
- E: the bundle written into the per-platform manifest by
  `GitHubPackages#upload_bottle`, a second manifest download per bottle
  and, for every bottle already published, a new per-platform manifest
  and a new index listing it.
- C: as E, with the second download only for clients that start from the
  block, plus the API generator deriving a per-platform digest from each
  pinned index, `Resource::BottleManifest` reading a per-platform
  manifest as well as an index and
  `brew info --github-packages-downloads` reading counts that move to the
  per-platform manifests.

C was chosen because it is the smallest and fastest for both groups, keeps
one digest per bottle block and stops the same attackers as A and E (see
the bottle manifest digest below). It costs the most code, with a second
client path for those that start from the block, and makes API generation
fetch indexes from the registry, as it already fetches the executables
database. A's single path and least code would have been paid for in
bytes, most of them in the 16%. E as the only mode was not worth its
extra request: it beats A only where bandwidth, not requests, is the
limit, at about 20 Mbit/s or less by arithmetic, not measured.

Rejected: bundles in the signed JSON API. They would need no GitHub
Packages request at all, but the per-platform file every default install
downloads (`api/internal/packages.<tag>.jws.json`: 8,558 bottled formulae,
16.0 MB, 3.8 MB as served with gzip) would grow to about 114 MB, 35 MB
gzipped, and is downloaded whole whenever it changes. Simulated on the
real file with ten distinct real bundles.

What GitHub Packages is known to support on 13 November 2026:

- Multi-KB JSON annotations in indexes and per-platform manifests, which
  the bundle annotation relies on: Homebrew's own manifests carry them
  today.
- Fetching any manifest by digest, which the design relies on: checked
  for all 2,762 per-platform manifests of the 420 sampled packages.
- Not the native Referrers API, which returns 404 even for images that
  have referrers under the tag schema.
- GitHub documents a 10 GB layer limit and a ten minute upload timeout
  and nothing on manifest size; `GitHubPackages` already refuses indexes
  of 4 MB or more.

## Performance targets and rollout gates

Proposed numbers, to be agreed in review of this plan (PR 1). Benchmarks use
`brew benchmark` at the default download concurrency on a GitHub-hosted
runner and one residential connection.

| Target | Value |
|---|---|
| Requests on a valid cache hit | 0, required |
| Extra requests per bottle on a cache miss | 0 from the API, 1 from a bottle block |
| Manifest bytes downloaded, API install | fewer than today |
| Verification CPU per distinct bundle | at most 5 ms |
| Verifier load, once per process and never at startup | at most 100 ms |
| Mean added wall-clock, cold `brew install hello` | at most 50 ms, ideally within noise |
| Mean added wall-clock, cold 20-bottle install | no more than for one bottle |
| Mean added wall-clock, cached bottle and bundle | at most 10 ms |
| Commands that pour no bottles | no measurable change |

| Stage | Gate to enter it |
|---|---|
| Opt-in (week 10) | PRs 2 to 17 in a stable tag; every tamper and outage test passes; targets above met |
| Developers (week 11) | Catalogue sweep: 100% of current bottles have manifest digests in the formula and the API and a retrievable, valid bundle on two consecutive days; no false rejection in Homebrew/brew or Homebrew/core CI for seven days |
| Unstable (week 12) | Same, plus no unresolved developer report and first-attempt bundle retrieval at least as reliable as bottle retrieval |
| Stable (week 13) | Same over the unstable stage, plus offline reinstall from cache verified, trusted root canary green and mirrors documented |

## Plan

| PR | Repository | Week | Summary |
|---|---|---|---|
| 1 | brew | 1 | This plan: threat model, policy, targets, gates and risks |
| 2 | brew | 1 to 2 | Done: `manifest_sha256` in `bottle do`, checked when present |
| 3 | brew, formulae.brew.sh | 2 to 3 | Done in brew: `bottle_manifest_checksum` in the API, fetched directly when present |
| 4 | brew | 2 | Done: `sigstore` gem vendored, off the load path until needed |
| 5 | brew | 2 | Verify bundles in Ruby, offline, against a pinned trusted root |
| 6 | brew | 3 | Enforce the trust policy |
| 7 | brew | 4 to 5 | GitHub Packages distribution experiment and format contract |
| 8 | brew | 6 | Publish bundles from `brew pr-upload` |
| 9 | brew | 6 | Write the manifest digest at upload |
| 10 | homebrew-core | 6 | Pass bundles to `brew pr-upload` |
| 11 | brew, homebrew-core | 6 | Mirror existing attestations, pin then require manifest digests, census and coverage |
| 12 | brew | 7 | Retrieve and verify through the download queue |
| 13 | brew | 7 | Remove the `gh`, token and API paths |
| 14 | brew | 8 | Offline cache |
| 15 | brew | 8 | Trusted root updates and canary |
| 16 | brew | 9 | Failure injection, `brew verify`, diagnostics and docs |
| 17 | homebrew-core | 9 | Catalogue sweep |
| 18 | brew | 11 | Default for Homebrew developers |
| 19 | brew | 12 | Default for unstable users |
| 20 | brew | 13 | Default for stable users |
| 21 | brew | stretch | Third-party tap policy and publishing |
| 22 | brew | stretch | Verify third-party tap bottles |

Adjacent PRs may merge where that keeps a change coherent. Week 10 ships no
new code: it tags a stable release and reviews the opt-in gate. PRs 21 and
22 are a stretch goal: they follow the stable stage if time remains and
nothing else depends on them.

### Manifest digests and verifier (weeks 1 to 3)

1. **This plan.** Review agrees the threat model, expected claims,
   performance targets, rollout gates and risk register.
2. **Manifest digest in `bottle do`.** Done: `manifest_sha256` holds the
   SHA-256 of the bottle's image index, one per bottle block. When it is
   present, `Bottle#github_packages_manifest_resource` fetches the index
   by that digest instead of by tag, `Resource::BottleManifest` checks the
   bytes and `Formula#bottle_hash` carries it for the API generator.
   `brew bottle --merge --write` drops it, as a changed block makes it
   stale, until PR 9 writes the new one. It must be in a stable release
   before homebrew/core uses it and may be absent until PR 11 requires it.
3. **Per-platform manifest digest in the API.** Done in brew: for every
   formula whose bottle block has a digest, `brew generate-internal-api`
   fetches the index by that digest through the download queue and writes
   the digest of each bottle's own manifest, as `bottle_manifest_checksum`
   beside `bottle_checksum`, in that platform's file. A missing or
   mismatched index fails the run. When the field is present,
   `Bottle#github_packages_manifest_resource` fetches that manifest by
   digest in place of the index and `Resource::BottleManifest` checks the
   bytes and that the manifest names the expected bottle. Older clients
   drop the field. Left to do: have the formulae.brew.sh workflow keep
   `HOMEBREW_CACHE/downloads/*.bottle_manifest.json` between runs, so a run
   fetches only new indexes.
4. **Vendor the `sigstore` gem.** Done: `sigstore` 0.3.0 (0.2.3 fixed
   in-toto statement verification, GHSA-mhg6-2q2v-9h2c) and its five
   `protobug*` gems are vendored from a Bundler group of their own,
   `attestation`, which `brew vendor-gems` leaves out of
   `vendor/bundle/bundler/setup.rb`. That file is unchanged, so the load
   path of every command is too, until PR 5 adds the gems when a bundle is
   verified. Ruby's default gems (`net-http`, `net-protocol`, `timeout` and
   `uri`) are not vendored: the copies in Homebrew's Ruby are used.
   Licences are Apache-2.0, MIT and Unlicense.
5. **Verify bundles in Ruby.** Add offline verification to
   `Homebrew::Attestation`: bundle JSON and bottle SHA-256 in, verified
   statement and signing time out, `InvalidAttestationError` otherwise.
   Put the six vendored gems' `lib` directories on the load path before
   requiring `sigstore`, and silence its debug logging. Parse bundle and
   trusted root JSON in Homebrew and decode it with `decode_json_hash`:
   `protobug` 0.2.0 passes `JSON.parse` options that `json` 3 rejects, and
   while Homebrew's Ruby bundles `json` 2.18.0, developers and CI load
   3.1.0 from the bundle.
   Check in the Sigstore trusted root next to the code (as
   `api/homebrew-1.pem` is) and build the verifier without a Rekor client so
   a stale root can never cause a request. Rescue both failure results and
   `Sigstore::Error`, and keep raw signature bytes out of messages. Specs
   use real fixtures for all four bundle kinds (`publish-commit-bottles`,
   `dispatch-build-bottle`, `dispatch-rebottle` and backfill), block sockets
   and cover tampered payloads, signatures, certificates, log entries and
   proofs. No install path calls it yet: bundles already in hand
   (`prefetched_bundles`) stay on `gh --bundle` until PR 6 enforces the
   repository identity that `gh --repo` checks today. Name
   `HOMEBREW_NO_VERIFY_ATTESTATIONS` in every fatal message in
   `utils/attestation.rb` (none mentions it today) and add specs that it
   disables verification on every path.
6. **Enforce the trust policy.** Implement the expected claims table as the
   gem's certificate policy plus statement checks, and cross-check the
   signed digest against the formula checksum as well as the file. Only
   then verify bundles already in hand in Ruby instead of `gh --bundle`, so
   no release accepts a bundle that `gh --repo` rejects; `gh` stays for the
   online lookup until PR 13. Specs cover a bundle for another bottle,
   another platform or an older version of the same formula, a fork,
   another branch or workflow of Homebrew/homebrew-core, a self-hosted
   runner, a wrong issuer, a renamed repository with a different ID, a
   backfill bundle after the cutoff and the `:all` naming rule.

### Distribution (weeks 4 to 6)

7. **Distribution experiment and format contract.** The read-only
   measurements are above; what is left needs a token. In a scratch GitHub
   Packages namespace, push per-platform manifests carrying a bundle as an
   annotation and an index that lists them. Confirm that each is served
   byte for byte by digest, that older clients reading the index by tag
   are unaffected and that rewriting a published bottle's manifests
   changes nothing else. Test whether the existing `skopeo` flow can push
   them, what happens to superseded manifests that no tag reaches and how
   GitHub Packages counts downloads of a per-platform manifest and of an
   index fetched by digest. Check behaviour through an OCI pull-through
   proxy as used with `HOMEBREW_ARTIFACT_DOMAIN`. Record the results and
   the contract (annotation keys, lookup algorithm and limits) here. No
   production code.
8. **Publish bundles from `brew pr-upload`.** Add an option taking the
   `actions/attest` bundle file. `GitHubPackages#upload_bottle` matches
   bundles to bottles by SHA-256, verifies each under the client policy and
   writes each bottle's bundle as an annotation on its per-platform
   manifest only, not on the index entry that otherwise repeats the same
   annotations. With the option set, a bottle without a valid bundle fails
   the upload. `--keep-old` leaves the manifests of the bottles it keeps
   untouched and `--dry-run` prints the plan. Specs validate the generated
   manifests against the OCI schemas `load_schemas!` already fetches. The
   option is not specific to Homebrew/core but the client policy is, so
   every other tap's bundles fail the upload until PR 21 adds a tap's own
   policy.
9. **Write the manifest digest at upload.** Once PR 2 is in a stable
   release, have `brew pr-upload` build the index before
   `brew bottle --merge --write` writes the bottle block, so the block
   carries the digest of the index about to be pushed, including under
   `--keep-old`. It does so for every tap, with or without bundles, so
   manifests are pinned whether or not a tap attests. Specs cover the
   generated block and that the digest matches what is uploaded.
10. **Pass bundles to `brew pr-upload`** in the three Homebrew/core signing
    workflows by giving the attest step an ID and passing its `bundle-path`
    output.
11. **Mirror existing attestations.** Move `bulk_list_bundles` from the
    client path to the publishing side with bounded retries, back-off and
    rate-limit handling, and add a way to publish a bundle for a bottle
    that is already uploaded: pushing a new per-platform manifest that adds
    the bundle and a new index that lists it, and checking that nothing
    else changed. A `workflow_dispatch` and scheduled Homebrew/core
    workflow walks every current bottle, skips those with a valid bundle,
    fetches the rest from the Homebrew and backfill repositories, verifies
    each under the client policy and publishes it. It starts with a
    handful of formulae, pins each new index's digest in the formula's
    bottle block in the same pass, is idempotent and resumable and reports
    a census (signer identities, bundle formats, log entry kinds and bundle
    sizes) and coverage. Bottles with no valid attestation, e.g. any
    published between the backfill cutoff and the first signed publish, are
    rebottled until the list is empty. Once every current bottle is pinned,
    `brew audit` requires the digest in Homebrew/core bottle blocks and
    `brew generate-internal-api` fails on a Homebrew/core bottle without
    one.

### Client (weeks 7 to 9)

12. **Retrieve and verify through the download queue.**
    `Resource::BottleManifest` exposes the bottle's bundle from its
    per-platform manifest. A client that fetched that manifest directly
    (PR 3) already has it. One that started from the index fetches the
    per-platform manifest the index lists beside the bottle, checked
    against the listed digest, using `CurlGitHubPackagesDownloadStrategy`,
    so anonymous access, `HOMEBREW_ARTIFACT_DOMAIN` rewriting and the
    GitHub Packages fallback for legacy mirrors behave as they do for
    manifests. In `DownloadQueue`, verification becomes a future joined on
    bottle and manifest, replacing the inline `check_bottle_attestation`
    call and shown as the bottle's `:verifying` phase. Verified bundles are
    memoised by digest for the process. The `Attestation.prefetch` call
    sites go. Until PR 13, a bottle with no published bundle falls back to
    the `gh` path. `brew info --github-packages-downloads` reads
    per-platform counts where clients no longer fetch the index, as PR 7
    found them to be counted. The commit message carries cold and warm
    `brew benchmark` output for one-bottle and 20-bottle installs,
    comparing the direct manifest fetch of PR 3 with the index fetch.
13. **Remove the `gh`, token and API paths** once the mirror reports full
    coverage: `gh_executable`, `sort_formulae_for_install` and its three
    callers, `prepare_attestation_verification!`, `prefetch` and its
    helpers, the `Gh*` and rate-limit errors and their messages, the `gh`
    exemptions in `FormulaInstaller` and test-bot and the retry loop
    (network retries belong to `RetryableDownload`; an invalid bundle is
    deterministic). Update the `HOMEBREW_VERIFY_ATTESTATIONS` description
    and regenerate the manpage and completions. This also ends the `gh`
    check of third-party tap bottles for users who opted in: they are not
    verified again until PR 22.
14. **Offline cache.** The cached per-platform manifest is the bundle
    cache. It is found without the network: by the API's digest or, for a
    client that starts from a bottle block, through the cached index that
    the block's digest identifies. Each is named by its digest so it cannot
    go stale and written atomically with owner-only permissions. Every read
    is fully verified; an invalid entry is deleted and fetched again once,
    then fails closed. A missing bundle is never cached. `brew cleanup`
    removes a bottle's manifests, the index included, with the bottle, not
    before. A spec reinstalls from cache with the network disabled, both
    from the API and from a bottle block.
15. **Trusted root updates.** A scheduled Homebrew/brew workflow refreshes
    the pinned trusted root through the gem's TUF client and opens a PR on
    change. A daily canary verifies the newest Homebrew/core bundle against
    the pinned root, so a Sigstore rotation or GitHub's move to Rekor v2 is
    seen before users are affected. Document the rotation policy and the
    lead time stable tags need.
16. **Failure injection, `brew verify`, diagnostics and docs.** Specs for
    modified, missing, replayed and stale manifests, annotations,
    blobs and cache entries, and for registry outages, timeouts and rate
    limits. Rewrite `brew verify` on the new path. Make every failure
    message say what failed and what to do. Update
    `docs/Homebrew-Security-and-Supply-Chain.md`, including
    `HOMEBREW_NO_INSTALL_FROM_API` as the setting for environments that do
    not want to trust the API, and document the distribution contract for
    mirror operators in `docs/Bottles.md`.
17. **Catalogue sweep.** A daily Homebrew/core workflow retrieves and
    verifies the bundle for every current bottle anonymously through the
    client path on macOS and Linux runners, and reports coverage, failures
    and retrieval latency. It also derives every per-platform manifest
    digest again from the tap and the registry and compares it with the
    published API. It measures the rollout gates and stays as the monitor
    afterwards.

### Rollout (weeks 10 to 13)

18. **Default for Homebrew developers:** `HOMEBREW_DEVELOPER` implies
    verification.
19. **Default for unstable users:** every checkout that is not on a stable
    tag.
20. **Default for stable users:** everyone. `HOMEBREW_VERIFY_ATTESTATIONS`
    becomes redundant, `HOMEBREW_NO_VERIFY_ATTESTATIONS` stays, and the
    documentation and `.oss-scanner/threat_model.md` stop describing
    verification as configuration-dependent.

Each rollout PR quotes the gate results it relies on and is reverted, not
weakened, if a regression appears.

### Third-party taps (stretch)

21. **Third-party tap policy and publishing.** Add a tap's own policy to
    the verifier: signed by the repository the tap's remote names, which
    `Attestation.check_formula_attestation` already derives. `brew pr-upload`
    verifies a third-party tap's bundles under it, as PR 8 does under
    Homebrew/core's, so nothing is published that PR 22 would reject. Get
    bundles published with as little asked of tap authors as possible.
    Preferred, and untested: existing taps need no change, because
    `brew pr-upload` attests the bottles itself wherever the job can
    request an OIDC token, which the `id-token: write` permission of
    today's `brew tap-new` publish workflow allows. Otherwise the
    `brew tap-new` workflow template attests before uploading and passes
    the bundle by default. Settle here what marks a tap as attesting (see
    the open questions) and document it and the distribution contract for
    tap authors in `docs/Bottles.md`.
22. **Verify third-party tap bottles.** Read a tap bottle's bundle from
    its manifest and verify it under PR 21's policy. A bundle that does
    not verify is fatal, as is a manifest that does not match the block's
    `manifest_sha256`. A bottle with no bundle fails only if PR 21's
    signal says its tap attests; otherwise it is not verified and does not
    fail. Specs cover a bundle removed from a manifest fetched by tag, a
    pinned manifest with no bundle from a tap that attests and from one
    that does not, a bundle from another repository and a tap with a
    custom remote.

### Bottle manifest digest

Mandatory for Homebrew/core and part of the distribution design: PR 2 adds
the DSL and the check of the index, PR 3 the per-platform digest in the
API and the direct fetch, PR 9 writes digests at upload and PR 11 pins
existing bottles in bulk and then requires a digest in every Homebrew/core
bottle block. Third-party taps get digests from `brew pr-upload` too,
whether or not they attest, but are not required to have them.

The bottle index is fetched through a mutable tag with no expected digest,
so whoever controls the registry, a mirror or the tag can alter it. They
cannot make a different bottle verify, but the index's copy of the tab
steers decisions made before the bottle is downloaded: runtime dependency
resolution (`FormulaInstaller#determine_bottle_tab_attributes`), whether
the bottle may pour at this prefix (`Bottle#compatible_locations_from_tab?`)
and whether it is relocated (`Bottle#skip_relocation?`). The build revision
and SBOM annotations are equally unsigned.

The fix is one digest per bottle block, as one index lists every
platform's bottle, from which every manifest a client reads is checked.
The attribute is `manifest_sha256`:

```ruby
bottle do
  rebuild 1
  manifest_sha256 "c847599789efade500c448e8b302fc9a3f985e1e4370e91b339b839b2205d984"
  sha256 cellar: :any_skip_relocation, arm64_golden_gate: "4dd2596c2e89..."
  sha256 cellar: :any_skip_relocation, arm64_tahoe:       "ae6237e3001b..."
  sha256                               x86_64_linux:      "ab40f4006173..."
end
```

One digest covers several files because each file names the next by
SHA-256: the index lists the digest of every per-platform manifest, and
each per-platform manifest holds its tab, sizes and SBOM inline and lists
its bottle's digest. Checked on 420 sampled packages: all 2,762
per-platform manifests hash to the digest their index lists, repeat every
annotation `Resource::BottleManifest` reads with the same value and list
the bottle named by `sh.brew.bottle.digest`. The tap commit a manifest
records (`org.opencontainers.image.revision`) is the one the bottle was
built from, not the one that adds the bottle block, so a digest in the
block is not circular.

- It covers the whole index and, through the per-platform digests the
  index lists, every platform's tab, SBOM, sizes, build revision and
  bundle, with the trust that already covers bottle checksums: a reviewed
  commit and the signed JSON API.
- It needs no extra request and no Sigstore, so it holds even where
  attestation verification is disabled.
- Fetched by digest, a manifest is immutable. It can be cached for ever
  and cannot go stale, and a later rewrite by `--keep-old` or the mirror
  never breaks a client with older metadata, as GitHub Packages keeps
  superseded indexes as untagged versions.
- A registry cannot strip the bundle of a tap bottle whose block has the
  digest.

Its costs:

- It changes the formula DSL and everything that reads or writes bottle
  blocks: `BottleSpecification`, `brew bottle --merge --write`,
  `Formula#bottle_hash`, the JSON API and its internal structs, the bottle
  RuboCops and the documentation.
- The DSL must be in a stable brew release before homebrew/core uses it:
  an older client reading formula files, rather than the API, fails on
  an unknown `bottle do` method. Hence PR 2 comes first.
- `brew pr-upload` must build the index before it writes and commits the
  bottle block. Today it commits first and builds the index while
  uploading.
- Every index rewrite needs a formula commit with the new digest. In
  normal operation indexes only change when `brew pr-upload` adds
  bottles, which already commits. The exception is the one-off mirror in
  PR 11.
- A pinned index missing from the registry, e.g. after a clean-up of
  untagged package versions, fails that formula for everyone.
- Digests do not compress. The per-platform internal API grows from
  16.0 to 16.9 MB, 3.8 to 4.2 MB as served with gzip, and
  `api/formula.jws.json` from 34.8 to 35.5 MB, 5.2 to 5.6 MB gzipped.

What a tampered manifest can do, from the code that reads it: change the
minimum dependency versions a bottle demands, so an outdated dependency
is left in place or a dependent is not upgraded
(`FormulaInstaller#expand_dependencies_for_formula_once`, `upgrade.rb`);
claim a different build prefix, so a bottle is refused and built from
source or poured with the wrong relocation; put false data in the
installed SBOM; and remove the bundle of a tap bottle fetched by tag so
it installs unverified. No path from it to running attacker code was
found: the bottle itself stays covered by its checksum and attestation.

Who can tamper, and what a checked digest stops. The registry side is
GitHub Packages and its CDN, a mirror or pull-through proxy, a network
attacker and any holder of a token with package write access, which
every publishing workflow has. Today it can alter any manifest.

| Attacker | Chosen: per-platform digest from the API | Index digest from the API (A or E) | Digests from a tap checkout |
|---|---|---|---|
| Registry side | stopped | stopped | stopped |
| API signing key or API generator | substitutes a manifest | substitutes a manifest | not in the path |
| Commit access to the tap | substitutes a manifest | substitutes a manifest | substitutes a manifest |
| Fault in the generator's derivation | install fails | cannot happen | cannot happen |

A client that reads its digests from the API gains nothing by also
fetching and checking the index: both digests come from the same signed
file, which already supplies the bottle checksum and the checksum of
formula source the client runs. So the chosen design is as strong as
checking the index for those clients. Checking the index helps only when
its digest comes from somewhere else, the tap checkout, and that takes
the API out of the path for every checksum, not just this one.
`HOMEBREW_NO_INSTALL_FROM_API` is therefore the setting for sensitive
environments, and no new one is needed. It trades trust in the API
signature for trust in the tap's Git hosting, as brew does not verify
commit signatures.

How the chosen design uses the digest:

- The API generator fetches each index by its pinned digest, checks it
  and writes each platform's manifest digest into that platform's signed
  API file. It fails on a mismatch, and the catalogue sweep derives the
  digests again independently.
- A client installing from the API checks its per-platform manifest
  against the API digest and that it names the bottle checksum it
  expects.
- A client with no API digest fetches the index by the block's digest,
  then the per-platform manifest it lists, checking both.
- Existing bottles are pinned in the same pass that adds their bundles,
  because a bundle changes the per-platform digests the index lists.
- GitHub Packages counts downloads per manifest. Clients fetch the tagged
  index today, so counts are per formula version. Fetching the index by
  digest should not change that; fetching only per-platform manifests
  moves the counts to those untagged manifests and gives per-platform
  counts for the first time. PR 7 confirms both on a test package and
  PR 12 then updates `brew info --github-packages-downloads` to read them.

Considered instead of the DSL change:

- one manifest digest per platform in the block, which lets every client
  check the block's own value in one request with no derivation,
  but puts 53,752 digests in homebrew/core where one per formula is 8,724
  and adds about 2.5 MB to gzipped `api/formula.jws.json`, scaled from
  the one-digest measurement above;
- sign the tab: add each bottle's tab digest as a further subject of the
  attestation Homebrew already creates, and have the client require a
  signed subject matching the `sh.brew.tab` it was served. No extra
  request and no formula or API change, but it covers the tab only, and
  only bottles attested after the change;
- attest the index digest, which needs no API or formula change but one
  more request, since an index cannot contain its own attestation.

## Risks

| Risk | Mitigation |
|---|---|
| GitHub Packages limits manifest annotations or removes manifests that no tag reaches | PR 7 tests both before the format is fixed; an annotation uses only what `sh.brew.tab` already relies on, and a current bottle's per-platform manifest is always listed by a tagged index |
| Rewriting the manifests of every current bottle breaks installs | PR 11 adds only the bundle, compares everything else before and after, starts with a handful of formulae and is resumable |
| Some current bottles have no valid attestation | PR 11 census and coverage report; rebottle until none remain; the developers gate needs 100% |
| A Sigstore key rotation or GitHub's move to Rekor v2 outpaces stable tags | PR 15 refresh and canary; Sigstore's trusted root already lists the Rekor v2 log; gem 0.3.0 verifies Rekor v2 entries but DSSE on Rekor v2 needs a fixture as soon as one exists |
| The gem is young (0.x, one in-toto advisory) and reports failures both as results and exceptions | Exact pin, reviewed bumps, fail-closed wrapper, real and tampered fixtures, upstream fixes rather than patches |
| `protobug` 0.2.0 cannot decode JSON where `json` 3 is loaded: developers and CI today, everyone once Homebrew's Ruby bundles it | PR 5 parses JSON itself and its specs run under the bundle's `json`; report it upstream and drop the workaround once a fixed release is pinned |
| API generation fails when GitHub Packages is unreachable or a pinned index is missing | Indexes are cached by digest, so a run fetches only new ones; a failed run leaves the previous API published; generation already depends on GitHub Packages for the executables database |
| The API carries a wrong per-platform digest | Installs fail closed, as the client checks the manifest names its bottle; the generator fails on any mismatch and the sweep derives the digests again daily |
| Download counts move from the index to per-platform manifests | PR 7 confirms how GitHub Packages counts them and PR 12 updates `brew info --github-packages-downloads` to match |
| Mirrors and proxies do not serve bundles | They travel in a manifest, which a mirror already has to serve; PR 7 tests a proxy by digest; contract documented before the stable gate |
| Slow links or `HOMEBREW_DOWNLOAD_CONCURRENCY=1` regress | Benchmarked in PR 12; API installs download fewer manifest bytes than today and nothing on a cache hit |
| GitHub Packages throttles anonymous requests | No extra request for API installs; the sweep measures retrieval reliability against bottle retrieval |
| A bug or stale trusted root on Homebrew's side makes valid bottles fail for everyone once this is the default | Publish-time verification, canary and sweep catch it first; messages name `HOMEBREW_NO_VERIFY_ATTESTATIONS`; each stage reverts with one PR |

## Open questions

- Should a legacy `HOMEBREW_BOTTLE_DOMAIN` mirror that cannot reach GitHub
  Packages fail closed at default-on, or must its operator mirror bundles or
  opt out?
- What marks a third-party tap as attesting, so that a bottle of its with
  no bundle fails? Not `manifest_sha256`, which every tap that uploads
  gets. Candidates are the attestation logic in the tap's publishing
  workflow, which `brew tap-new` would include by default, and
  `brew pr-upload` attesting by itself so that existing taps need no
  change. PR 21 decides.
- Should the `gh` check of third-party tap bottles, which users who opted
  in get today, outlive PR 13 until PR 22 replaces it? The plan removes it
  with the rest of the `gh` path.
- Are Homebrew's CI and the catalogue sweep enough to judge the gates, or is
  an anonymous analytics event for verification failures wanted?
- For a bottle with no valid attestation, is rebottling always acceptable or
  is a one-off, separately allow-listed re-attestation workflow needed? It
  could also retire the backfill special cases from the client, at the
  price of Homebrew re-signing bottles it did not publish under that
  identity.
- Is delivering the trusted root with `brew update` enough for stable users
  who update rarely, or should it also travel in the signed JSON API?

## Success criteria

- `brew install` verifies every Homebrew/core bottle by default with no
  `gh`, no token and no request to `api.github.com`.
- Every current Homebrew/core bottle has a valid bundle retrievable
  anonymously from GitHub Packages, proven daily by the sweep.
- An API install fetches one manifest per bottle, smaller than today's
  index and checked against a digest.
- Every current Homebrew/core bottle has a manifest digest in its formula
  and the API, enforced by `brew audit` and the API generator.
- A reinstall from cache verifies with the network disabled.
- The performance targets above hold in `brew benchmark`.
- Every tampering, replay, outage and identity test fails closed.
- `attestation.rb` no longer references `gh`, tokens or the attestation API
  on any install path.
