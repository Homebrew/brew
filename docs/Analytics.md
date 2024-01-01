# Anonymous Analytics

Homebrew gathers anonymous analytics using InfluxDB. You will be notified the first time you run `brew update` or install Homebrew. Analytics are not enabled until after this notice is shown, to ensure that you can [opt out](Analytics.md#opting-out) without ever sending analytics data.

## Why?

Homebrew is provided free of charge and run entirely by volunteers in their spare time. As a result, we do not have the resources to do detailed user studies of Homebrew users to decide on how best to design future features and prioritise current work. Anonymous analytics allow us to prioritise fixes and features based on how, where and when people use Homebrew. For example:

- If a formula is widely used and is failing often it will enable us to prioritise fixing that formula over others.
- Collecting the OS version allows us to decide which versions of macOS to prioritise for support and identify build failures that occur only on single versions.

## How Long?

Homebrew's anonymous analytics has a 365 day retention period in InfluxDB.

## What?

Homebrew's analytics record some shared information for every event:

- Whether the data is being sent from CI, e.g. `true` if the CI environment variable is set.
- Whether you are using the default install prefix (e.g. `/opt/homebrew`) or a custom one (e.g. `/home/mike/.brew`). If your prefix is custom, it will be sent as `custom-prefix` to preserve anonymity.
- Whether you are a Homebrew Developer, e.g. `true` if the `HOMEBREW_DEVELOPER` environment variable is set.
- Whether `devcmdrun` is set, e.g. `true` if you have ever run one of Homebrew's developer commands.
- Your CPU's architecture, e.g. `x86_64`.
- The OS you are using and its version number, e.g. `macOS 13`.
- The version of Homebrew, e.g. `4.0.0`.

All analytics data previously sent to Google Analytics has been destroyed.

Homebrew's analytics records the following different events:

- The `install` event category and the Homebrew formula from a non-private GitHub tap you install plus any used options (e.g. `wget --HEAD`) as the action. This allows us to identify which formulae where work should be prioritised, as well as how to handle possible deprecation or removal of any.
- The `install_on_request` event category and the Homebrew formula from a non-private GitHub tap you have requested to install (e.g. when explicitly named with a `brew install`) plus options. This allows us to differentiate the formulae that users intend to install from those pulled in as dependencies.
- The `cask_install` event category and the Homebrew cask from a non-private GitHub tap you install as the action. This allows us to identify which casks where work should be prioritised, as well as how to handle possible deprecation or removal of any.
- The `build_error` event category and the Homebrew formula plus options that failed to install as the action, e.g. `wget --HEAD`. This allows us to identify formulae that may need fixing. The details or logs of the build error are not sent.

You can also view all the information that is sent by Homebrew's analytics by setting `HOMEBREW_ANALYTICS_DEBUG=1` in your environment. Please note this will also stop any analytics from being sent.

It is impossible for the Homebrew developers to match any particular event to any particular user. We do not store or receive IP addresses.

## When/Where?

Homebrew's analytics are sent throughout Homebrew's execution to InfluxDB over HTTPS.

## Who?

Aggregates of analytics events are [publicly available](https://formulae.brew.sh/analytics/). A JSON API is also available. The majority of Homebrew maintainers are not granted more detailed analytics data beyond these public resources.

## How?

The code is viewable in [`analytics.rb`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/utils/analytics.rb) and [`analytics.sh`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/utils/analytics.sh). They are done in a separate background process and fail fast to avoid delaying any execution. They will fail immediately and silently if you have no network connection.

## Opting out

Homebrew analytics helps us maintainers and leaving it on is appreciated. However, if you want to opt out of Homebrew's analytics, you can set this variable in your environment:

```sh
export HOMEBREW_NO_ANALYTICS=1
```

Alternatively, this will prevent analytics from ever being sent:

```sh
brew analytics off
```
