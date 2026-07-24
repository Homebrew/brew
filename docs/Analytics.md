---
last_review_date: "2026-07-18"
---

# Anonymous Analytics

Homebrew collects aggregate, anonymous usage analytics in InfluxDB.
Homebrew displays a notice before analytics are enabled so a user can opt out before sending an event.

## Purpose

The data helps maintainers prioritise widely used formulae, casks, commands and supported platforms.
It also shows where installation or build failures are concentrated and whether a feature is used enough to justify its maintenance cost.

Analytics must not replace technical evidence or maintainer judgement.
Low usage alone does not establish that removing a command or package is safe.

## Retention

Homebrew retains analytics events in InfluxDB for 365 days.
Public aggregate reports may cover shorter periods.

## Data sent

Formula, cask and build-error events can include:

- the package and non-private GitHub tap names
- selected install options
- whether the install was explicitly requested rather than installed as a dependency
- whether Homebrew is running in CI, developer mode or after a developer command has been used
- CPU architecture and operating system name or major version
- Homebrew version
- whether Homebrew uses its default prefix, with every other prefix reported only as `custom-prefix`

Command events include the command and option names after option values have been removed.
For selected common commands, Homebrew randomly samples one supported configuration variable and records its name and whether the user left it unset, set it to its default or set it to a non-default value; variables Homebrew exports itself (e.g. `HOMEBREW_EDITOR` from `EDITOR`) count as unset.
It does not record the variable's value.

BrewTestBot can send CI-only test-step results when its analytics setting is enabled.
Build-error events do not include build logs or exception details.

The analytics payload does not contain a user identifier or an IP-address field.
Homebrew does not use the payload to build a history for an individual user.

The current implementation is in [`analytics.rb`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/utils/analytics.rb) and [`analytics.sh`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/utils/analytics.sh).
These files are the authoritative source when this page and the implementation differ.

## Inspecting analytics

Set `HOMEBREW_ANALYTICS_DEBUG=1` for one command to print the analytics request and send it synchronously.
The server response is discarded, so no response output is shown.
Debug mode is not an opt-out mechanism; use one of the settings below when the request must not be sent.

Aggregate reports and their JSON representations are available from the [Homebrew analytics site](https://formulae.brew.sh/analytics/).
Most Homebrew maintainers have access only to these public aggregates.

## Transport and failure behaviour

Homebrew sends analytics to InfluxDB over HTTPS in a detached background process.
The request has a short timeout and failures are silent so analytics do not delay or prevent the requested Homebrew operation.

## Opting out

Disable analytics persistently with:

```sh
brew analytics off
```

Alternatively, set the environment variable:

```sh
export HOMEBREW_NO_ANALYTICS=1
```

Run `brew analytics state` to inspect the current setting.
