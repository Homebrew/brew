---
last_review_date: 2025-05-28
---

# `brew livecheck`

The `brew livecheck` command finds the newest version of a formula or cask's software by checking upstream. Livecheck has [strategies](/rubydoc/Homebrew/Livecheck/Strategy.html) to identify versions from various sources, such as Git repositories, websites, etc.

## Behaviour

When livecheck isn't given instructions for how to check for upstream versions, it does the following by default:

1. Collect a list of URLs to check.

* For formulae: use their `stable`, `head`, and `homepage` URLs, in that order.
* For formula resources: use their `url`.
* For casks: use their `url` and `homepage` URLs, in that order.

1. Determine if any strategies apply to the first URL. If not, try the next URL.
1. If a strategy can be applied, use it to check for new versions.
1. Return the newest version (or an error if versions could not be found at any available URLs).

It's sometimes necessary to override this default behaviour to create a working check. If a source doesn't provide the newest version, we need to check a different one. If livecheck doesn't correctly match version text, we need to provide an appropriate regex or `strategy` block.

This can be accomplished by adding a `livecheck` block to the formula/cask/resource. For more information on the available methods, please refer to the [`Livecheck` class](/rubydoc/Livecheck.html) documentation.

## Creating a check

1. **Use the debug output to understand the situation**. `brew livecheck --debug <formula>|<cask>` provides information about which URLs livecheck tries, any strategies that apply, matched versions, etc.

1. **Research available sources to select a URL**. Try removing the file name from `stable`/`url` to see if it provides a directory listing page. If that doesn't work, try to find a page that links to the file (e.g. a download page). If it's not possible to find the newest version on the website, try checking other sources from the formula/cask. When necessary, search for other sources outside of the formula/cask.

