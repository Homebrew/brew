---
last_review_date: "1970-01-01"
---

# Python for Formula Authors

This document explains how to successfully use Python in a Homebrew formula.

Homebrew draws a distinction between Python **applications** and Python **libraries**. The difference is that users generally do not care that applications are written in Python; it is unusual that a user would expect to be able to `import foo` after installing an application. Examples of applications are [`ansible`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/a/ansible.rb) and [`jrnl`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/j/jrnl.rb).

Python libraries exist to be imported by other Python modules; they are often dependencies of Python applications. They are usually no more than incidentally useful in a terminal. Examples of libraries are [`certifi`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/c/certifi.rb) and [`numpy`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/n/numpy.rb).

Bindings are a special case of libraries that allow Python code to interact with a library or application implemented in another language. An example is the Python bindings installed by [`libxml2`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/lib/libxml2.rb).

Homebrew is happy to accept applications that are built in Python, whether the apps are available from PyPI or not. Homebrew generally won't accept libraries that can be installed correctly with `pip install foo`. Bindings may be installed for packages that provide them, especially if equivalent functionality isn't available through pip. Similarly, libraries that have non-trivial amounts of native code and have a long compilation as a result can be good candidates. If in doubt, though: do not package libraries.

Applications should unconditionally bundle all their Python-language dependencies and libraries and should install any unsatisfied dependencies; these strategies are discussed in depth in the following sections.

## Applications

### Python declarations for applications

Formulae for apps that require Python 3 **must** declare an unconditional dependency on `"python@3.y"`. These apps **must** work with the current Homebrew Python 3.y formula.

### Installing applications

