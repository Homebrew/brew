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

All the Python module dependencies of the application (and their dependencies, recursively) should be declared as [`resource`](https://rubydoc.brew.sh/Formula#resource-class_method)s in the formula and installed into the virtual environment as well. Each dependency should be explicitly specified; please do not rely on `setup.py` or `pip` to perform automatic dependency resolution, for the [reasons described here](Acceptable-Formulae.md#we-dont-like-install-scripts-that-download-unversioned-things).

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

You can also use the more verbose form and request that specific resources be installed:

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

in case you need to do different things for different resources.

## Bindings

To add bindings for Python 3, please add `depends_on "python@3.y"` to work with the current Homebrew Python 3.y formula.

### Dependencies for bindings

Bindings should follow the same advice for Python module dependencies as libraries; see below for more.

### Installing bindings

If the bindings are installed by invoking a `setup.py`, do something like:

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

## Further down the rabbit hole

Additional commentary that explains why Homebrew does some of the things it does.

### Setuptools vs. Distutils vs. pip

Distutils was a module in the Python standard library that provided developers a basic package management API until its removal in Python 3.12. Setuptools is a module distributed outside the standard library that extends and replaces Distutils. It is a convention that Python packages provide a `setup.py` that calls the `setup()` function from either Distutils or Setuptools.

Setuptools used to provide the `easy_install` command, which was an end-user package management tool that fetched and installed packages from PyPI, the Python Package Index. The `easy_install` console script was removed in Setuptools v52.0.0 and direct usage has been deprecated since v58.3.0. `pip` is another, newer end-user package management tool, which is also provided outside the standard library. While `pip` supplants `easy_install`, it does not replace the other functionality of the Setuptools module.

Distutils and pip use a "flat" installation hierarchy that installs modules as individual files under `site-packages` while `easy_install` installs zipped eggs to `site-packages` instead.

Distribute (not to be confused with Distutils) is an obsolete fork of Setuptools. Distlib is a package maintained outside the standard library which is used by pip for some low-level packaging operations and is not relevant to most `setup.py` users.

### Running `setup.py`

For when a formula needs to interact with `setup.py` instead of calling `pip`, Homebrew provides the helper method `Language::Python.setup_install_args` which returns useful arguments for invoking `setup.py`. Your formula should use this instead of invoking `setup.py` explicitly. The syntax is:

```ruby
system Formula["python@3.y"].opt_bin/"python3.y", *Language::Python.setup_install_args(prefix)
```

where `prefix` is the destination prefix (usually `libexec` or `prefix`).

### What is `--single-version-externally-managed`?

`--single-version-externally-managed` ("SVEM") is a [Setuptools](https://setuptools.readthedocs.io/en/latest/setuptools.html)-only argument to `setup.py install`. The primary effect of SVEM is using Distutils to perform the install instead of Setuptools' `easy_install`.

`easy_install` does a few things that we need to avoid:

* fetches and installs dependencies
* upgrades dependencies in `sys.path` in-place
* writes `.pth` and `site.py` files which aren't useful for us and cause link conflicts

Setuptools requires that SVEM be used in conjunction with `--record`, which provides a list of files that can later be used to uninstall the package. We don't need or want this because Homebrew can manage uninstallation, but since Setuptools demands it we comply. The Homebrew convention is to name the record file "installed.txt".

Detecting whether a `setup.py` uses `setup()` from Setuptools or Distutils is difficult, but we always need to pass this flag to Setuptools-based scripts. `pip` faces the same problem that we do and forces `setup()` to use the Setuptools version by loading a shim around `setup.py` that imports Setuptools before doing anything else. Since Setuptools monkey-patches Distutils and replaces its `setup` function, this provides a single, consistent interface. We have borrowed this code and use it in `Language::Python.setup_install_args`.

### `--prefix` vs `--root`

`setup.py` accepts a slightly bewildering array of installation options. The correct switch for Homebrew is `--prefix`, which automatically sets the `--install-foo` family of options with sane POSIX-y values.

`--root` [is used](https://mail.python.org/pipermail/distutils-sig/2010-November/017099.html) when installing into a prefix that will not become part of the final installation location of the files, like when building a RPM or binary distribution. When using a `setup.py`-based Setuptools, `--root` has the side effect of activating `--single-version-externally-managed`. It is not safe to use `--root` with an empty `--prefix` because the `root` is removed from paths when byte-compiling modules.

It is probably safe to use `--prefix` with `--root=/`, which should work with either Setuptools- or Distutils-based `setup.py`'s, but it's kinda ugly.

### `pip` vs. `setup.py`

[PEP 453](https://legacy.python.org/dev/peps/pep-0453/#recommendations-for-downstream-distributors) makes a recommendation to downstream distributors (us) that sdist tarballs should be installed with `pip` instead of by invoking `setup.py` directly. For historical reasons we did not follow PEP 453, so some formulae still use `setup.py` installs. Nowadays, most core formulae use `pip` as we have migrated them to this preferred method of installation.
