---
last_review_date: "2026-07-18"
redirect_from:
  - /Python-for-Formula-Authors
  - /Node-for-Formula-Authors
---

# Language-Specific Formulae

This guide covers the language-specific parts of formula authoring.
The [Formula Cookbook](Formula-Cookbook.md), [Acceptable Formulae](Acceptable-Formulae.md) and [shared package acceptance policy](Package-Acceptance-Policy.md) still apply.

## Shared requirements

- Declare every language runtime needed at build or runtime rather than relying on the contributor's environment.
- Use immutable, checksummed sources and a reproducible dependency set.
- Install application dependencies inside the formula prefix so they do not modify a user's global language environment.
- Do not let the installed application download required code automatically at runtime.
- Add a functional test that exercises installed behaviour rather than only checking that an executable exists.

Ordinary libraries already handled well by a language package manager are generally not useful as standalone formulae.
Command-line applications, substantial native libraries and bindings needed by other formulae can be appropriate when they meet the acceptance policy.

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
