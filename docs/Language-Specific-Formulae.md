---
last_review_date: "2026-07-18"
redirect_from:
  - /Python-for-Formula-Authors
  - /Node-for-Formula-Authors
---

# Language-Specific Formulae

This guide covers the language-specific parts of formula authoring.
The [Formula Cookbook](Formula-Cookbook.md), [Acceptable Formulae](Acceptable-Formulae.md) and [shared package acceptance policy](Package-Acceptance-Policy.md) still apply.

- Table of Contents
{:toc}

## Shared requirements

- Declare every language runtime needed at build or runtime rather than relying on the contributor's environment.
- Use immutable, checksummed sources and a reproducible dependency set.
- Install application dependencies inside the formula prefix so they do not modify a user's global language environment.
- Do not let the installed application download required code automatically at runtime.
- Add a functional test that exercises installed behaviour rather than only checking that an executable exists.

Ordinary libraries already handled well by a language package manager are generally not useful as standalone formulae.
Command-line applications, substantial native libraries and bindings needed by other formulae can be appropriate when they meet the acceptance policy.

## C and C++

Use Homebrew's selected compiler and build environment rather than hardcoding `gcc`, `clang` or SDK paths.
See [compiler selection](Formula-Cookbook.md#compiler-selection) when upstream requires a particular compiler and [C++ standard libraries](C%2B%2B-Standard-Libraries.md) when linking C++ dependencies.
Declare build tools such as `cmake`, `meson`, `ninja` and `pkgconf` as build dependencies when needed.

Use the [standard build arguments](Formula-Cookbook.md#standard-arguments) for upstream's build system.
For example, a CMake project can be built and installed with:

```ruby
system "cmake", "-S", ".", "-B", "build", *std_cmake_args
system "cmake", "--build", "build"
system "cmake", "--install", "build"
```

Declare linked libraries as runtime dependencies and use Homebrew's copies instead of downloading or building additional bundled copies where possible.
The same build-system guidance applies to Objective-C and Objective-C++ projects.

## Python

### Applications, libraries and bindings

Python applications provide user-facing behaviour and are good formula candidates even when they are published on PyPI.
Users should not need to know that an application is implemented in Python or manually add its modules to `sys.path`.

Ordinary importable libraries should normally be installed in a project environment with pip rather than packaged as formulae.
A library may be appropriate when it has a substantial native build, is required by other formulae or needs Homebrew-specific integration.
Bindings supplied by a non-Python project may be installed with that project when they are useful and maintainable.

### Python dependency and resources

Python applications in `homebrew/core` use its current versioned Python formula.
Update the dependency when `homebrew/core` moves to a new supported Python minor version.

All Python module dependencies and their recursive dependencies that are not provided by another formula must be declared as [`resource`](/rubydoc/Formula.html#resource-class_method)s.
This keeps every source version and SHA-256 checksum in the formula, and Homebrew's pip helper installs with dependency resolution disabled.

Use `brew update-python-resources <formula>` to generate or update the resource blocks.
Use `--print-only` to inspect the result without changing the formula.
For third-party taps, `--ignore-errors` records every discovered resource and leaves a `RESOURCE-ERROR` comment for each one that cannot be resolved.
This option is disabled for all official Homebrew taps, which require complete resolution.
Verify the generated URLs and checksums.

The `pypi_packages` stanza records resolver configuration that should remain with the formula.
Use `package_name` when the formula name or URL does not identify the correct PyPI package, `extra_packages` for additional dependency roots, `exclude_packages` for packages provided by another formula and `dependencies` for formulae that must be installed while resources are resolved:

```ruby
pypi_packages package_name:     "upstream-name",
              extra_packages:   "extra-package",
              exclude_packages: "package-from-homebrew",
              dependencies:     "resolver-dependency"
```

If the stable URL is not on PyPI and PyPI has no release matching the formula's version, `package_name` (including any extras such as `upstream-name[all]`) is resolved against the stable URL instead.

### Installing a Python application

Include `Language::Python::Virtualenv` and use `virtualenv_install_with_resources` for the standard application layout.
The examples use `3.y` as a placeholder for the current Python minor version used by `homebrew/core`:

```ruby
class Foo < Formula
  include Language::Python::Virtualenv

  desc "Example Python command-line application"
  homepage "https://example.com/foo"
  url "https://files.pythonhosted.org/packages/.../foo-1.0.tar.gz"
  sha256 "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1"

  depends_on "python@3.y"

  resource "dependency" do
    url "https://files.pythonhosted.org/packages/.../dependency-1.2.3.tar.gz"
    sha256 "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1"
  end

  def install
    virtualenv_install_with_resources
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/foo --version")
  end
end
```

The helper creates a virtual environment under `libexec`, installs every resource and links newly installed commands into `bin`.
Use its `start_with:`, `end_with:` and `without:` keywords when only the resource order or selection differs.
Use `virtualenv_create` directly when additional installation steps require explicit calls to `pip_install` or `pip_install_and_link`.

### Installing Python bindings

Declare the same versioned Python dependency used by other current `homebrew/core` formulae.
For a standard `pyproject.toml` or `setup.py` package, install through the declared interpreter and Homebrew's pip arguments:

```ruby
system "python3.y", "-m", "pip", "install", *std_pip_args(build_isolation: true), "./source/python"
```

`std_pip_args` delays packages published within Homebrew's release-cooldown period, disables automatic dependency resolution and binary wheels and installs only under the requested prefix.
Match the executable to the declared dependency whenever the Python minor version changes.
Use upstream build-system options to direct bindings into the formula prefix rather than patching global Python paths.

### Build-system integration for Python bindings

When more than one Python is available in the dependency graph, pass the declared interpreter to the build system explicitly.

- For CMake, use the variable recognised by upstream's discovery module, commonly `Python3_EXECUTABLE`, `Python_EXECUTABLE` or the older `PYTHON_EXECUTABLE`.
- For Meson, check how upstream calls `find_installation()` and use its supported options to select the interpreter.
  - If Meson cannot infer Homebrew's installation directories, set `python.purelibdir` or `python.platlibdir` to a path inside the formula prefix.
- For Autotools projects, use an upstream `--with-python` option when available or disable the build-system installation and install the bindings with the declared interpreter and `std_pip_args`.

## Node.js

### Source and dependency

Prefer the release tarball published to the npm registry when it contains the complete distributable application.
Registry tarballs normally omit development-only files and include upstream's published build output.
Use the exact tarball URL and SHA-256 checksum for the packaged version.
The usual registry URL has the form `https://registry.npmjs.org/<name>/-/<name>-<version>.tgz`.

Applications compatible with the current Node.js release should declare:

```ruby
depends_on "node"
```

Use a versioned Node.js formula only when upstream documents that requirement and that formula remains supported.

### Standard npm installation

Install a normal npm application into `libexec` and link its executables:

```ruby
class Foo < Formula
  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink libexec.glob("bin/*")
  end
end
```

`std_npm_args` uses Homebrew's npm cache, applies the package release cooldown, builds native dependencies from source and installs in npm's global layout under `libexec`.
It ignores lifecycle scripts by default to reduce the amount of package code executed during installation.

If the package requires an install-phase lifecycle script such as `postinstall`, review every enabled script and dependency before using:

```ruby
system "npm", "install", *std_npm_args(ignore_scripts: false)
```

Explain why those scripts are necessary in the pull request.

Use a local npm layout when npm is only one stage of a larger build:

```ruby
system "npm", "install", *std_npm_args(prefix: false)
```

Continue the upstream build, then install the resulting files into the formula prefix explicitly.

### Native addons

A dependency tree containing native addons also needs the tools required by `node-gyp`.
Declare Python as a build dependency when the build invokes it:

```ruby
depends_on "python" => :build
```

Native addons are tied to a Node.js ABI.
Add a functional test that exposes an incompatible Node.js major version so maintainers know when the formula needs a revision bump.

## Go

### Dependencies and installation

Declare Go as a build dependency with `depends_on "go" => :build`.
Homebrew sets `GOTOOLCHAIN=local` so builds use the declared Go toolchain rather than downloading another version automatically.

Use upstream's `go.mod` and `go.sum` to download and verify module dependencies in a [`fetch`](/rubydoc/Formula.html#fetch-instance_method) method before building without network access:

```ruby
class Foo < Formula
  depends_on "go" => :build

  deny_network_access!

  def fetch
    system "go", "mod", "download"
  end

  def install
    system "go", "build", *std_go_args
  end
end
```

Homebrew configures the Go build and module caches for both phases.
If upstream supplies vendored dependencies, build with `-mod=vendor` and omit the module download step.
Append the main package path, such as `"./cmd/foo"`, to the build command when the executable is not in the module root.

### Standard build arguments

[`std_go_args`](/rubydoc/Formula.html#std_go_args-instance_method) sets `-trimpath` and writes the executable to `bin/name` by default.
It also strips debugging information with `-s -w` unless building with debug symbols.
Use `output:` for a different executable name, `ldflags:` for linker flags, `gcflags:` for compiler flags and `tags:` for build tags:

```ruby
system "go", "build", *std_go_args(output: bin/"foo", ldflags: "-X main.version=#{version}", tags: ["feature"]), "./cmd/foo"
```

`ldflags:`, `gcflags:` and `tags:` accept strings or arrays of strings.
`ldflags:` also accepts `:goreleaser`.
The helper joins build tags with commas and adds the standard stripping flags to custom linker flags unless building with debug symbols.

### GoReleaser metadata

For projects that use [GoReleaser's default linker flags](https://goreleaser.com/customization/builds/builders/go/#options), use:

```ruby
system "go", "build", *std_go_args(ldflags: :goreleaser)
```

This sets `main.version`, `main.commit`, `main.date` and `main.builtBy` from the formula's metadata.
The commit comes from the source revision or Git archive when available, falling back to the tap owner or `Homebrew` when it cannot be determined.
The builder is the tap owner or `Homebrew`.
This helper does not read `.goreleaser.yaml` or other GoReleaser configuration; pass custom `ldflags:` when upstream uses different variable names or values.

## Rust

Declare `depends_on "rust" => :build` and use upstream's `Cargo.lock` to keep dependency versions reproducible.
Fetch dependencies with [`std_cargo_fetch_args`](/rubydoc/Formula.html#std_cargo_fetch_args-instance_method), then install executables with [`std_cargo_args`](/rubydoc/Formula.html#std_cargo_args-instance_method):

```ruby
class Foo < Formula
  depends_on "rust" => :build

  deny_network_access!

  def fetch
    system "cargo", "fetch", *std_cargo_fetch_args
  end

  def install
    system "cargo", "install", *std_cargo_args
  end
end
```

Both helpers pass `--locked`.
`std_cargo_args` builds from the current directory, installs under `prefix` and adds `--offline` when the formula defines `fetch`.
Use `path:` for a workspace member, `features:` for additional Cargo features and `root:` to change the installation prefix.
Declare native libraries used by crates as formula dependencies rather than allowing their build scripts to download them.

Homebrew sets `CARGO_REGISTRY_GLOBAL_MIN_PUBLISH_AGE` to apply its release cooldown when Cargo 1.100 or newer resolves registry dependencies.

## Java

Declare the JDK used to build or run the software.
Use `openjdk` for software that supports the current JDK, or a supported versioned formula when upstream requires a specific release:

```ruby
depends_on "openjdk@21"
```

Use a build-only dependency only when the installed software does not need Java at runtime.

Wrap installed commands with `Language::Java.java_home_env` when they must always use the declared JDK:

```ruby
bin.env_script_all_files libexec/"bin", Language::Java.java_home_env("21")
```

Use `Language::Java.overridable_java_home_env` when the declared JDK should be the default but upstream supports a user-selected `JAVA_HOME`:

```ruby
(bin/"foo").write_env_script libexec/"bin/foo", Language::Java.overridable_java_home_env("21")
```

The helper's version must match the formula dependency.
Do not embed a Cellar path or a macOS-only JDK location in an installed script.

Java bytecode published by upstream may be installed directly when it meets the formula acceptance policy.
When building with Maven, Gradle or another tool, ensure its dependency inputs are versioned and reproducible.

## Perl

Declare `depends_on "perl"` when the application needs Homebrew's Perl, or `uses_from_macos "perl"` when the macOS interpreter is sufficient.
Declare CPAN dependencies not supplied by another formula as checksummed resources and install them under `libexec` before the application.
For a `Makefile.PL` project, use an installation base inside the formula and preserve its module search path in command wrappers:

```ruby
class Foo < Formula
  depends_on "perl"

  def install
    ENV.prepend_create_path "PERL5LIB", libexec/"lib/perl5"
    ENV.prepend_path "PERL5LIB", libexec/"lib"

    system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}"
    system "make", "install"
    bin.env_script_all_files libexec/"bin", PERL5LIB: ENV.fetch("PERL5LIB")
  end
end
```

Run the same installation steps inside each resource's `stage` block before building the application.
For a `Build.PL` project, use `perl Build.PL --install_base <directory>`, then `./Build` and `./Build install` instead.
For scripts whose build system does not select the interpreter, include `Language::Perl::Shebang` and use `rewrite_shebang detected_perl_shebang, <script>` as described in [rewriting a script shebang](Formula-Cookbook.md#rewriting-a-script-shebang).

## Ruby

Use Bundler with an upstream `Gemfile.lock` when it records the complete dependency set.
Install the bundle under `libexec` rather than into the user's gem environment:

```ruby
ENV["GEM_HOME"] = libexec
ENV["BUNDLE_WITHOUT"] = "development"
system "bundle", "install"
```

Install commands from that environment and preserve `GEM_HOME` in their wrappers:

```ruby
bin.install libexec/"bin/foo"
bin.env_script_all_files libexec/"bin", GEM_HOME: ENV.fetch("GEM_HOME")
```

If upstream does not provide a usable lock file, declare immutable, checksummed resources or use another reproducible installation method accepted for that ecosystem.

## Fortran

Declare `depends_on "gcc"` to use its `gfortran` compiler.
Keep this as a runtime dependency when the installed software links to GCC's Fortran runtime libraries.
Pass `FC=gfortran` to upstream's build system when it needs an explicit compiler selection and use its usual [standard build arguments](Formula-Cookbook.md#standard-arguments).

## Lua

Declare `lua` or `luajit` according to the interpreter and module ABI supported by upstream.
Install application-specific Lua modules under `libexec` and set `LUA_PATH` for Lua sources and `LUA_CPATH` for native modules in command wrappers when needed.
Preserve the interpreter's default search paths with `;;` in these variables.
Build native modules against the same interpreter used by the installed application.
Use checksummed resources or upstream's pinned dependency set instead of installing unversioned rocks into a global LuaRocks tree.

## Shell scripts

Install executable scripts with `bin.install`.
Declare `bash` or `zsh` as a runtime dependency when the script requires Homebrew's shell and ensure its shebang selects that interpreter through the formula's stable `opt` path.
Use `/bin/sh` only for scripts that work with the system's POSIX shell.
Declare external commands used by the script as dependencies and test a functional invocation with the installed script's full path.

## Vala

Declare `depends_on "vala" => :build` when the build invokes `valac`.
Declare GLib and any other native libraries used by the generated code as runtime dependencies.
Build through upstream's Meson or Autotools configuration using `std_meson_args` or `std_configure_args` rather than bypassing it with a separate compiler invocation.
If a release tarball supplies generated C sources, check whether the build actually needs Vala before adding the compiler dependency.

## Swift

Use `uses_from_macos "swift" => :build` for projects that build with the macOS toolchain and Homebrew's Swift on Linux.
Declare an Xcode requirement separately when upstream needs the full Xcode installation rather than the Command Line Tools.
Use upstream's `Package.resolved` for dependency versions and resolve packages in `fetch` when downloads are needed:

```ruby
class Foo < Formula
  uses_from_macos "swift" => :build

  deny_network_access!

  def fetch
    system "swift", "package", "resolve", "--disable-sandbox"
  end

  def install
    system "swift", "build", *std_swift_args
    bin.install ".build/release/foo"
  end
end
```

[`std_swift_args`](/rubydoc/Formula.html#std_swift_args-instance_method) selects a release build, sets parallelism and adds platform-specific arguments for Homebrew's build environment.
Install any resource bundles required by the executable alongside it in the layout expected by upstream.

## Haskell

Declare `cabal-install` and `ghc` as build dependencies.
Use upstream's `cabal.project.freeze` or another pinned dependency plan when available and download dependencies before the offline build:

```ruby
class Foo < Formula
  depends_on "cabal-install" => :build
  depends_on "ghc" => :build

  deny_network_access!

  def fetch
    system "cabal", "v2-update"
    system "cabal", "v2-install", "--only-download", *std_cabal_v2_args
  end

  def install
    system "cabal", "v2-install", "--offline", *std_cabal_v2_args
  end
end
```

[`std_cabal_v2_args`](/rubydoc/Formula.html#std_cabal_v2_args-instance_method) sets parallelism and dependency-resolution limits and installs executables by copying them into `bin`.
Use `installdir:` to change that directory, or `installdir: false` when passing the helper to `v2-configure` or `v2-build`.
Declare native libraries such as `gmp` and `libffi` when the installed executable links to them.

## Tcl and Tk

Declare `tcl-tk` when the application needs Homebrew's Tcl interpreter, Tk widgets or native libraries.
Select the declared dependency's `tclsh`, `wish` and build configuration files rather than relying on macOS system copies.
Install application-specific Tcl packages under the formula prefix and set `TCLLIBPATH` in a wrapper if upstream's installation layout does not make them discoverable.
Native extensions must be built for the same Tcl version used at runtime.

## OCaml

Declare `ocaml` and any required tools such as `opam`, `dune` or `ocaml-findlib` as build dependencies.
When using opam, set `OPAMROOT` to a directory inside `buildpath` and initialise with `--compiler=ocaml-system --no-setup` to use the declared compiler without modifying shell configuration.
Use upstream's pinned package set and download dependencies during `fetch` before compiling without network access.
Keep the compiler switch and dependency configuration consistent between `fetch` and `install`.
Install executables into `bin` and declare any native libraries they need at runtime.

## Zig

Declare `depends_on "zig" => :build` unless the installed application also invokes Zig at runtime.
Use upstream's `build.zig.zon` dependency hashes and fetch before building:

```ruby
class Foo < Formula
  depends_on "zig" => :build

  deny_network_access!

  def fetch
    system "zig", "build", "--fetch"
  end

  def install
    system "zig", "build", *std_zig_args
  end
end
```

[`std_zig_args`](/rubydoc/Formula.html#std_zig_args-instance_method) selects the installation prefix, release mode and target CPU.
Use `release_mode: :safe` or `release_mode: :small` when upstream needs an alternative to the default `:fast` mode.
Use a supported versioned Zig formula when upstream requires a specific compiler release.

## PHP

Declare `php` as a runtime dependency, or a supported versioned PHP formula when upstream requires it.
For an executable PHAR with a PHP shebang, install it and select the declared interpreter with Homebrew's shebang helper:

```ruby
class Foo < Formula
  include Language::PHP::Shebang

  depends_on "php"

  def install
    bin.install "foo.phar" => "foo"
    rewrite_shebang detected_php_shebang, bin/"foo"
  end
end
```

For applications built with Composer, declare `composer` as a build dependency and use upstream's `composer.lock`.
Install production dependencies within the formula prefix and review any Composer scripts or plugins enabled during installation.

## C# and F# (.NET)

Declare `dotnet`, or a supported versioned .NET formula matching upstream's target framework.
For a [framework-dependent deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/), retain it as a runtime dependency and publish with `--no-self-contained` into `libexec`.
Wrap the installed launcher with `DOTNET_ROOT` pointing to the dependency's `opt_libexec`, for example:

```ruby
(bin/"foo").write_env_script libexec/"foo", DOTNET_ROOT: formula_opt_libexec("dotnet")
```

Use upstream's NuGet lock files when available.
If restoring dependencies in `fetch`, use the same target framework and runtime options when publishing with `--no-restore` in `install`.

## Erlang and Elixir

Declare `erlang` for applications that run on the Erlang VM and `rebar3` as a build dependency when upstream uses it.
Elixir applications need `elixir` and upstream's `mix.lock`; Erlang projects should retain their `rebar.lock`.
Download the locked dependencies during `fetch` before compiling and assembling the release or escript in `install`.
Install complete release directories under `libexec`, or standalone escripts into `bin`, and ensure launchers select the declared runtime.
Keep the runtime dependency unless the installed release includes its own runtime built from source.

## Crystal

Declare `depends_on "crystal" => :build` and use upstream's `shard.lock` for dependency versions.
Fetch production shards before building with [`std_shards_args`](/rubydoc/Formula.html#std_shards_args-instance_method):

```ruby
class Foo < Formula
  depends_on "crystal" => :build

  deny_network_access!

  def fetch
    system "shards", "install", "--production", "--skip-postinstall"
  end

  def install
    system "shards", "build", *std_shards_args
    bin.install "bin/foo"
  end
end
```

The helper selects a production release build and preserves debugging information when requested.
Declare native libraries linked by the executable, such as `bdw-gc`, as runtime dependencies.
Review any required shard post-install scripts before enabling them.

## Other languages

For less common ecosystems, use the same source, dependency and installation requirements above with the toolchain required by upstream:

| Language                        | Toolchain dependency              | Formula considerations                                                                                                         |
| ------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| D                               | `ldc`                             | Declare the compiler as a build dependency and retain any linked runtime libraries as dependencies.                            |
| Nim                             | `nim`                             | Declare the compiler as a build dependency and use pinned resources or a locked Nimble dependency set.                         |
| Scheme                          | An implementation such as `guile` | Keep the interpreter as a runtime dependency and install modules for that implementation's version.                            |
| Common Lisp                     | An implementation such as `sbcl`  | Build saved images with the declared implementation and retain it when the installed launcher needs it.                        |
| R                               | `r`                               | Install application-specific packages under `libexec` and set `R_LIBS_SITE` in command wrappers when needed.                   |
| Clojure, Scala and Kotlin       | A supported JDK and build tools   | Follow the [Java guidance](#java) for runtime selection and declare the compiler as a build dependency when compiling sources. |
| Pascal                          | `fpc`                             | Declare the compiler as a build dependency and install the executable and any required native libraries.                       |
