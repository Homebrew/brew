---
last_review_date: "1970-01-01"
---

# Cask Cookbook

Each cask is a Ruby block, beginning with a special header line. The cask definition itself is always enclosed in a `do … end` block. Example:

```ruby
cask "anybar" do
  version "0.2.3"
  sha256 "c87dbc6aff5411676a471e84905d69c671b62b93b1210bd95c9d776d087de95c"

  url "https://github.com/tonsky/AnyBar/releases/download/#{version}/AnyBar-#{version}.zip"
  name "AnyBar"
  desc "Menu bar status indicator"
  homepage "https://github.com/tonsky/AnyBar"

  app "AnyBar.app"
end
```

* Table of Contents
{:toc}

## The cask language is declarative

Each cask contains a series of stanzas (or “fields”) which *declare* how the software is to be obtained and installed. In a declarative language, the author does not need to worry about **order**. As long as all the needed fields are present, Homebrew Cask will figure out what needs to be done at install time.

To make maintenance easier, the most-frequently-updated stanzas are usually placed at the top. But that’s a convention, not a rule.

Exception: `do` blocks such as `postflight` may enclose a block of pure Ruby code. Lines within that block follow a procedural (order-dependent) paradigm.

## Header line details

The Cask name ([`<cask-token>`](#token-reference)) on the header line `cask <cask-token> do` should match the cask filename, without the `.rb` extension, enclosed in double quotes.

There are currently some arbitrary limitations on cask tokens which are in the process of being removed. GitHub Actions will catch any errors during the transition.

## Stanza order

Having a common order for stanzas makes casks easier to update and parse. Below is the complete stanza sequence (no cask will have all stanzas). The empty lines shown here are also important, as they help to visually delimit information.

    version
    sha256

    language

    url
    name
    desc
    homepage

    livecheck

    deprecate!
    disable!

    auto_updates
    conflicts_with
    depends_on
    container

    suite
    app
    pkg
    installer
    binary
    manpage
    colorpicker
    dictionary
    font
    input_method
    internet_plugin
    keyboard_layout
    prefpane
    qlplugin
    mdimporter
    screen_saver
    service
    audio_unit_plugin
    vst_plugin
    vst3_plugin
    artifact, target: # target: shown here as is required with `artifact`
    stage_only

    preflight

    postflight

    uninstall_preflight

    uninstall_postflight

    uninstall

    zap

    caveats

Note that every stanza that has additional parameters (`:symbols` after a `,`) shall have them on separate lines, one per line, in alphabetical order. An exception is `target:` which typically consists of short lines.

## Stanzas

### Required stanzas

Each of the following stanzas is required for every cask.

| name                         | multiple occurrences allowed? | value |
| ---------------------------- | :---------------------------: | ----- |
| [`version`](#stanza-version) | no                            | Application version. |
| [`sha256`](#stanza-sha256)   | no                            | SHA-256 checksum of the file downloaded from `url`, calculated by the command `shasum -a 256 <file>`. Can be suppressed by using the special value `:no_check`. |
| [`url`](#stanza-url)         | no                            | URL to the `.dmg`/`.zip`/`.tgz`/`.tbz2` file that contains the application. A [comment](#when-url-and-homepage-domains-differ-add-verified) should be added if the domains in the `url` and `homepage` stanzas differ. Block syntax should be used for URLs that change on every visit. |
| [`name`](#stanza-name)       | yes                           | String providing the full and proper name defined by the vendor. |
| [`desc`](#stanza-desc)       | no                            | One-line description of the cask. Shown when running `brew info`. |
| `homepage`                   | no                            | Application homepage; used for the `brew home` command. |
| [`livecheck`](#stanza-livecheck)           | no                            | Ruby block describing how to find updates for this cask. Supersedes `appcast`. |
| [`depends_on`](#stanza-depends_on)         | yes                           | List of dependencies and requirements for this cask. |
| [`zap`](#stanza-zap)                       | yes                           | Additional procedures for a more complete uninstall, including user files and shared resources. |

### At least one artifact stanza is also required

Each cask must declare one or more *artifacts* (i.e. something to install).

| name                             | multiple occurrences allowed? | value |
| -------------------------------- | :---------------------------: | ----- |
| [`app`](#stanza-app)             | yes                           | Relative path to an `.app` that should be moved into the `/Applications` folder on installation. |
| [`suite`](#stanza-suite)         | yes                           | Relative path to a containing directory that should be moved into the `/Applications` folder on installation. |
| [`pkg`](#stanza-pkg)             | yes                           | Relative path to a `.pkg` file containing the distribution. |
| [`installer`](#stanza-installer) | yes                           | Describes an executable which must be run to complete the installation. |
| [`binary`](#stanza-binary)       | yes                           | Relative path to a Binary that should be linked into the `$(brew --prefix)/bin` folder on installation. |
| `manpage`                        | yes                           | Relative path to a Man Page that should be linked into the respective man page folder on installation, e.g. `/opt/homebrew/share/man/man3` for `my_app.3`. |
| `colorpicker`                    | yes                           | Relative path to a ColorPicker plugin that should be moved into the `~/Library/ColorPickers` folder on installation. |
| `dictionary`                     | yes                           | Relative path to a Dictionary that should be moved into the `~/Library/Dictionaries` folder on installation. |
| `font`                           | yes                           | Relative path to a Font that should be moved into the `~/Library/Fonts` folder on installation. |
| `input_method`                   | yes                           | Relative path to an Input Method that should be moved into the `~/Library/Input Methods` folder on installation. |
| `internet_plugin`                | yes                           | Relative path to an Internet Plugin that should be moved into the `~/Library/Internet Plug-Ins` folder on installation. |
| `keyboard_layout`                | yes                           | Relative path to a Keyboard Layout that should be moved into the `/Library/Keyboard Layouts` folder on installation. |
| `prefpane`                       | yes                           | Relative path to a Preference Pane that should be moved into the `~/Library/PreferencePanes` folder on installation. |
| `qlplugin`                       | yes                           | Relative path to a Quick Look Plugin that should be moved into the `~/Library/QuickLook` folder on installation. |
| `mdimporter`                     | yes                           | Relative path to a Spotlight Metadata Importer that should be moved into the `~/Library/Spotlight` folder on installation. |
| `screen_saver`                   | yes                           | Relative path to a Screen Saver that should be moved into the `~/Library/Screen Savers` folder on installation. |
| `service`                        | yes                           | Relative path to a Service that should be moved into the `~/Library/Services` folder on installation. |
| `audio_unit_plugin`              | yes                           | Relative path to an Audio Unit Plugin that should be moved into the `~/Library/Audio/Components` folder on installation. |
| `vst_plugin`                     | yes                           | Relative path to a VST Plugin that should be moved into the `~/Library/Audio/VST` folder on installation. |
| `vst3_plugin`                    | yes                           | Relative path to a VST3 Plugin that should be moved into the `~/Library/Audio/VST3` folder on installation. |
| `artifact`                       | yes                           | Relative path to an arbitrary path that should be moved on installation. Must provide an absolute path as a `target`. (Example: [free-gpgmail.rb](https://github.com/Homebrew/homebrew-cask/blob/b3c438d608d9702380edf10d5495e0727cf17108/Casks/f/free-gpgmail.rb#L44)) This is only for unusual cases; the `app` stanza is strongly preferred when moving `.app` bundles. |
| `stage_only`                     | no                            | `true`. Asserts that the cask contains no activatable artifacts. |

### Optional stanzas

| name                                       | multiple occurrences allowed? | value |
| ------------------------------------------ | :---------------------------: | ----- |
| [`uninstall`](#stanza-uninstall)           | yes                           | Procedures to uninstall a cask. Optional unless the `pkg` stanza is used. |
| [`conflicts_with`](#stanza-conflicts_with) | yes                           | List of conflicts with this cask (*not yet functional*). |
| [`caveats`](#stanza-caveats)               | yes                           | String or Ruby block providing the user with cask-specific information at install time. |
| [`deprecate!`](#stanza-deprecate--disable) | no                            | Date as a String in `YYYY-MM-DD` format and a String or Symbol providing a reason. |
| [`disable!`](#stanza-deprecate--disable)   | no                            | Date as a String in `YYYY-MM-DD` format and a String or Symbol providing a reason. |
| `preflight`                                | yes                           | Ruby block containing preflight install operations (needed only in very rare cases). |
| [`postflight`](#stanza-flight)             | yes                           | Ruby block containing postflight install operations. |
| `uninstall_preflight`                      | yes                           | Ruby block containing preflight uninstall operations (needed only in very rare cases). |
| `uninstall_postflight`                     | yes                           | Ruby block containing postflight uninstall operations. |
| [`language`](#stanza-language)             | required                      | Ruby block, called with language code parameters, containing other stanzas and/or a return value. |
| `container nested:`                        | no                            | Relative path to an inner container that must be extracted before moving on with the installation. This allows for support of `.dmg` inside `.tar`, `.zip` inside `.dmg`, etc. (Example: [blocs.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/b/blocs.rb#L17-L19)) |
| `container type:`                          | no                            | Symbol to override container-type autodetect. May be one of: `:air`, `:bz2`, `:cab`, `:dmg`, `:generic_unar`, `:gzip`, `:otf`, `:pkg`, `:rar`, `:seven_zip`, `:sit`, `:tar`, `:ttf`, `:xar`, `:zip`, `:naked`. (Example: [parse.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/p/parse.rb#L10)) |
| `auto_updates`                             | no                            | `true`. Asserts that the cask artifacts auto-update. Use if `Check for Updates…` or similar is present in an app menu, but not if it only opens a webpage and does not do the download and installation for you. |

## Stanza descriptions

### Stanza: `app`

In the simple case of a string argument to `app`, the source file is moved to the target `/Applications` directory. For example:

```ruby
app "Alfred 2.app"
```

by default moves the source to:

```bash
/Applications/Alfred 2.app
```

#### Renaming the target

You can rename the target which appears in your `/Applications` directory by adding a `target:` key to `app`. Example (from [scala-ide.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/s/scala-ide.rb#L24)):

```ruby
app "eclipse.app", target: "Scala IDE.app"
```

#### *target* may contain an absolute path

If `target:` has a leading slash, it is interpreted as an absolute path. The containing directory for the absolute path will be created if it does not already exist. Example (from [sapmachine-jdk.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/s/sapmachine-jdk.rb#L21)):

```ruby
artifact "sapmachine-jdk-#{version}.jdk", target: "/Library/Java/JavaVirtualMachines/sapmachine-jdk-#{version}.jdk"
```

#### *target* works on most artifact types

The `target:` key works similarly for most cask artifacts, such as `app`, `binary`, `colorpicker`, `dictionary`, `font`, `input_method`, `internet_plugin`, `keyboard_layout`, `prefpane`, `qlplugin`, `mdimporter`, `screen_saver`, `service`, `suite`, `audio_unit_plugin`, `vst_plugin`, `vst3_plugin`, and `artifact`.

#### *target* should only be used in select cases

Don’t use `target:` for aesthetic reasons, like removing version numbers (`app "Slack #{version}.app", target: "Slack.app"`). Use it when it makes sense functionally and document your reason clearly in the cask, using one of the templates: [for clarity](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/i/imagemin.rb#L10); [for consistency](https://github.com/Homebrew/homebrew-cask/blob/8be96e3658ff7ab66ca40723c3018fc5e35e3735/Casks/x-moto.rb#L16); [to prevent conflicts](https://github.com/Homebrew/homebrew-cask/blob/4472df441468e2aa657005550e2b951c2ef817f4/Casks/t/telegram-desktop.rb#L20); [due to developer suggestion](https://github.com/Homebrew/homebrew-cask/blob/ff3e9c4a6623af44b8a071027e8dcf3f4edfc6d9/Casks/kivy.rb#L12).

### Stanza: `binary`

In the simple case of a string argument to `binary`, the source file is linked into the `$(brew --prefix)/bin` directory on installation. For example (from [operadriver.rb](https://github.com/Homebrew/homebrew-cask/blob/326c44e93aeb8d4dd73acea14a99ae215c75fdd6/Casks/o/operadriver.rb#L15)):

```ruby
binary "operadriver_mac64/operadriver"
```

creates a symlink to:

```bash
$(brew --prefix)/bin/operadriver
```

from a source file such as:

```bash
$(brew --caskroom)/operadriver/106.0.5249.119/operadriver_mac64/operadriver
```

A binary (or multiple) can also be contained in an application bundle:

```ruby
app "Atom.app"
binary "#{appdir}/Atom.app/Contents/Resources/app/apm/bin/apm"
```

You can rename the target which appears in your binaries directory by adding a `target:` key to `binary`:

```ruby
binary "#{appdir}/Atom.app/Contents/Resources/app/atom.sh", target: "atom"
```

Behaviour and usage of `target:` is [the same as with `app`](#renaming-the-target). However, for `binary` the select cases don’t apply as rigidly. It’s fine to take extra liberties with `target:` to be consistent with other command-line tools, like [changing case](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/g/godot.rb#L19), [removing an extension](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/f/filebot.rb#L19), or [cleaning up the name](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/f/fig.rb#L21).

### Stanza: `caveats`

Sometimes there are particularities with the installation of a piece of software that cannot or should not be handled programmatically by Homebrew Cask. In those instances, `caveats` is the way to inform the user. Information in `caveats` is displayed when a cask is invoked with either `install` or `info`.

To avoid flooding users with too many messages (thus desensitising them to the important ones), `caveats` should be used sparingly and exclusively for installation-related matters. If you’re not sure a `caveat` you find pertinent is installation-related or not, ask a maintainer. As a general rule, if your case isn’t already covered in our comprehensive [`caveats Mini-DSL`](#caveats-mini-dsl), it’s unlikely to be accepted.

#### `caveats` as a string

When `caveats` is a string, it is evaluated at compile time. The following methods are available for interpolation if `caveats` is placed in its customary position at the end of the cask:

| method             | description |
| ------------------ | ----------- |
| `token`            | the cask token |
| `version`          | the cask version |
| `homepage`         | the cask homepage |
| `caskroom_path`    | the containing directory for this cask: `$(brew --caskroom)/<token>` (only available with block form) |
| `staged_path`      | the staged location for this cask, including version number: `$(brew --caskroom)/<token>/<version>` (only available with block form) |

Example:

```ruby
caveats "Using #{token} may be hazardous to your health."
```

#### `caveats` as a block

When `caveats` is a Ruby block, evaluation is deferred until install time. Within a block you may refer to the `@cask` instance variable, and invoke [any method available on `@cask`](https://rubydoc.brew.sh/Cask/Cask).

#### `caveats` mini-DSL

There is a mini-DSL available within `caveats` blocks.

The following methods may be called to generate standard warning messages:

| method                             | description |
| ---------------------------------- | ----------- |
| `path_environment_variable "path"` | Users should make sure `path` is in their `PATH` environment variable. |
| `zsh_path_helper "path"`           | `zsh` users must take additional steps to make sure `path` is in their `PATH` environment variable. |
| `depends_on_java "version"`        | Users should make sure they have the specified version of Java installed. `version` can be exact (e.g. `6`), a minimum (e.g. `7+`), or omitted (when any version works). |
| `requires_rosetta`                 | The cask requires Rosetta 2 for it to run on Apple Silicon. |
| `logout`                           | Users should log out and log back in to complete installation. |
| `reboot`                           | Users should reboot to complete installation. |
| `files_in_usr_local`               | The cask installs files to `/usr/local`, which may confuse Homebrew. |
| `kext`                             | Users may need to enable their kexts in *System Settings → Privacy & Security* (or *System Preferences → Security & Privacy → General* in earlier macOS versions). |
| `unsigned_accessibility`           | Users will need to re-enable the app on each update in *System Settings → Privacy & Security* (or *System Preferences → Security & Privacy → Privacy* in earlier macOS versions) as it is unsigned. |
| `license "web_page"`               | Users may find the software's usage license at `web_page`. |
| `free_license "web_page"`          | Users may obtain an official license to use the software at `web_page`. |

Example:

```ruby
caveats do
  path_environment_variable "/usr/texbin"
end
```

### Stanza: `deprecate!` / `disable!`

`deprecate!` and `disable!` are used to declare that a cask is no longer functional or supported.
Casks that contain a `deprecate!` stanza can still be installed, but will print a warning message when they are installed or upgraded.
Casks that contain a `disable!` stanza cannot be installed or upgraded and will print an error message.

The syntax for both stanzas is the same:

```ruby
deprecate! date: "YYYY-MM-DD", because: "is ..."
disable! date: "YYYY-MM-DD", because: "is ..."

# Or with a preset reason (see the `because:` argument section below)
deprecate! date: "YYYY-MM-DD", because: :discontinued
disable! date: "YYYY-MM-DD", because: :discontinued
```

#### `date:` argument

The `date:` argument controls when the deprecation or disabling will take effect.
Casks that have a `deprecate!` stanza with a date in the future will not be treated as being deprecated until that date.
Casks that have a `disable!` stanza with a date in the future will be automatically deprecated until that date, at which point they will be disabled.

#### `because:` argument

The `because:` argument accepts a reason for the cask being deprecated or disabled.
The info message will be `<cask> is deprecated because it <reason>!`, so format the reason to fit that sentence.
For example, `because: "is broken"` will result in `<cask> is deprecated because it is broken!`.

The `because:` argument can also accept a symbol that corresponds to a preset reason, for example:

```ruby
deprecate! date: "YYYY-MM-DD", because: :discontinued
```

A complete list of allowable symbols can be found in the [`DeprecateDisable` module](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/deprecate_disable.rb).

### Stanza: `conflicts_with`

`conflicts_with` is used to declare conflicts that keep a cask from installing or working correctly.

#### `conflicts_with` *cask*

The value should be another cask token.

Example: the [macFUSE](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/m/macfuse.rb#L17) cask, which conflicts with `macfuse-dev`.

```ruby
conflicts_with cask: "macfuse-dev"
```

#### `conflicts_with` *formula*

**Note:** `conflicts_with formula:` is a stub and is not yet functional.

The value should be another formula name.

Example: [MacVim](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/m/macvim.rb#L16), which conflicts with the `macvim` formula.

```ruby
conflicts_with formula: "macvim"
```

### Stanza: `depends_on`

`depends_on` is used to declare dependencies and requirements for a cask. `depends_on` is not consulted until `install` is attempted.

#### `depends_on` *cask*

The value should be another cask token, needed by the current cask.

Example: [NTFSTool](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/n/ntfstool.rb#L11), which depends on macFUSE.

```ruby
depends_on cask: "macfuse"
```

#### `depends_on` *formula*

The value should name a Homebrew formula needed by the cask.

Example: some distributions are contained in archive formats such as `7z` which are not supported by stock Apple tools. For these cases, a more capable archive reader may be pulled in at install time by declaring a dependency on the `unar` formula:

```ruby
depends_on formula: "unar"
```

#### `depends_on` *macos*

##### Requiring an exact macOS release

The value for `depends_on macos:` may be a symbol or an array of symbols, listing the exact compatible macOS releases. The available values for macOS releases are defined in the [MacOSVersion class](https://rubydoc.brew.sh/MacOSVersion.html).

Only major releases are covered (10.x numbers containing a single dot or whole numbers since macOS 11). The symbol form is used for readability. The following are all valid ways to enumerate the exact macOS release requirements for a cask:

```ruby
depends_on macos: :big_sur
depends_on macos: [
  :catalina,
  :big_sur,
]
```

##### Setting a minimum macOS release

`depends_on macos:` can also accept a string starting with a comparison operator such as `>=`, followed by an macOS release in the form above. The following is a valid expression meaning “at least macOS Big Sur (11.0)”:

```ruby
depends_on macos: ">= :big_sur"
```

A comparison expression cannot be combined with any other form of `depends_on macos:`.

#### `depends_on` *arch*

The value for `depends_on arch:` may be a symbol or an array of symbols, listing the hardware compatibility requirements for a cask. The requirement is satisfied at install time if any one of multiple `arch:` values matches the user’s hardware.

The available symbols for hardware are:

| symbol     | meaning        |
| ---------- | -------------- |
| `:arm64`   | Apple Silicon |
| `:x86_64`  | 64-bit Intel |
| `:intel`   | 64-bit Intel |

The following are all valid expressions:

```ruby
depends_on arch: :arm64
depends_on arch: :intel
depends_on arch: :x86_64            # same meaning as above
depends_on arch: [:x86_64]          # same meaning as above
```

#### `depends_on` parameters

| key        | description |
| ---------- | ----------- |
| `formula:` | Homebrew formula |
| `cask:`    | cask token |
| `macos:`   | symbol, array, or string comparison expression defining macOS release requirements |
| `arch:`    | symbol or array defining hardware requirements |
| `java:`    | *stub - not yet functional* |

### Stanza: `desc`

`desc` accepts a single-line UTF-8 string containing a short description of the software. It’s used to help with searchability and disambiguation, thus it must concisely describe what the software does (or what you can accomplish with it).

`desc` is not for app slogans! Vendors’ descriptions tend to be filled with generic adjectives such as “modern” and “lightweight”. Those are meaningless marketing fluff (do you ever see apps proudly describing themselves as outdated and bulky?) which must be deleted. It’s fine to use the information on the software’s website as a starting point, but it will require editing in almost all cases.

#### Dos and Don'ts

* **Do** start with an uppercase letter.

  ```diff
  - desc "sound and music editor"
  + desc "Sound and music editor"
  ```

* **Do** be brief, i.e. use less than 80 characters.

  ```diff
  - desc "Sound and music editor which comes with effects, instruments, sounds and all kinds of creative features"
  + desc "Sound and music editor"
  ```

* **Do** describe what the software does or is.

  ```diff
  - desc "Development of musical ideas made easy"
  + desc "Sound and music editor"
  ```

* **Do not** include the platform. Casks only work on macOS, so this is redundant information.

  ```diff
  - desc "Sound and music editor for macOS"
  + desc "Sound and music editor"
  ```

* **Do not** include the cask’s [name](#stanza-name).

  ```diff
  - desc "Ableton Live is a sound and music editor"
  + desc "Sound and music editor"
  ```

* **Do not** include the vendor. This should be added to the cask’s [name](#stanza-name) instead.

  ```diff
  - desc "Sound and music editor made by Ableton"
  + desc "Sound and music editor"
  ```

* **Do not** add user pronouns.

  ```diff
  - desc "Edit your music files"
  + desc "Sound and music editor"
  ```

* **Do not** use empty marketing jargon.

  ```diff
  - desc "Beautiful and powerful modern sound and music editor"
  + desc "Sound and music editor"
  ```

### Stanza: `*flight`

The stanzas `preflight`, `postflight`, `uninstall_preflight`, and `uninstall_postflight` define operations to be run before or after installation or uninstallation.

#### Evaluation of blocks is always deferred

The Ruby blocks defined by these stanzas are not evaluated until install time or uninstall time. Within a block you may refer to the `@cask` instance variable, and invoke [any method available on `@cask`](https://rubydoc.brew.sh/Cask/Cask).

#### `*flight` mini-DSL

There is a mini-DSL available within these blocks.

The following methods may be called to perform standard tasks:

| method                                    | availability                                     | description |
| ----------------------------------------- | ------------------------------------------------ | ----------- |
| `set_ownership(paths)`                    | `preflight`, `postflight`, `uninstall_preflight` | Set user and group ownership of `paths`. (Example: [docker-toolbox.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/d/docker-toolbox.rb#L42)) |
| `set_permissions(paths, permissions_str)` | `preflight`, `postflight`, `uninstall_preflight` | Set permissions in `paths` to `permissions_str`. (Example: [ngrok.rb](https://github.com/Homebrew/homebrew-cask/blob/41d91ff669d85343175202adf568e2328486205f/Casks/n/ngrok.rb#L30)) |

`set_ownership(paths)` defaults user ownership to the current user and group ownership to `staff`. These can be changed by passing in extra options: `set_ownership(paths, user: "user", group: "group")`. (Example: [hummingbird.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/h/hummingbird.rb#L24))

### Stanza: `installer`

This stanza must always be accompanied by [`uninstall`](#stanza-uninstall).

The `installer` stanza takes a series of key-value pairs, the first key of which must be `manual:` or `script:`.

#### `installer` *manual*

`installer manual:` takes a single string value, describing a GUI installer which must be run by the user at a later time. The path may be absolute, or relative to the cask. Example (from [rubymotion.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/r/rubymotion.rb#L15)):

```ruby
installer manual: "RubyMotion Installer.app"
```

#### `installer` *script*

`installer script:` introduces a series of key-value pairs describing a command which will automate completion of the install. **It should never be used for interactive installations.** The form is similar to [`uninstall script:`](#uninstall-script):

| key             | value |
| --------------- | ----- |
| `executable:`   | path to an install script to be run |
| `args:`         | array of arguments to the install script |
| `input:`        | array of lines of input to be sent to `stdin` of the script |
| `must_succeed:` | set to `false` if the script is allowed to fail |
| `sudo:`         | set to `true` if the script needs *sudo* |

The path may be absolute, or relative to the cask. Example (from [miniforge.rb](https://github.com/Homebrew/homebrew-cask/blob/864f623e2cd17dbde5987a7b3923fdb0b4ac9ee5/Casks/m/miniforge.rb#L23-L26)):

```ruby
installer script: {
  executable: "Miniforge3-#{version}-MacOSX-x86_64.sh",
  args:       ["-b", "-p", "#{caskroom_path}/base"],
}
```

If the `installer script:` does not require any of the key-values it can point directly to the path of the install script:

```ruby
installer script: "#{staged_path}/install.sh"
```

### Stanza: `language`

The `language` stanza can match [ISO 639-1](https://en.wikipedia.org/wiki/ISO_639-1) language codes, script codes ([ISO 15924](https://en.wikipedia.org/wiki/ISO_15924)) and regional identifiers ([ISO 3166-1 Alpha 2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2)), or a combination thereof.

US English should always be used as the default language:

```ruby
language "zh", "CN" do
  "zh_CN"
end

language "de" do
  "de_DE"
end

language "en-GB" do
  "en_GB"
end

language "en", default: true do
  "en_US"
end
```

Note that the following are not the same:

```ruby
language "en", "GB" do
  # matches all locales containing "en" or "GB"
end

language "en-GB" do
  # matches only locales containing "en" and "GB"
end
```

The return value of the matching `language` block can be accessed by simply calling `language`.

```ruby
homepage "https://example.org/#{language}"
```

Examples: [firefox.rb](https://github.com/Homebrew/homebrew-cask/blob/939b4331dc2a6860350d66a1b2c7b3f22442cc08/Casks/f/firefox.rb#L4-L207), [battle-net.rb](https://github.com/Homebrew/homebrew-cask/blob/e039d079560cf2f77b671f7dda4752a053341180/Casks/b/battle-net.rb#L5-L10)

#### Installation

To install a cask in a specific language, you can pass the `--language=` option to `brew install`:

```bash
brew install firefox --language=it
```

### Stanza: `livecheck`

The `livecheck` stanza is used to automatically fetch the latest version of a cask from changelogs, release notes, appcasts, etc.

Every `livecheck` block must contain a `url`, which can be either a string or a symbol pointing to other URLs in the cask (`:url` or `:homepage`).

Refer to the [`brew livecheck` documentation](Brew-Livecheck.md) for how to write a `livecheck` block.

### Stanza: `name`

`name` accepts a UTF-8 string defining the name of the software, including capitalization and punctuation. It is used to help with searchability and disambiguation.

Unlike the [token](#token-reference), which is simplified and reduced to a limited set of characters, the `name` stanza can include the proper capitalization, spacing and punctuation to match the official name of the software. For disambiguation purposes, it is recommended to spell out the name of the application, including the vendor name if necessary. A good example is the [`pycharm-ce`](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/p/pycharm-ce.rb#L9-L10) cask, whose name is spelled out as `Jetbrains PyCharm Community Edition`, even though it is likely never referenced as such anywhere.

Additional details about the software can be provided in the [`desc` stanza](#stanza-desc).

The `name` stanza can be repeated multiple times if there are useful alternative names. The first instance should use the Latin alphabet. For example, see the [`cave-story`](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/c/cave-story.rb#L58-L60) cask, whose original name does not use the Latin alphabet.

### Stanza: `pkg`

This stanza must always be accompanied by [`uninstall`](#stanza-uninstall).

The first argument to the `pkg` stanza should be a relative path to the `.pkg` file to be installed. Example:

```ruby
pkg "Unity.pkg"
```

Subsequent arguments to `pkg` are key/value pairs which modify the install process. Currently supported keys are `allow_untrusted:` and `choices:`.

#### `pkg` *allow_untrusted*

`pkg allow_untrusted: true` can be used to install a `.pkg` containing an untrusted certificate by passing `-allowUntrusted` to `/usr/sbin/installer`.

This option is not permitted in official Homebrew Cask taps; it is only provided for use in third-party taps or local casks.

Historical example (from [alinof-timer.rb](https://github.com/Homebrew/homebrew-cask/blob/312ae841f1f1b2ec07f4d88b7dfdd7fbdf8d4f94/Casks/alinof-timer.rb#L10)):

```ruby
pkg "AlinofTimer.pkg", allow_untrusted: true
```

#### `pkg` *choices*

`pkg choices:` can be used to override a `.pkg`’s default install options via `-applyChoiceChangesXML`. It uses a deserialized version of the `choiceChanges` property list (refer to the `CHOICE CHANGES FILE` section of the `installer` manual page by running `man -P 'less --pattern "^CHOICE CHANGES FILE"' installer`).

Running this macOS `installer` command:

```bash
installer -showChoicesXML -pkg '/path/to/my.pkg'
```

will output XML that you can use to extract the `choices:` values, as well as their equivalents to the GUI options.

See [this pull request for wireshark-chmodbpf](https://github.com/Homebrew/homebrew-cask/pull/26997) and [this one for wine-staging](https://github.com/Homebrew/homebrew-cask/pull/27937) for some examples of the procedure.

Example (from [lando.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/l/lando.rb#L21-L33)):

```ruby
pkg "LandoInstaller.pkg",
    choices: [
      {
        "choiceIdentifier" => "choiceDocker",
        "choiceAttribute"  => "selected",
        "attributeSetting" => 0,
      },
      {
        "choiceIdentifier" => "choiceLando",
        "choiceAttribute"  => "selected",
        "attributeSetting" => 1,
      },
    ]
```

Example (from [microsoft-office.rb](https://github.com/Homebrew/homebrew-cask/blob/56cabc6cec8be8f8a2fd06bc0b88f851d3b075d7/Casks/m/microsoft-office.rb#L30-L37)):

```ruby
pkg "Microsoft_365_and_Office_#{version}_Installer.pkg",
    choices: [
      {
        "choiceIdentifier" => "com.microsoft.autoupdate", # Office16_all_autoupdate.pkg
        "choiceAttribute"  => "selected",
        "attributeSetting" => 0,
      },
    ]
```

### Stanza: `sha256`

#### Calculating the SHA-256

The `sha256` value is usually calculated by the `shasum` command:

```bash
shasum --algorithm 256 <file>
```

#### Special value `:no_check`

The special value `sha256 :no_check` is used to turn off SHA checking whenever checksumming is impractical due to the upstream configuration.

`version :latest` requires `sha256 :no_check`, and this pairing is common. However, `sha256 :no_check` does not require `version :latest`.

We use a checksum whenever possible.

### Stanza: `suite`

Some distributions provide a suite of multiple applications, or an application with required data, to be installed together in a subdirectory of `/Applications`.

For these casks, use the `suite` stanza to define the directory containing the application suite. Example (from [racket.rb](https://github.com/Homebrew/homebrew-cask/blob/e65e45e94d27d14a78e1bd02b584b0c89c8f9e8b/Casks/r/racket.rb#L18)):

```ruby
suite "Racket v#{version}"
```

The value of `suite` is never an `.app` bundle, but a plain directory.

### Stanza: `uninstall`

> If you cannot design a working `uninstall` stanza, please submit your cask anyway. The maintainers can help you write an `uninstall` stanza, just ask!

#### `uninstall pkgutil:` is the easiest and most useful

The easiest and most useful `uninstall` directive is [`pkgutil:`](#uninstall-pkgutil). It should cover most use cases.

#### `uninstall` is required for casks that install using `pkg` or `installer manual:`

For most casks, uninstall actions are determined automatically, and an explicit `uninstall` stanza is not needed. However, a cask which uses the `pkg` or `installer manual:` stanzas will **not** know how to uninstall correctly unless an `uninstall` stanza is given.

So, while the [cask DSL](#required-stanzas) does not enforce the requirement, it is much better for users if every `pkg` and `installer manual:` has a corresponding `uninstall`.

The `uninstall` stanza is available for non-`pkg` casks, and is useful for a few corner cases. However, the documentation below concerns the typical case of using `uninstall` to define procedures for a `pkg`.

#### There are multiple uninstall techniques

Since `pkg` installers can do arbitrary things, different techniques are needed to uninstall in each case. You may need to specify one, or several, of the following key/value pairs as arguments to `uninstall`.

#### Summary of keys

* **`early_script:`** (string or hash) - like [`script:`](#uninstall-script), but runs early (for special cases, best avoided)
* [`launchctl:`](#uninstall-launchctl) (string or array) - IDs of `launchd` jobs to remove
* [`quit:`](#uninstall-quit) (string or array) - bundle IDs of running applications to quit (does not run when uninstall is initiated by `brew upgrade` or `brew reinstall`)
* [`signal:`](#uninstall-signal) (array of arrays) - signal numbers and bundle IDs of running applications to send a Unix signal to - for when `quit:` does not work (does not run when uninstall is initiated by `brew upgrade` or `brew reinstall`)
* [`login_item:`](#uninstall-login_item) (string or array) - names of login items to remove
* [`kext:`](#uninstall-kext) (string or array) - bundle IDs of kexts to unload from the system
* [`script:`](#uninstall-script) (string or hash) - relative path to an uninstall script to be run via sudo; use hash if args are needed
  * `executable:` - relative path to an uninstall script to be run via sudo (required for hash form)
  * `args:` - array of arguments to the uninstall script
  * `input:` - array of lines of input to be sent to `stdin` of the script
  * `must_succeed:` - set to `false` if the script is allowed to fail
  * `sudo:` - set to `true` if the script needs *sudo*
* [`pkgutil:`](#uninstall-pkgutil) (string, regexp or array of strings and regexps) - strings or regexps matching bundle IDs of packages to uninstall using `pkgutil`
* [`delete:`](#uninstall-delete) (string or array) - double-quoted, absolute paths of files or directory trees to remove. Should only be used as a last resort; `pkgutil:` is strongly preferred.
* **`rmdir:`** (string or array) - double-quoted, absolute paths of directories to remove if empty. Works recursively.
* [`trash:`](#uninstall-trash) (string or array) - double-quoted, absolute paths of files or directory trees to move to Trash

Each `uninstall` technique is applied according to the order above. The order in which `uninstall` keys appear in the cask file is ignored.

For assistance filling in the right values for `uninstall` keys, there are several helper scripts found under `developer/bin` in the Homebrew Cask repository. Each of these scripts responds to the `-help` option with additional documentation.

Working out an `uninstall` stanza is easiest when done on a system where the package is currently installed and operational. To operate on an uninstalled `.pkg` file, see [Working With a `.pkg` File Manually](#working-with-a-pkg-file-manually), below.

#### `uninstall` *pkgutil*

This is the most useful uninstall key. `pkgutil:` is often sufficient to completely uninstall a `pkg`, and is strongly preferred over `delete:`.

IDs for the most recently installed packages can be listed using [`list_recent_pkg_ids`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_recent_pkg_ids):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_recent_pkg_ids"
```

`pkgutil:` also accepts a regular expression match against multiple package IDs. The regular expressions are somewhat nonstandard. To test a `pkgutil:` regular expression against currently installed packages, use [`list_pkg_ids_by_regexp`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_pkg_ids_by_regexp):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_pkg_ids_by_regexp" <regular-expression>
```

#### List files associated with a package ID

Once you know the ID for an installed package (see above), you can list all files on your system associated with that package ID using the macOS `pkgutil` command:

```bash
pkgutil --files <package.id.goes.here>
```

Listing the associated files can help you assess whether the package included any `launchd` jobs or kernel extensions (kexts).

#### `uninstall` *launchctl*

IDs for currently loaded `launchd` jobs can be listed using [`list_loaded_launchjob_ids`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_loaded_launchjob_ids):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_loaded_launchjob_ids"
```

IDs for all installed `launchd` jobs can be listed using [`list_installed_launchjob_ids`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_installed_launchjob_ids):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_installed_launchjob_ids"
```

#### `uninstall` *quit*

Bundle IDs for currently running applications can be listed using [`list_running_app_ids`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_running_app_ids):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_running_app_ids"
```

Bundle IDs inside an application bundle on disk can be listed using [`list_ids_in_app`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_ids_in_app):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_ids_in_app" '/path/to/application.app'
```

#### `uninstall` *signal*

`signal:` should only be needed in the rare case that a process does not respond to `quit:`.

Bundle IDs for `signal:` targets may be obtained in the same way as for `quit:`. The value for `signal:` is an array-of-arrays, with each cell containing two elements: the desired Unix signal followed by the corresponding bundle ID.

The Unix signal may be given in numeric or string form (see the `kill`(1) man page for more details).

The elements of the `signal:` array are applied in order, only if there is an existing process associated the bundle ID, and stopping when that process terminates. A bundle ID may be repeated to send more than one signal to the same process.

It is better to use the least-severe signals that are sufficient to stop a process. The `KILL` signal in particular can have unwanted side effects.

An example, with commonly used signals in ascending order of severity:

```ruby
uninstall signal: [
  ["TERM", "fr.madrau.switchresx.daemon"],
  ["QUIT", "fr.madrau.switchresx.daemon"],
  ["INT",  "fr.madrau.switchresx.daemon"],
  ["HUP",  "fr.madrau.switchresx.daemon"],
  ["KILL", "fr.madrau.switchresx.daemon"],
]
```

Note that when multiple running processes match the given bundle ID, all matching processes will be signaled.

Unlike `quit:` directives, Unix signals originate from the current user, not from the superuser. This is construed as a safety feature, since the superuser is capable of bringing down the system via signals. However, this inconsistency may also be considered a bug, and should be addressed in some fashion in a future version.

#### `uninstall` *login_item*

Login items associated with an application bundle on disk can be listed using [`list_login_items_for_app`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_login_items_for_app):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_login_items_for_app" '/path/to/application.app'
```

Note that you will likely need to have opened the app at least once for any login items to be present.

#### `uninstall` *kext*

IDs for currently loaded kernel extensions can be listed using [`list_loaded_kext_ids`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_loaded_kext_ids):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_loaded_kext_ids"
```

IDs inside a kext bundle on disk can be listed using [`list_id_in_kext`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_id_in_kext):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_id_in_kext" '/path/to/name.kext'
```

#### `uninstall` *script*

`uninstall script:` introduces a series of key-value pairs describing a command which will automate completion of the uninstall. Example (from [virtualbox.rb](https://github.com/Homebrew/homebrew-cask/blob/ef9931087f6e101262bf64119166e2d9cec068f0/Casks/v/virtualbox.rb#L55-L61)):

```ruby
uninstall script:  {
            executable: "VirtualBox_Uninstall.tool",
            args:       ["--unattended"],
            sudo:       true,
          },
          pkgutil: "org.virtualbox.pkg.*",
          delete:  "/usr/local/bin/vboximg-mount"
```

It is important to note that, although `script:` in the above example does attempt to completely uninstall the `pkg`, it should not be used in place of [`pkgutil:`](#uninstall-pkgutil), but as a complement when possible.

#### `uninstall` *delete*

`delete:` should only be used as a last resort, if other `uninstall` methods are insufficient.

Arguments to `uninstall delete:` should use the following basic rules:

* Basic tilde expansion is performed on paths, i.e. leading `~` is expanded to the home directory.
* Paths must be absolute.
* Glob expansion is performed using the [standard set of characters](https://en.wikipedia.org/wiki/Glob_(programming)).

To remove user-specific files, use the [`zap` stanza](#stanza-zap).

#### `uninstall` *trash*

`trash:` arguments follow the same rules listed above for `delete:`.

#### Working with a `.pkg` file manually

Advanced users may wish to work with a `.pkg` file manually, without having the package installed.

A list of files which may be installed from a `.pkg` can be extracted using [`list_payload_in_pkg`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_payload_in_pkg):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_payload_in_pkg" '/path/to/my.pkg'
```

Candidate application names helpful for determining the name of a cask may be extracted from a `.pkg` file using [`list_apps_in_pkg`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_apps_in_pkg):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_apps_in_pkg" '/path/to/my.pkg'
```

Candidate package IDs which may be useful in a `pkgutil:` key may be extracted from a `.pkg` file using [`list_ids_in_pkg`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_ids_in_pkg):

```bash
"$(brew --repository homebrew/cask)/developer/bin/list_ids_in_pkg" '/path/to/my.pkg'
```

A fully manual method for finding bundle IDs in a package file follows:

1. Unpack `/path/to/my.pkg` (replace with your package name) with `pkgutil --expand /path/to/my.pkg /tmp/expanded.unpkg`.
2. The unpacked package is a folder. Bundle IDs are contained within files named `PackageInfo`. These files can be found with the command `find /tmp/expanded.unpkg -name PackageInfo`.
3. `PackageInfo` files are XML files, and bundle IDs are found within the `identifier` attributes of `<pkg-info>` tags that look like `<pkg-info ... identifier="com.oracle.jdk7u51" ... >`, where extraneous attributes have been snipped out and replaced with ellipses.
4. Kexts inside packages are also described in `PackageInfo` files. If any kernel extensions are present, the command `find /tmp/expanded.unpkg -name PackageInfo -print0 | xargs -0 grep -i kext` should return a `<bundle id>` tag with a `path` attribute that contains a `.kext` extension, for example `<bundle id="com.wavtap.driver.WavTap" ... path="./WavTap.kext" ... />`.
5. Once bundle IDs have been identified, the unpacked package directory can be deleted.

### Stanza: `url`

#### HTTPS URLs are preferred

If available, an HTTPS URL is preferred. A plain HTTP URL should only be used in the absence of a secure alternative.

#### Additional `url` parameters

When a plain URL string is insufficient to fetch a file, additional information may be provided to the `curl`-based downloader, in the form of key/value pairs appended to `url`:

| key                | value       |
| ------------------ | ----------- |
| `verified:`        | string repeating the beginning of `url`, for [verification purposes](#when-url-and-homepage-domains-differ-add-verified) |
| `using:`           | the symbols `:post` and `:homebrew_curl` are the only legal values |
| `cookies:`         | hash of cookies to be set in the download request (Example: [oracle-jdk-javadoc.rb](https://github.com/Homebrew/homebrew-cask/blob/326c44e93aeb8d4dd73acea14a99ae215c75fdd6/Casks/o/oracle-jdk-javadoc.rb#L5-L8)) |
| `referer:`         | string holding the URL to set as referer in the download request (Example: [firealpaca.rb](https://github.com/Homebrew/homebrew-cask/blob/c4b3f0742e044ae2a6e114eb6b90068763d0d12b/Casks/f/firealpaca.rb#L5-L6)) |
| `header:`          | string or array of strings holding the header(s) to set for the download request (Example: [pull-6545](https://github.com/Homebrew/brew/pull/6545#issue-503302353), [issue-15590](https://github.com/Homebrew/brew/issues/15590#issue-1774825542)) |
| `user_agent:`      | string holding the user agent to set for the download request. Can also be set to the symbol `:fake`, which will use a generic browser-like user agent string. We prefer `:fake` when the server does not require a specific user agent. |
| `data:`            | hash of parameters to be set in the POST request (Example: [segger-jlink.rb](https://github.com/Homebrew/homebrew-cask/blob/38ac55614f146d68ae317594f0c119e9acbd7c9e/Casks/s/segger-jlink.rb#L6-L11)) |

#### When URL and homepage domains differ, add `verified:`

When the domains of `url` and `homepage` differ, the discrepancy should be documented with the `verified:` parameter, repeating the smallest possible portion of the URL that uniquely identifies the app or vendor, excluding the protocol. (Example: [1password-cli.rb](https://github.com/Homebrew/homebrew-cask/blob/ec2476459ead02e80391f44d42a2b48a18bf373d/Casks/1/1password-cli.rb#L8-L9))

This must be added so a user auditing the cask knows the URL was verified by the Homebrew Cask team as the one provided by the vendor, even though it may look unofficial. It is our responsibility as Homebrew Cask maintainers to verify both the `url` and `homepage` information when first added (or subsequently modified, apart from versioning).

The parameter doesn’t mean you should trust the source blindly, but we only approve casks in which users can easily verify its authenticity with basic means, such as checking the official homepage or public repository. Occasionally, slightly more elaborate techniques may be used, such as inspecting a [`livecheck`](#stanza-livecheck) URL we established as official. Cases where such quick verifications aren’t possible (e.g. when the download URL is behind a registration wall) are [treated in a stricter manner](https://docs.brew.sh/Acceptable-Casks#unofficial-vendorless-and-walled-builds).

#### Difficulty finding a URL

Web browsers may obscure the direct `url` download location for a variety of reasons. Homebrew Cask supplies a [`list_url_attributes_on_file`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/developer/bin/list_url_attributes_on_file) script which can read extended file attributes to extract the actual source URL of most files downloaded by a browser on macOS. The script usually emits multiple candidate URLs; you may have to test each of them:

```bash
$(brew --repository homebrew/cask)/developer/bin/list_url_attributes_on_file <file>
```

#### Subversion URLs

In rare cases, a distribution may not be available over ordinary HTTP/S. Subversion URLs are also supported, and can be specified by appending the following key/value pairs to `url`:

| key                | value       |
| ------------------ | ----------- |
| `using:`           | the symbol `:svn` is the only legal value |
| `revision:`        | string identifying the Subversion revision to download |
| `trust_cert:`      | set to `true` to automatically trust the certificate presented by the server (avoiding an interactive prompt) |

#### Git URLs

Artifacts also may be distributed via Git repositories. URLs that end in `.git` are automatically assumed to be Git repositories, and the following key/value pairs may be appended to `url`:

| key                | value       |
| ------------------ | ----------- |
| `using:`           | the symbol `:git` is the only legal value |
| `tag:`             | string identifying the Git tag to download |
| `revision:`        | string identifying the Git revision to download |
| `branch:`          | string identifying the Git branch to download |
| `only_path:`       | path within the repository to limit the checkout to. If only a single directory of a large repository is required, using this option can significantly speed up downloads. If provided, artifact paths are relative to this path. (Example: [font-geo.rb](https://github.com/Homebrew/homebrew-cask-fonts/blob/bac691e1d7b5bd7372e7e0befae989a3ff7ad449/Casks/font-geo.rb#L5-L8)) |

#### SourceForge/OSDN URLs

SourceForge and OSDN (formerly `SourceForge.JP`) projects are common ways to distribute binaries, but they provide many different styles of URLs to get to the goods.

We prefer URLs of this format:

    https://downloads.sourceforge.net/<project_name>/<filename>.<ext>

Or, if it’s from OSDN, where `<subdomain>` is typically of the form `dl` or `<user>.dl`:

    http://<subdomain>.osdn.jp/<project_name>/<release_id>/<filename>.<ext>

If these formats are not available, and the application is macOS-exclusive (otherwise a command-line download defaults to the Windows version) we prefer the use of this format:

    https://sourceforge.net/projects/<project_name>/files/latest/download

#### Some providers block command-line downloads

Some hosting providers actively block command-line HTTP clients. Such URLs cannot be used in casks.

Other providers may use URLs that change periodically, or even on each visit (example: FossHub). While some cases [could be circumvented](#using-a-block-to-defer-code-execution), they tend to occur when the vendor is actively trying to prevent automated downloads, so we prefer to not add those casks to the main repository.

#### Using a block to defer code execution

Some casks—notably nightlies—have versioned download URLs but are updated so often that they become impractical to keep current with the usual process. For those, we want to dynamically determine `url`.

##### The Problem

In theory, one can write arbitrary Ruby code right in the cask definition to fetch and construct a disposable URL.

However, this typically involves an HTTP round trip to a landing site, which may take a long time. Because of the way Homebrew Cask loads and parses casks, it is not acceptable that such expensive operations be performed directly in the body of a cask definition.

##### Writing the block

Similar to the `preflight`, `postflight`, `uninstall_preflight`, and `uninstall_postflight` blocks, the `url` stanza offers an optional *block syntax*:

```ruby
url "https://handbrake.fr/nightly.php" do |page|
  file_path = page[/href=["']?([^"' >]*Handbrake[._-][^"' >]+\.dmg)["' >]/i, 1]
  file_path ? URI.join(page.url, file_path) : nil
end
```

You can also nest `url do` blocks inside `url do` blocks to follow a chain of URLs.

The block is only evaluated when needed, for example at download time or when auditing a cask. Inside a block, you may safely do things such as HTTP/S requests that may take a long time to execute. You may also refer to the `@cask` instance variable, and invoke [any method available on `@cask`](https://rubydoc.brew.sh/Cask/Cask).

The block will be called immediately before downloading; its result value will be assumed to be a `String` (or a pair of a `String` and `Hash` containing parameters) and subsequently used as a download URL.

You can use the `url` stanza with either a direct argument or a block but not with both.

Example of using the block syntax: [vlc@nightly.rb](https://github.com/Homebrew/homebrew-cask/blob/0b2b76ad8c3fbf4e1ee2f5e758640c4963ad6aaf/Casks/v/vlc%40nightly.rb#L7-L12)

##### Mixing additional URL parameters with the block syntax

In rare cases, you might need to set URL parameters like `cookies` or `referer` while also using the block syntax.

This is possible by returning a two-element array as a block result. The first element of the array must be the download URL; the second element must be a `Hash` containing the parameters.

### Stanza: `version`

`version`, while related to the app’s own versioning, doesn’t have to follow it exactly. It is common to change it slightly so it can be [interpolated](https://en.wikipedia.org/wiki/String_interpolation#Ruby_/_Crystal) in other stanzas, usually in `url` to create a cask that only needs `version` and `sha256` changes when updated. This can be taken further, when needed, with [Ruby String methods](https://ruby-doc.org/core/String.html).

For example, instead of:

```ruby
version "1.2.3"
url "https://example.com/file-version-123.dmg"
```

we can use:

```ruby
version "1.2.3"
url "https://example.com/file-version-#{version.delete(".")}.dmg"
```

We can also leverage the power of regular expressions. So instead of:

```ruby
version "1.2.3build4"
url "https://example.com/1.2.3/file-version-1.2.3build4.dmg"
```

we can use:

```ruby
version "1.2.3build4"
url "https://example.com/#{version.sub(/build\d+/, "")}/file-version-#{version}.dmg"
```

#### `version` methods

The examples above can become hard to read, however. Since many of these changes are common, we provide a number of helpers to clearly interpret otherwise obtuse cases:

| method                   | input              | output             |
| ------------------------ | ------------------ | ------------------ |
| `major`                  | `1.2.3-a45,ccdd88` | `1` |
| `minor`                  | `1.2.3-a45,ccdd88` | `2` |
| `patch`                  | `1.2.3-a45,ccdd88` | `3-a45` |
| `major_minor`            | `1.2.3-a45,ccdd88` | `1.2` |
| `major_minor_patch`      | `1.2.3-a45,ccdd88` | `1.2.3-a45` |
| `minor_patch`            | `1.2.3-a45,ccdd88` | `2.3-a45` |
| `before_comma`           | `1.2.3-a45,ccdd88` | `1.2.3-a45` |
| `after_comma`            | `1.2.3-a45,ccdd88` | `ccdd88` |
| `dots_to_hyphens`        | `1.2.3-a45,ccdd88` | `1-2-3-a45,ccdd88` |
| `no_dots`                | `1.2.3-a45,ccdd88` | `123-a45,ccdd88` |

Similar to `dots_to_hyphens`, we provide methods for all logical permutations of `{dots,hyphens,underscores}_to_{dots,hyphens,underscores}`. The same applies to `no_dots` in the form of `no_{dots,hyphens,underscores}`, with an extra `no_dividers` that applies all these at once.

Finally, there is `csv` which returns an array of comma-separated values. `csv`, `before_comma` and `after_comma` are extra-special to allow for otherwise complex cases, and should be used sparingly. There should be no more than two of `,` per `version`.

#### `version :latest`

The special value `:latest` is used when:

* `url` does not contain any version information and there is no way to retrieve
  the version using a `livecheck`, or
* having a correct value for `version` is too difficult or impractical, even with our automated systems. For example,
  [chromium.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/c/chromium.rb#L4)
  releases multiple versions a day.

### Stanza: `zap`

#### `zap` purpose

The `zap` stanza describes a more complete uninstallation of files associated with a cask. The `zap` procedures will never be performed by default, but only if the user uses `--zap` on `uninstall`:

```bash
brew uninstall --zap firefox
```

`zap` stanzas may remove:

* Preference files and caches stored within the user’s `~/Library` directory.
* Shared resources such as application updaters. Since shared resources may be removed, other applications may be affected by `brew uninstall --zap`. Understanding that is the responsibility of the end user.

`zap` stanzas should not remove:

* Files created by the user directly.

Appending `--force` to the command will allow you to perform these actions even if the cask is no longer installed:

```bash
brew uninstall --zap --force firefox
```

#### `zap` syntax

The form of the `zap` stanza follows the [`uninstall` stanza](#stanza-uninstall). All the same directives are available. The `trash:` key is preferred over `delete:`.

Example: [dropbox.rb](https://github.com/Homebrew/homebrew-cask/blob/974a55ade77bb4edc8bbb80ef72eec83ae0e76c0/Casks/d/dropbox.rb#L30-L68)

#### `zap` creation

The simplest method is to use [@nrlquaker's CreateZap](https://github.com/nrlquaker/homebrew-createzap), which can automatically generate the stanza. In a few instances it may fail to pick up anything and manual creation may be required.

Manual creation can be facilitated with:

* Some of the developer tools which are already available in Homebrew Cask.
* `sudo find / -iname "*<search item>*"`
* An uninstaller tool such as [AppCleaner](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/a/appcleaner.rb).
* Inspection of the usual paths, i.e. `/Library/{'Application Support',LaunchAgents,LaunchDaemons,Frameworks,Logs,Preferences,PrivilegedHelperTools}` and `~/Library/{'Application Support',Caches,Containers,LaunchAgents,Logs,Preferences,'Saved Application State'}`.

If no additional files are discovered, instead of a zap stanza, include the following comment:

```ruby
# No zap stanza required
```

## Conditional statements

### Handling different system configurations

Casks can deliver specific versions of artifacts depending on the current macOS release or CPU architecture by either tailoring the URL / SHA-256 hash / version, using the [`on_<system>` syntax](Formula-Cookbook.md#handling-different-system-configurations) (which replaces conditional statements using `MacOS.version` or `Hardware::CPU`), or both.

If your cask's artifact is offered as separate downloads for Apple Silicon and Intel architectures, they'll presumably be downloadable at distinct URLs that differ only slightly. To adjust the URL depending on the current CPU architecture, supply a hash for each to the `arm:` and `intel:` parameters of `sha256`, and use the special `arch` stanza to define the unique components of the respective URLs for substitution in the `url`. Additional substitutions can be defined by calling `on_arch_conditional` directly. Example (from [libreoffice.rb](https://github.com/Homebrew/homebrew-cask/blob/a4164b8f5084fdaefb6e2e2f4f699270690b7845/Casks/l/libreoffice.rb#L1-L10)):

```ruby
cask "libreoffice" do
  arch arm: "aarch64", intel: "x86-64"
  folder = on_arch_conditional arm: "aarch64", intel: "x86_64"

  version "7.6.0"
  sha256 arm:   "81eab945a33622fc156951e804024d23aa9a745c06743b4947215ed9303ad1c4",
         intel: "ede541af151487f60eb518e310d20dad1a973f3dbe9ff78d782dd29b14ba2946"

  url "https://download.documentfoundation.org/libreoffice/stable/#{version}/mac/#{folder}/LibreOffice_#{version}_MacOS_#{arch}.dmg",
      verified: "download.documentfoundation.org/libreoffice/stable/"
end
```

If the version number is different for each architecture, locate the unique `version` and (if checked) `sha256` stanzas within `on_arm` and `on_intel` blocks. Example (from [inkscape.rb](https://github.com/Homebrew/homebrew-cask/blob/11f6966bf17628b98895d64a61a4fb0bc1bb31bf/Casks/i/inkscape.rb#L1-L13)):

```ruby
cask "inkscape" do
  arch arm: "arm64", intel: "x86_64"

  on_arm do
    version "1.3.0,42339"
    sha256 "e37b5f8b8995a0ecc41ca7fcae90d79bcd652b7a25d2f6e52c4e2e79aef7fec1"
  end
  on_intel do
    version "1.3.0,42338"
    sha256 "e97de6804d8811dd2f1bc45d709d87fb6fe45963aae710c24a4ed655ecd8eb8a"
  end

  url "https://inkscape.org/gallery/item/#{version.csv.second}/Inkscape-#{version.csv.first}_#{arch}.dmg"
end
```

To adjust the installed version depending on the current macOS release, use a series of `on_<system>` blocks that cover the range of supported releases. Each block can contain stanzas that set which version to download and customize installation/uninstallation and livecheck behaviour for one or more releases. Example (from [calibre.rb](https://github.com/Homebrew/homebrew-cask/blob/482c34e950da8d649705f4aaea7b760dcb4b5402/Casks/c/calibre.rb#L1-L34)):

```ruby
cask "calibre" do
  on_high_sierra :or_older do
    version "3.48.0"
    sha256 "68829cd902b8e0b2b7d5cf7be132df37bcc274a1e5720b4605d2dd95f3a29168"

    livecheck do
      skip "Legacy version"
    end
  end
  on_mojave do
    # ...
  end
  on_catalina do
    # ...
  end
  on_big_sur :or_newer do
    version "6.25.0"
    sha256 "a7ed19ae0526630ccb138b9afee6dc5169904180b02f7a3089e78d3e0022753b"

    livecheck do
      url "https://github.com/kovidgoyal/calibre"
      strategy :github_latest
    end
  end
end
```

Such `on_<system>` blocks can be nested and contain other stanzas not listed here. Examples: [calhash.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/c/calhash.rb), [openzfs.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/o/openzfs.rb), [r.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/r/r.rb), [wireshark.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/wireshark.rb)

### Switch between languages or regions

If a cask is available in multiple languages, you can use the [`language` stanza](#stanza-language) to switch between languages or regions based on the system locale.

## Arbitrary Ruby methods

In the exceptional case that the cask DSL is insufficient, it is possible to define arbitrary Ruby variables and methods inside the cask by creating a `Utils` namespace. Example:

```ruby
cask "myapp" do
  module Utils
    def self.arbitrary_method
      # ...
    end
  end

  version "1.0"
  sha256 "a32565cdb1673f4071593d4cc9e1c26bc884218b62fef8abc450daa47ba8fa92"

  url "https://#{Utils.arbitrary_method}"
  name "MyApp"
  homepage "https://www.example.com/"
  # ...
end
```

This should be used sparingly: any method which is needed by two or more casks should instead be rolled into Homebrew/brew. Care must also be taken that such methods be very efficient.

Variables and methods should not be defined outside the `Utils` namespace, as they may collide with Homebrew Cask internals.

## Token reference

This section describes the algorithm implemented in the `generate_cask_token` script, and covers detailed rules and exceptions which are not needed in most cases.

* [Purpose](#purpose)
* [Finding the Simplified Name of the Vendor’s Distribution](#finding-the-simplified-name-of-the-vendors-distribution)
* [Converting the Simplified Name To a Token](#converting-the-simplified-name-to-a-token)
* [Cask Filenames](#cask-filenames)
* [Cask Headers](#cask-headers)
* [Cask Token Examples](#cask-token-examples)
* [Special Affixes](#special-affixes)

### Purpose

Software vendors are often inconsistent with their naming. By enforcing strict naming conventions we aim to:

* Prevent duplicate submissions
* Minimize renaming events
* Unambiguously boil down the name of the software into a unique identifier

Details of software names and brands will inevitably be lost in the conversion to a minimal token. To capture the vendor’s full name for a distribution, use the [`name`](#stanza-name) within a cask. `name` accepts an unrestricted UTF-8 string.

### Finding the simplified name of the vendor’s distribution

#### Simplified names of apps

* Start with the exact name of the application bundle as it appears on disk, such as `Google Chrome.app`.

* If the name uses letters outside A–Z, convert it to ASCII as described in [Converting to ASCII](#converting-to-ascii).

* Remove `.app` from the end.

* Remove from the end: the string “app”, if the vendor styles the name like “Software App.app”. Exception: when “app” is an inseparable part of the name, without which the name would be inherently nonsensical, as in [whatsapp.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/whatsapp.rb).

* Remove from the end: version numbers or incremental release designations such as “alpha”, “beta”, or “release candidate”. Strings which distinguish different capabilities or codebases such as “Community Edition” are currently accepted. Exception: when a number is not an incremental release counter, but a differentiator for a different product from a different vendor, as in [kdiff3.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/k/kdiff3.rb).

* If the version number is arranged to occur in the middle of the App name, it should also be removed.

* Remove from the end: “Launcher”, “Quick Launcher”.

* Remove from the end: strings such as “Desktop”, “for Desktop”.

* Remove from the end: strings such as “Mac”, “for Mac”, “for OS X”, “macOS”, “for macOS”. These terms are generally added to ported software such as “MAME OS X.app”. Exception: when the software is not a port, and “Mac” is an inseparable part of the name, without which the name would be inherently nonsensical, as in [PlayOnMac.app](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/p/playonmac.rb).

* Remove from the end: hardware designations such as “for x86”, “32-bit”, “ARM”.

* Remove from the end: software framework names such as “Cocoa”, “Qt”, “Gtk”, “Wx”, “Java”, “Oracle JVM”, etc. Exception: the framework is the product being casked.

* Remove from the end: localization strings such as “en-US”.

* If the result of that process is a generic term, such as “Macintosh Installer”, try prepending the name of the vendor or developer, followed by a hyphen. If that doesn’t work, then just create the best name you can, based on the vendor’s web page.

* If the result conflicts with the name of an existing cask, make yours unique by prepending the name of the vendor or developer, followed by a hyphen. Example: [unison.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/u/unison.rb) and [panic-unison.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/p/panic-unison.rb).

* Inevitably, there are a small number of exceptions not covered by the rules. Don’t hesitate to [use the forum](https://github.com/orgs/Homebrew/discussions) if you have a problem.

#### Converting to ASCII

* If the vendor provides an English localization string, that is preferred. Here are the places it may be found, in order of preference:

  * `CFBundleDisplayName` in the main `Info.plist` file of the app bundle
  * `CFBundleName` in the main `Info.plist` file of the app bundle
  * `CFBundleDisplayName` in `InfoPlist.strings` of an `en.lproj` localization directory
  * `CFBundleName` in `InfoPlist.strings` of an `en.lproj` localization directory
  * `CFBundleDisplayName` in `InfoPlist.strings` of an `English.lproj` localization directory
  * `CFBundleName` in `InfoPlist.strings` of an `English.lproj` localization directory

* When there is no vendor localization string, romanize the name by transliteration or decomposition.

* As a last resort, translate the name of the app bundle into English.

#### Simplified names of `pkg`-based installers

* The Simplified Name of a `pkg` may be more tricky to determine than that of an App. If a `pkg` installs an App, then use that App name with the rules above. If not, just create the best name you can, based on the vendor’s web page.

#### Simplified names of non-App software

* Currently, rules for generating a token are not well-defined for Preference Panes, Quick Look plugins, and several other types of software installable by Homebrew Cask. Just create the best name you can, based on the filename on disk or the vendor’s web page. Watch out for duplicates.

  Non-app tokens should become more standardized in the future.

### Converting the simplified name to a token

The token is the primary identifier for a package in this project. It’s the unique string users refer to when operating on the cask.

To convert the App’s Simplified Name (above) to a token:

* Convert all letters to lower case.
* Expand the `+` symbol into a separated English word: `-plus-`.
* Expand the `@` symbol into a separated English word: `-at-`.
* Spaces become hyphens.
* Underscores become hyphens.
* Middots/Interpuncts become hyphens.
* Hyphens stay hyphens.
* Digits stay digits.
* Delete any character which is not alphanumeric or a hyphen.
* Collapse a series of multiple hyphens into one hyphen.
* Delete a leading or trailing hyphen.

### Casks pinned to specific versions

Casks pinned to a specific version of the application (i.e. [`carbon-copy-cloner@5`](https://github.com/Homebrew/homebrew-cask/blob/1b8f44198e5e184c597ee07454a1e10f97f36b15/Casks/c/carbon-copy-cloner%405.rb)) should use the same token as the standard cask with a suffix of `@<version-number`. For Carbon Copy Cloner (`carbon-copy-cloner`), pinned to version 5, the token should be `carbon-copy-cloner@5`.

### Casks pinned to development channels

Casks that use an development "channel", such as betas, should use the same token as the standard cask with a suffix of `@<channel>`. For Google Chrome (`google-chrome`), using the "beta" channel, the token should be `google-chrome@beta`.

### Cask filenames

Casks are stored in a Ruby file named after the token, with the file extension `.rb`.

### Cask headers

The token is also given in the header line for each cask.

### Cask token examples

These illustrate most of the rules for generating a token:

| App Name on Disk       | Simplified App Name | Cask Token       | Filename |
|------------------------|---------------------|------------------|----------------------|
| `Audio Hijack Pro.app` | Audio Hijack Pro    | audio-hijack-pro | `audio-hijack-pro.rb` |
| `VLC.app`              | VLC                 | vlc              | `vlc.rb` |
| `BetterTouchTool.app`  | BetterTouchTool     | bettertouchtool  | `bettertouchtool.rb` |
| `LPK25 Editor.app`     | LPK25 Editor        | lpk25-editor     | `lpk25-editor.rb` |
| `Sublime Text 2.app`   | Sublime Text        | sublime-text     | `sublime-text.rb` |

For versioned/development channel casks:

| Standard Cask Token     | Derivative          | Cask Token           | Filename  |
|------------------------|---------------------|-----------------------|----------------------|
| `google-chrome`        | Beta Channel        | `google-chrome@beta`  | `google-chrome@beta.rb` |
| `vlc`                  | Nightly Channel     | `vlc@nightly`         | `vlc@nightly.rb` |
| `carbon-copy-cloner`   | Pinned to version 5 | `carbon-copy-cloner@5`| `carbon-copy-cloner@5.rb` |

### Special affixes

A few situations require a prefix or suffix to be added to the token.

#### Token overlap

When the token for a new cask would otherwise conflict with the token of an already existing cask, the nature of that overlap dictates the token, potentially for both casks. See [Forks and Apps with Conflicting Names](Acceptable-Casks.md#forks-and-apps-with-conflicting-names) for information on how to proceed.

#### Potentially misleading name

If the token for a piece of unofficial software that interacts with a popular service would make it look official and the vendor is not authorised to use the name, [a prefix must be added](Acceptable-Casks.md#forks-and-apps-with-conflicting-names) for disambiguation.

In cases where the prefix is ambiguous and would make the app appear official, the `-unofficial` suffix may be used.