1. **Create a regex, if necessary**. If the check works without a regex and wouldn't benefit from having one, it's usually fine to omit it. More information on creating regexes can be found in the [regex guidelines](#regex-guidelines) section.

### General guidelines

* **Only use `strategy` when it's necessary**. For example, if livecheck is already using the `Git` strategy for a URL, it's not necessary to use `strategy :git`. However, if `Git` applies to a URL but we need to use `PageMatch`, it's necessary to specify `strategy :page_match`.

* **Only use the `GithubLatest` and `GithubReleases` strategies when they are necessary and correct**. GitHub rate-limits API requests, so we only use these strategies when `Git` isn't sufficient or appropriate. `GithubLatest` should only be used if the upstream repository has a "latest" release for a suitable version and either the formula/cask uses a release asset or the `Git` strategy can't correctly identify the latest release version. `GithubReleases` should only be used if the upstream repository uses releases and both the `Git` and `GithubLatest` strategies aren't suitable.

### URL guidelines

* **A `url` is required in a `livecheck` block**. This can be a URL string (e.g. `"https://www.example.com/downloads/"`) or a formula/cask URL symbol (i.e. `:stable`, `:url`, `:head`, `:homepage`). The exception to this rule is a `livecheck` block that only uses `skip`.

* **Check for versions in the same location as the stable archive, whenever possible**.

* **Avoid checking paginated release pages, when possible**. For example, we generally avoid checking the `release` page for a GitHub project because the latest stable version can be pushed off the first page by pre-release versions. In this scenario, it's more reliable to use the `Git` strategy, which fetches all the tags in the repository.

### Regex guidelines

The `livecheck` block regex restricts matches to a subset of the fetched content and uses a capture group around the version text.

* **Regexes should be made case insensitive, whenever possible**, by adding `i` at the end (e.g. `/.../i` or `%r{...}i`). This improves reliability, as the regex will handle changes in letter case without needing modifications.

* **Regexes should only use a capturing group around the version text**. For example, in `/href=.*?example-v?(\d+(?:\.\d+)+)(?:-src)?\.t/i`, we're only using a capturing group around the version text (matching a version like `1.2`, `1.2.3`, etc.) and we're using non-capturing groups elsewhere (e.g. `(?:-src)?`).

* **Anchor the start/end of the regex to restrict its scope**. For example, on HTML pages we often match file names or version directories in `href` attribute URLs (e.g. `/href=.*?example[._-]v?(\d+(?:\.\d+)+)\.zip/i`). The general idea is that limiting scope will help exclude unwanted matches.

* **Avoid generic catchalls like `.*` or `.+`** in favor of something non-greedy and/or contextually appropriate. For example, to match characters within the bounds of an HTML attribute, use `[^"' >]+?`.

* **Use `[._-]` in place of a period/underscore/hyphen between the software name and version in a file name**. For a file named `example-1.2.3.tar.gz`, `example[._-]v?(\d+(?:\.\d+)+)\.t` will continue matching if the upstream file name format changes to `example_1.2.3.tar.gz` or `example.1.2.3.tar.gz`.

* **Use `\.t` in place of `\.tgz`, `\.tar\.gz`, etc.** There are a variety of different file extensions for tarballs (e.g. `.tar.bz2`, `tbz2`, `.tar.gz`, `.tgz`, `.tar.xz`, `.txz`, etc.) and the upstream source may switch from one compression format to another over time. `\.t` avoids this issue by matching current and future formats starting with `t`. Outside of tarballs, we use the full file extension in the regex like `\.zip`, `\.jar`, etc.

## Example `livecheck` blocks

The following examples cover a number of patterns that you may encounter. These are intended to be representative samples and can be easily adapted.

When in doubt, start with one of these examples instead of copy-pasting a `livecheck` block from a random formula/cask.

### File names

When matching the version from a file name on an HTML page, we often restrict matching to `href` attributes. `href=.*?` will match the opening delimiter (`"`, `'`) as well as any part of the URL before the file name.

```ruby
livecheck do
  url "https://www.example.com/downloads/"
  regex(/href=.*?example[._-]v?(\d+(?:\.\d+)+)\.t/i)
end
```

We sometimes make this more explicit to exclude unwanted matches. URLs with a preceding path can use `href=.*?/` and others can use `href=["']?`. For example, this is necessary when the page also contains unwanted files with a longer prefix (`another-example-1.2.tar.gz`).

### Version directories

When checking a directory listing page, sometimes files are separated into version directories (e.g. `1.2.3/`). In this case, we must identify versions from the directory names.

```ruby
livecheck do
  url "https://www.example.com/releases/example/"
  regex(%r{href=["']?v?(\d+(?:\.\d+)+)/?["' >]}i)
end
```

### Git tags

When the `stable` URL uses the `Git` strategy, the following example will only match tags like `1.2`/`v1.2`, etc.

```ruby
livecheck do
  url :stable
  regex(/^v?(\d+(?:\.\d+)+)$/i)
end
```

If tags include the software name as a prefix (e.g. `example-1.2.3`), it's easy to modify the regex accordingly: `/^example[._-]v?(\d+(?:\.\d+)+)$/i`

### Referenced formula/cask

A formula/cask can use the same check as another by using `formula` or `cask`.

```ruby
livecheck do
  formula "another-formula"
end
```

The referenced formula/cask should be in the same tap, as a reference to a formula/cask from another tap will generate an error if the user doesn't already have it tapped.

A formula resource whose version stays in sync with its parent formula versioning can use the same check with `formula :parent`.

```ruby
livecheck do
  formula :parent
end
```

### `POST` requests

Some checks require making a `POST` request, which can be accomplished by adding a `post_form` or `post_json` option to a `livecheck` block `url`.

```ruby
livecheck do
  url "https://example.com/download.php", post_form: {
    Name:     "",
    "E-mail": "",
  }
  regex(/href=.*?example[._-]v?(\d+(?:\.\d+)+)\.t/i)
end
```

`post_form` is used for form data and `post_json` is used for JSON data. Livecheck will encode the provided hash value to the appropriate format before making the request.

`POST` support only applies to strategies that use `Strategy::page_headers` or `::page_content` (directly or indirectly), so it does not apply to `ExtractPlist`, `Git`, `GithubLatest`, `GithubReleases`, etc.

### `strategy` blocks

If the upstream version format needs to be manipulated to match the formula/cask format, a `strategy` block can be used instead of a `regex`.

#### `PageMatch` `strategy` block

Here is a basic example, extracting a simple version from a page:

```ruby
livecheck do
  url "https://example.org/my-app/download"
  regex(%r{href=.*?/MyApp-(\d+(?:\.\d+)*)\.zip}i)
  strategy :page_match
end
```

More complex versions can be handled by specifying a block.

```ruby
livecheck do
  url "https://example.org/my-app/download"
  regex(%r{href=.*?/(\d+)/MyApp-(\d+(?:\.\d+)*)\.zip}i)
  strategy :page_match do |page, regex|
    match = page.match(regex)
    next if match.blank?

    "#{match[2]},#{match[1]}"
  end
end
```

In the example below, we're scanning the contents of the homepage for a date format like `2020-01-01` and converting it into `20200101`.

```ruby
livecheck do
  url :homepage
  strategy :page_match do |page|
    page.scan(/href=.*?example[._-]v?(\d{4}-\d{2}-\d{2})\.t/i)
        .map { |match| match&.first&.gsub(/\D/, "") }
  end
end
```

The `PageMatch` `strategy` block style seen here also applies to any site-specific strategy that uses `PageMatch` internally.

#### `HeaderMatch` `strategy` block

A `strategy` block for `HeaderMatch` will try to parse a version from the filename (in the `Content-Disposition` header) and the final URL (in the `Location` header). If that doesn't work, a `regex` can be specified.

```ruby
livecheck do
  url "https://example.org/my-app/download/latest"
  regex(/MyApp-(\d+(?:\.\d+)*)\.zip/i)
  strategy :header_match
end
```

If the version depends on multiple header fields, a block can be specified.

```ruby
livecheck do
  url "https://example.org/my-app/download/latest"
  strategy :header_match do |headers|
    v = headers["content-disposition"][/MyApp-(\d+(?:\.\d+)*)\.zip/i, 1]
    id = headers["location"][%r{/(\d+)/download$}i, 1]
    next if v.blank? || id.blank?

    "#{v},#{id}"
  end
end
```

#### `Git` `strategy` block

A `strategy` block for `Git` is a bit different, as the block receives an array of tag strings instead of a page content string. Similar to the `PageMatch` example, this is converting tags with a date format like `2020-01-01` into `20200101`.

```ruby
livecheck do
  url :stable
  strategy :git do |tags|
    tags.filter_map { |tag| tag[/^(\d{4}-\d{2}-\d{2})$/i, 1]&.gsub(/\D/, "") }
  end
end
```

#### `GithubLatest` `strategy` block

A `strategy` block for `GithubLatest` receives the parsed JSON data from the GitHub API for a repository's "latest" release, along with a regex. When a regex is not provided in a `livecheck` block, the strategy's default regex is passed into the `strategy` block instead.

By default, the strategy matches version text in the release's tag or title but a `strategy` block can be used to check any of the fields in the release JSON. The logic in the following `strategy` block is similar to the default behaviour but only checks the release tag instead, for the sake of demonstration:

```ruby
livecheck do
  url :stable
  regex(/^example[._-]v?(\d+(?:\.\d+)+)$/i)
  strategy :github_latest do |json, regex|
    match = json["tag_name"]&.match(regex)
    next if match.blank?

    match[1]
  end
end
```

You can find more information on the response JSON from this API endpoint in the related [GitHub REST API documentation](https://docs.github.com/en/rest/releases/releases?apiVersion=latest#get-the-latest-release).

#### `GithubReleases` `strategy` block

A `strategy` block for `GithubReleases` receives the parsed JSON data from the GitHub API for a repository's most recent releases, along with a regex. When a regex is not provided in a `livecheck` block, the strategy's default regex is passed into the `strategy` block instead.

By default, the strategy matches version text in each release's tag or title but a `strategy` block can be used to check any of the fields in the release JSON. The logic in the following `strategy` block is similar to the default behaviour but only checks the release tag instead, for the sake of demonstration:

```ruby
livecheck do
  url :stable
  regex(/^example[._-]v?(\d+(?:\.\d+)+)$/i)
  strategy :github_releases do |json, regex|
    json.map do |release|
      next if release["draft"] || release["prerelease"]

      match = release["tag_name"]&.match(regex)
      next if match.blank?

      match[1]
    end
  end
end
```

The strategy's default logic skips releases marked as draft or pre-release but this can be modified by using a `strategy` block. Removing the `release["prerelease"]` condition from the previous example would allow us to work with pre-release releases, though the regex may also need to be adapted to handle unstable version formats.

You can find more information on the response JSON from this API endpoint in the related [GitHub REST API documentation](https://docs.github.com/en/rest/releases/releases?apiVersion=latest#list-releases).

#### `Crate` `strategy` block

A `strategy` block for `Crate` receives parsed JSON data from the registry API's `versions` endpoint and either the provided or default strategy regex. The strategy uses the following logic by default, so this `strategy` block may be a good starting point for a modified approach:

```ruby
livecheck do
  url :stable
  strategy :crate do |json, regex|
    json["versions"]&.map do |version|
      next if version["yanked"]
      next unless (match = version["num"]&.match(regex))

      match[1]
    end
  end
end
```

#### `ElectronBuilder` `strategy` block

A `strategy` block for `ElectronBuilder` fetches content at a URL and parses it as an electron-builder appcast in YAML format. It's used for casks of macOS applications built using the Electron framework.

```ruby
livecheck do
  url "https://example.org/my-app/latest-mac.yml"
  strategy :electron_builder
end
```

If you need to modify the version, you can access the YAML hash in the `strategy` block like so:

```ruby
livecheck do
  url "https://example.org/my-app/latest-mac.yml"
  strategy :electron_builder do |yaml|
    yaml["version"]&.gsub(/\D/, "")
  end
end
```

Similarly, you can work with the `files` array like this:

```ruby
livecheck do
  url "https://example.org/my-app/latest-mac.yml"
  regex(/MyApp[._-]v?(\d+(?:\.\d+)+)-(\h+)\.dmg/i)
  strategy :electron_builder do |yaml, regex|
    yaml["files"]&.map do |file|
      match = file["url"]&.match(regex)
      next if match.blank?

      "#{match[1]},#{match[2]}"
    end
  end
end
```

#### `Json` `strategy` block

A `strategy` block for `Json` receives parsed JSON data and, if provided, a regex. For example, if we have an object containing an array of objects with a `version` string, we can select only the members that match the regex and isolate the relevant version text as follows:

```ruby
livecheck do
  url "https://www.example.com/example.json"
  regex(/^v?(\d+(?:\.\d+)+)$/i)
  strategy :json do |json, regex|
    json["versions"].select { |item| item["version"]&.match?(regex) }
                    .map { |item| item["version"][regex, 1] }
  end
end
```

#### `Sparkle` `strategy` block

A `strategy` block for `Sparkle` receives an `item` which has methods for the `version`, `short_version`, `nice_version`, `url`, `channel` and `title`. It expects a URL for an XML feed providing release information to a macOS application that self-updates using the Sparkle framework. This URL can be found within the app bundle as the `SUFeedURL` property in `Contents/Info.plist` or by using the [`find-appcast`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/cmd/find-appcast.rb) command. Run it with:

```bash
brew find-appcast '/path/to/application.app'
```

The default pattern for the `Sparkle` strategy is to generate `"#{item.short_version},#{item.version}"` from `sparkle:shortVersionString` and `sparkle:version` if both are set. In the example below, the returned value also includes a needed download ID from the `url`:

```ruby
livecheck do
  url "https://www.example.com/example.xml"
  strategy :sparkle do |item|
    "#{item.short_version},#{item.version}:#{item.url[%r{/(\d+)/[^/]+\.zip}i, 1]}"
  end
end
```

To use only one, specify `&:version`, `&:short_version` or `&:nice_version`:

```ruby
livecheck do
  url "https://www.example.com/example.xml"
  strategy :sparkle, &:short_version
end
```

If the value returned by `item` is not the most recent or not what's desired, passing `items` instead will allow iterating over all the items in the feed:

```ruby
livecheck do
  url "https://www.example.com/example.xml"
  strategy :sparkle do |items|
    items.find { |item| item.channel.nil? }&.short_version
  end
end
```

#### `Xml` `strategy` block

A `strategy` block for `Xml` receives an `REXML::Document` object and, if provided, a regex. For example, if the XML contains a `versions` element with nested `version` elements and their inner text contains the version string, we could extract it using a regex as follows:

```ruby
livecheck do
  url "https://www.example.com/example.xml"
  regex(/v?(\d+(?:\.\d+)+)/i)
  strategy :xml do |xml, regex|
    xml.get_elements("versions//version").map { |item| item.text[regex, 1] }
  end
end
```

For more information on how to work with an `REXML::Document` object, please refer to the [`REXML::Document`](https://ruby.github.io/rexml/REXML/Document.html) and [`REXML::Element`](https://ruby.github.io/rexml/REXML/Element.html) documentation.

#### `Yaml` `strategy` block

A `strategy` block for `Yaml` receives parsed YAML data and, if provided, a regex. Borrowing the `Json` example, if we have an object containing an array of objects with a `version` string, we can select only the members that match the regex and isolate the relevant version text as follows:

```ruby
livecheck do
  url "https://www.example.com/example.yaml"
  regex(/^v?(\d+(?:\.\d+)+)$/i)
  strategy :yaml do |yaml, regex|
    yaml["versions"].select { |item| item["version"]&.match?(regex) }
                    .map { |item| item["version"][regex, 1] }
  end
end
```

#### `ExtractPlist` `strategy` block

If no means are available online for checking which version of a macOS package is current, as a last resort the `:extract_plist` strategy will have `brew livecheck` download the artifact and retrieve its version string from contained `.plist` files.

```ruby
livecheck do
  url :url
  strategy :extract_plist
end
```

A `strategy` block for `ExtractPlist` receives a hash containing keys for each found bundle identifier and `item`s with methods for each `version` and `short_version`.

```ruby
livecheck do
  url :url
  strategy :extract_plist do |items|
    items["com.example.MyApp"].short_version
  end
end
```

Note that if a package uses this livecheck strategy it will be excluded from [autobumping](Autobump.md) as this strategy has negative impact on CI time.

### `throttle`

For software with extremely frequent releases that don't all need to be published as formula/cask updates, livecheck can be set to reduce how many versions it surfaces by using `throttle`. In this example, only versions whose last component is divisible by 10 will be returned.

```ruby
livecheck do
  url :stable
  regex(/^v?(\d+(?:\.\d+)+)$/i)
  throttle 10
end
```

### `skip`

Livecheck automatically skips some formulae/casks for a number of reasons (deprecated, disabled, etc.). However, on rare occasions we need to use a `livecheck` block to do a manual skip. The `skip` method takes a string containing a very brief reason for skipping.

```ruby
livecheck do
  skip "No version information available"
end
```
