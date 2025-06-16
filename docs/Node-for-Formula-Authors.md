---
last_review_date: "1970-01-01"
---

# Node for Formula Authors

This document explains how to successfully use Node and npm in a Node module based Homebrew formula.

## Running `npm install`

Homebrew provides a helper method `std_npm_args` to set up the correct environment for npm and return arguments for `npm install`. Your formula should use this when invoking `npm install`. The syntax for a standard Node module installation is:

```ruby
system "npm", "install", *std_npm_args
```

## Download URL

If the Node module is also available on the npm registry, we prefer npm-hosted release tarballs over GitHub (or elsewhere) hosted source tarballs. The advantages of these tarballs are that they don't include the files from the `.npmignore` (such as tests) resulting in a smaller download size and that any possible transpilation step is already done (e.g. no need to compile CoffeeScript files as a build step).

The npm registry URLs usually have the format of:

    https://registry.npmjs.org/<name>/-/<name>-<version>.tgz

Alternatively you could `curl` the JSON at `https://registry.npmjs.org/<name>` and look for the value of `versions[<version>].dist.tarball` for the correct tarball URL.

## Dependencies

Node modules which are compatible with the latest Node version should declare a dependency on the `node` formula.

```ruby
depends_on "node"
```

If your formula requires being executed with an older Node version you should use one of its versioned formulae (e.g. `node@20`).

### Special requirements for native addons

If your Node module is a native addon or has a native addon somewhere in its dependency tree you have to declare an additional dependency. Since the compilation of the native addon results in an invocation of `node-gyp` we need an additional build time dependency on `"python"` (because GYP depends on Python).

```ruby
depends_on "python" => :build
```

Also note that such a formula would only be compatible with the same Node major version it originally was compiled with. This means that we need to revision every formula with a Node native addon with every major version bump of the `node` formula. To make sure we don't overlook your formula on a Node major version bump, write a meaningful test which would fail in such a case (being invoked with an ABI-incompatible Node version).

## Installation

Node modules should be installed to `libexec`. This prevents the Node modules from contaminating the global `node_modules`, which is important so that npm doesn't try to manage Homebrew-installed Node modules.

In the following we distinguish between two types of Node modules installed using formulae:

- formulae for standard Node modules compatible with npm's global module format which should use [`std_npm_args`](#installing-global-style-modules-with-std_npm_args-to-libexec) (like [`angular-cli`](https://github.com/Homebrew/homebrew-core/blob/master/Formula/a/angular-cli.rb) or [`webpack`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/w/webpack.rb))
- formulae where the `npm install` call is not the only required install step (e.g. need to also compile non-JavaScript sources) which have to use [`std_npm_args`](#installing-module-dependencies-locally-with-std_npm_args) (like [`emscripten`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/e/emscripten.rb) or [`grunt-cli`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/g/grunt-cli.rb))

What both methods have in common is that they are setting the correct environment for using npm inside Homebrew and are returning the arguments for invoking `npm install` for their specific use cases. This includes fixing an important edge case with the npm cache (caused by Homebrew's redirection of `HOME` during the build and test process) by using our own custom `npm_cache` inside `HOMEBREW_CACHE`, which would otherwise result in very long build times and high disk space usage.

### Installing global style modules with `std_npm_args` to `libexec`

In your formula's `install` method, simply `cd` to the top level of your Node module if necessary and then use `system` to invoke `npm install` with `std_npm_args` like:

```ruby
system "npm", "install", *std_npm_args
```

This will install your Node module in npm's global module style with a custom prefix to `libexec`. All your modules' executables will be automatically resolved by npm into `libexec/bin` for you, which are not symlinked into Homebrew's prefix. To make sure these are installed, we need to symlink all executables to `bin` with:

```ruby
bin.install_symlink Dir["#{libexec}/bin/*"]
```

### Installing module dependencies locally with `std_npm_args`

In your formula's `install` method, do any installation steps which need to be done before the `npm install` step and then `cd` to the top level of the included Node module. Then, use `system` to invoke `npm install` with `std_npm_args(prefix: false)` like:

```ruby
system "npm", "install", *std_npm_args(prefix: false)
```

This will install all of your Node modules' dependencies to your local build path. You can now continue with your build steps and handle the installation into the Homebrew prefix on your own, following the [general Homebrew formula instructions](Formula-Cookbook.md).

## Example

Installing a standard Node module based formula would look like this:

```ruby
class Foo < Formula
  desc "An example formula"
  homepage "https://example.com"
  url "https://registry.npmjs.org/foo/-/foo-1.4.2.tgz"
  sha256 "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1"

  depends_on "node"
  # uncomment if there is a native addon inside the dependency tree
  # depends_on "python" => :build

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    # add a meaningful test here, version isn't usually meaningful
    assert_match version.to_s, shell_output("#{bin}/foo --version")
  end
end
```

## Tooling

You can use [homebrew-npm-noob](https://github.com/zmwangx/homebrew-npm-noob) to automatically generate a formula like the example above for an npm package.