Starting with Python@3.12, Homebrew follows [PEP 668](https://peps.python.org/pep-0668/#marking-an-interpreter-as-using-an-external-package-manager). Applications must be installed into a Python [virtual environment](https://docs.python.org/3/library/venv.html) rooted in `libexec`. This prevents the app's Python modules from contaminating the system `site-packages` and vice versa.

All the Python module dependencies of the application (and their dependencies, recursively) should be [declared as `resource`s](Formula-Cookbook.md#python-dependencies) in the formula and installed into the virtual environment as well. Each dependency should be explicitly specified; please do not rely on `pip` to perform automatic dependency resolution, for the [reasons described here](Acceptable-Formulae.md#we-dont-like-install-scripts-that-download-unversioned-things).

You can use `brew update-python-resources` to help you write resource stanzas. To use it, simply run `brew update-python-resources <formula>`. Sometimes, `brew update-python-resources` won't be able to automatically update the resources. If this happens, try running `brew update-python-resources --print-only <formula>` to print the resource stanzas instead of applying the changes directly to the file. You can then copy and paste resources as needed.

If using `brew update-python-resources` doesn't work, you can use [homebrew-pypi-poet](https://github.com/tdsmith/homebrew-pypi-poet) to help you write resource stanzas. To use it, set up a virtual environment and install your package and all its dependencies. Then, `pip install homebrew-pypi-poet` into the same virtual environment. Running `poet some_package` will generate the necessary resource stanzas. You can do this like:

```sh
# Use a temporary directory for the virtual environment
cd "$(mktemp -d)"

# Create and source a new virtual environment in the venv/ directory
python3 -m venv venv
source venv/bin/activate

# Install the package of interest as well as homebrew-pypi-poet
pip install some_package homebrew-pypi-poet
poet some_package

# Destroy the virtual environment
deactivate
rm -rf venv
```

Homebrew provides helper methods for instantiating and populating virtual environments. You can use them by putting `include Language::Python::Virtualenv` at the top of the `Formula` class definition.

For most applications, all you will need to write is:

```ruby
class Foo < Formula
  include Language::Python::Virtualenv

  # ...
  url "https://example.com/foo-1.0.tar.gz"
  sha256 "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1"

  depends_on "python@3.y"

  def install
    virtualenv_install_with_resources
  end
end
```

This is exactly the same as writing:

```ruby
class Foo < Formula
  include Language::Python::Virtualenv

  # ...
  url "https://example.com/foo-1.0.tar.gz"
  sha256 "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abc1"

  depends_on "python@3.y"

  def install
    # Create a virtualenv in `libexec`.
    venv = virtualenv_create(libexec, "python3.y")
    # Install all of the resources declared on the formula into the virtualenv.
    venv.pip_install resources
    # `pip_install_and_link` takes a look at the virtualenv's bin directory
    # before and after installing its argument. New scripts will be symlinked
    # into `bin`. `pip_install_and_link buildpath` will install the package
    # that the formula points to, because buildpath is the location where the
    # formula's tarball was unpacked.
    venv.pip_install_and_link buildpath
  end
end
```

### Example formula

Installing a formula with dependencies will look like this:

```ruby
class Foo < Formula
  include Language::Python::Virtualenv

  desc "Description"
  homepage "https://example.com"
  url "..."

  resource "six" do
    url "https://files.pythonhosted.org/packages/71/39/171f1c67cd00715f190ba0b100d606d440a28c93c7714febeca8b79af85e/six-1.16.0.tar.gz"
    sha256 "1e61c37477a1626458e36f7b1d82aa5c9b094fa4802892072e49de9c60c4c926"
  end

  resource "parsedatetime" do
    url "https://files.pythonhosted.org/packages/a8/20/cb587f6672dbe585d101f590c3871d16e7aec5a576a1694997a3777312ac/parsedatetime-2.6.tar.gz"
    sha256 "4cb368fbb18a0b7231f4d76119165451c8d2e35951455dfee97c62a87b04d455"
  end

  def install
    virtualenv_install_with_resources
  end
end
```

In case you need to do different things for different resources, you can also use the more verbose form and request that specific resources be installed:

```ruby
class Foo < Formula
  include Language::Python::Virtualenv

  desc "Description"
  homepage "https://example.com"
  url "..."

  def install
    venv = virtualenv_create(libexec)
    %w[six parsedatetime].each do |r|
      venv.pip_install resource(r)
    end
    venv.pip_install_and_link buildpath
  end
end
```

## Bindings

To add bindings for Python 3, please add `depends_on "python@3.y"` to work with the current Homebrew Python 3.y formula.

### Dependencies for bindings

Bindings should follow the same advice for Python module dependencies as libraries; see below for more.

### Installing bindings

If the bindings are defined as a standard Python package (with either a `pyproject.toml` or a `setup.py`), do something like:

```ruby
system "python3.y", "-m", "pip", "install", *std_pip_args(build_isolation: true), "./source/python"
```

#### Autotools

If the configure script takes a `--with-python` flag, it usually will not need extra help finding Python. However, if there are multiple Python formulae in the dependency tree, it may need help finding the correct one.

If the `configure` and `make` scripts do not want to install into the Cellar, sometimes you can:

1. call `./configure --without-python` (or a similar named option)
1. call `pip` on the directory containing the Python bindings (as described above)

Sometimes we have to edit a `Makefile` on-the-fly to use our prefix for the Python bindings using Homebrew's [`inreplace`](Formula-Cookbook.md#inreplace) helper method.

#### CMake

If `cmake` finds a different Python than the direct dependency, sometimes you can help it find the correct Python by setting one of the following variables with the `-D` option:

* `Python3_EXECUTABLE` for the [`FindPython3`](https://cmake.org/cmake/help/latest/module/FindPython3.html) module
* `Python_EXECUTABLE` for the [`FindPython`](https://cmake.org/cmake/help/latest/module/FindPython.html) module
* `PYTHON_EXECUTABLE` for the [`FindPythonInterp`](https://cmake.org/cmake/help/latest/module/FindPythonInterp.html) module

#### Meson

As a side effect of Homebrew's symlink installation and the Python sysconfig patch, `meson` may be unable to automatically detect the Cellar directories to install Python bindings into. If the formula's `meson` build definition uses [`install_sources()`](https://mesonbuild.com/Python-module.html#install_sources) or similar methods, you can set `python.purelibdir` and/or `python.platlibdir` to override the default paths.

If `meson` finds a different Python than the direct dependency and the formula's `meson` option definition file does not provide a user-settable option, then you will need to check how the Python executable is being detected. A common approach is the [`find_installation()`](https://mesonbuild.com/Python-module.html#find_installation) method which will behave differently based on what the `name_or_path` argument is set to.

## Libraries

Remember: there are very limited cases for libraries (e.g. significant amounts of native code is compiled) so, if in doubt, do not package them.

**We do not use the `python-` prefix for these kinds of formulae!**

### Examples of allowed libraries in homebrew-core

* `numpy`, `scipy`: long build time, complex build process

* `cryptography`: builds with `rust`

* `certifi`: patched formula to allow any Python-based formulae to leverage the brewed CA certs (see <https://github.com/orgs/Homebrew/discussions/4691>).

### Python declarations for libraries

Libraries built for Python 3 must include `depends_on "python@3.y"`, which will bottle against Homebrew's Python 3.y.

### Installing libraries

Libraries may be installed to `libexec` and added to `sys.path` by writing a `.pth` file (named like "homebrew-foo.pth") to the `prefix` site-packages. This simplifies the ensuing drama if pip is accidentally used to upgrade a Homebrew-installed package and prevents the accumulation of stale `.pyc` files in Homebrew's site-packages.

Most formulae presently just install to `prefix`. Any stale `.pyc` files are handled by `brew cleanup`.

### Dependencies for libraries

Library dependencies must be installed so that they are importable. To minimise the potential for linking conflicts, dependencies should be installed to `libexec/<vendor>` and added to `sys.path` by writing a second `.pth` file (named like "homebrew-foo-dependencies.pth") to the `prefix` site-packages.

Formulae with general Python library dependencies (e.g. `setuptools`, `six`) should not use this approach as it will contaminate the system `site-packages` with all libraries installed inside `libexec/<vendor>`.

## Historical context

Over time, the Python packaging ecosystem has evolved from storing package metadata in a dynamic `setup.py` script to a static, declarative `pyproject.toml` file. At the same time, frontend installers (like `pip`) were decoupled from build backends (like `setuptools`), allowing the community to experiment and grow beyond a single tool.

1. **The `setup.py` era:** Historically, package installations relied on executing `python setup.py install`. This `setup.py` script imported either `distutils` (originally part of the standard library until its removal in Python 3.12) or its extended replacement `setuptools`. Package installers like `easy_install` and later `pip` were then [developed](https://packaging.python.org/en/latest/discussions/pip-vs-easy-install/) on top of this execution model.
2. **Python adopts `pip`:** In 2013, [PEP 453](https://peps.python.org/pep-0453/) officially adopted `pip` as Python's default installer and bundled it with Python 3.4. It also explicitly [recommended](https://peps.python.org/pep-0453/#recommendations-for-downstream-distributors) downstream distributors (such as Homebrew) to install packages using `pip` rather than invoking `setup.py` directly. For historical reasons, Homebrew did not originally follow this advice.
3. **The `pyproject.toml` standard:** In 2016, to decouple from specific tools, [PEP 518](https://peps.python.org/pep-0518/) introduced `pyproject.toml` for declaring explicit build-time dependencies while [PEP 517](https://peps.python.org/pep-0517/) standardized an API allowing frontend installers to interact with *any* compliant build backend. This allowed the development of new tools such as `poetry`, `pdm`, and `hatch`.
4. **Homebrew transition:** In 2021, `setuptools` officially [deprecated](https://packaging.python.org/en/latest/discussions/setup-py-deprecated/) executing `setup.py` directly in favor of the new standard. Homebrew then migrated all core formulae to use a standard `pip` installation method.
