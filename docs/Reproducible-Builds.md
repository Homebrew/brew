---
last_review_date: "2026-07-18"
---

# Reproducible Builds

The Homebrew build environment is designed with [reproducible builds](https://reproducible-builds.org/) as a goal where possible. Some convenience tools are also available to formula authors to help achieve deterministic builds.

## Build time

Some build tools embed or record the time at which the build occurs. This can cause build artifacts to differ between repeated builds of the same sources. To avoid this issue, the Homebrew build environment sets the [`SOURCE_DATE_EPOCH` environment variable](https://reproducible-builds.org/docs/source-date-epoch/) to the modification time of the source code for tools that consume it.

In cases where a build time must be manually set, `time` is a Ruby `Time` object containing the same timestamp as the `SOURCE_DATE_EPOCH` environment variable.
Methods provided by Ruby on `Time` objects can then be used to format this time into the desired format.

```ruby
def install
  system "make", "install",
         "VERSION=#{version}",
         "DATE=#{time.iso8601}",
         "PREFIX=#{prefix}"
end
```

Use `time.iso8601` or `time.strftime` when upstream's build interface requires a formatted timestamp.

## Reproducible gzip compression

Some formulae may create gzip-compressed files during their build process (for example, compressing manpages or other data files). Build machines may provide different implementations of the `gzip` utility, and by default `gzip` will record the modification time of the file being compressed, which usually varies depending on the build time. Thus, relying on the build machine's `gzip` utility will usually result in non-reproducible outputs being part of the build.

To avoid this issue, Homebrew provides the `Utils::Gzip.compress` helper function for situations where reproducible `gzip` compression is needed. This function accepts one or more paths to be compressed and places the compressed files next to the original with a `.gz` suffix, just like the `gzip` utility does. It also returns an array of `Pathname` objects which can be consumed by other methods.

```ruby
def install
  system "make", "install"
  man1.install Utils::Gzip.compress("mycommand.1")
end
```

```ruby
def install
  system "make", "install"
  (pkgshare/"data").install Utils::Gzip.compress(*Dir["#{buildpath}/path/to/some/folder/contents/*"])
end
```

Pass one path or multiple paths to the same helper rather than invoking the host's `gzip` directly.

## Relocatability

Some formulae or build tools record paths specific to the build environment in configuration files or in binaries. When building redistributable bottles, Homebrew searches through the built files and replaces paths to common Homebrew locations, such as the Homebrew prefix and the Cellar, with a placeholder like `@@HOMEBREW_PREFIX@@` or `@@HOMEBREW_CELLAR@@`. When bottles are installed, Homebrew expands these placeholders to the respective paths on the end user's machine.

This allows for some bottles to be used by users that may have Homebrew installed in a non-default prefix. It also results in bit-for-bit identical bottles between platforms where the location of Homebrew is the only difference.

This search and replace process occurs automatically and does not require any additional action from formula authors to use it.
