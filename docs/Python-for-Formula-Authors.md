# Python for Formula Authors

This document explains how to successfully use Python in a Homebrew formula.

Homebrew draws a distinction between Python **applications** and Python **libraries**. The difference is that users generally do not care that applications are written in Python; it is unusual that a user would expect to be able to `import foo` after installing an application. Examples of applications are [`ansible`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/a/ansible.rb) and [`jrnl`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/j/jrnl.rb).

Python libraries exist to be imported by other Python modules; they are often dependencies of Python applications. They are usually no more than incidentally useful in a terminal. An example of a library is the bindings that are installed by [`protobuf`](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/p/protobuf.rb).

Bindings are a special case of libraries that allow Python code to interact with a library or application implemented in another language.

Homebrew is happy to accept applications that are built in Python, whether the apps are available from PyPI or not. Homebrew generally won't accept libraries that can be installed correctly with `pip install foo`. Bindings may be installed for packages that provide them, especially if equivalent functionality isn't available through pip. Similarly, libraries that have non-trivial amounts of native code and have a long compilation as a result can be good candidates. If in doubt, though: do not package libraries.

Applications should unconditionally bundle all their Python-language dependencies and libraries and should install any unsatisfied dependencies; these strategies are discussed in depth in the following sections.

## Applications

### Python declarations for applications

Formulae for apps that require Python 3 **should** declare an unconditional dependency on `"python@3.x"`. These apps **must** work with the current Homebrew Python 3.x formula.

### Installing applications

Applications should be installed into a Python [virtualenv](https://virtualenv.pypa.io/en/stable/) environment rooted in `libexec`. This prevents the app's Python modules from contaminating the system `site-packages` and vice versa.

All the Python module dependencies of the application (and their dependencies, recursively) should be declared as [`resource`](https://rubydoc.brew.sh/Formula#resource-class_method)s in the formula and installed into the virtualenv as well. Each dependency should be explicitly specified; please do not rely on `setup.py` or `pip` to perform automatic dependency resolution, for the [reasons described here](Acceptable-Formulae.md#we-dont-like-install-scripts-that-download-unversioned-things).

You can use `brew update-python-resources` to help you write resource stanzas. To use it, simply run `brew update-python-resources <formula>`. Sometimes, `brew update-python-resources` won't be able to automatically update the resources. If this happens, try running `brew update-python-resources --print-only <formula>` to print the resource stanzas instead of applying the changes directly to the file. You can then copy and paste resources as needed.

If using `brew update-python-resources` doesn't work, you can use [homebrew-pypi-poet](https://github.com/tdsmith/homebrew-pypi-poet) to help you write resource stanzas. To use it, set up a virtualenv and install your package and all its dependencies. Then, `pip install homebrew-pypi-poet` into the same virtualenv. Running `poet some_package` will generate the necessary resource stanzas. You can do this like:

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

Homebrew provides helper methods for instantiating and populating virtualenvs. You can use them by putting `include Language::Python::Virtualenv` at the top of the `Formula` class definition.

For most applications, all you will need to write is:

```ruby
def install
  virtualenv_install_with_resources
end
```

This is exactly the same as writing:

```ruby
def install
  # Create a virtualenv in `libexec`. If your app needs Python 3, make sure that
  # `depends_on "python"` is declared, and use `virtualenv_create(libexec, "python3")`.
  venv = virtualenv_create(libexec)
  # Install all of the resources declared on the formula into the virtualenv.
  venv.pip_install resources
  # `pip_install_and_link` takes a look at the virtualenv's bin directory
  # before and after installing its argument. New scripts will be symlinked
  # into `bin`. `pip_install_and_link buildpath` will install the package
  # that the formula points to, because buildpath is the location where the
  # formula's tarball was unpacked.
  venv.pip_install_and_link buildpath
end
```

### Example formula

Installing a formula with dependencies will look like this:

```ruby
class Foo < Formula
  include Language::Python::Virtualenv

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
def install
  venv = virtualenv_create(libexec)
  %w[six parsedatetime].each do |r|
    venv.pip_install resource(r)
  end
  venv.pip_install_and_link buildpath
end
```

in case you need to do different things for different resources.

## Bindings

To add bindings for Python 3, please add `depends_on "python@3.x"` to work with the current Homebrew Python 3.x formula.

### Dependencies for bindings

Bindings should follow the same advice for Python module dependencies as libraries; see below for more.

### Installing bindings

If the bindings are installed by invoking a `setup.py`, do something like:

```ruby
cd "source/python" do
  system Formula["python@3.x"].opt_bin/"python3", *Language::Python.setup_install_args(prefix)
end
```

If the configure script takes a `--with-python` flag, it usually will not need extra help finding Python.

If the `configure` and `make` scripts do not want to install into the Cellar, sometimes you can:

1. call `./configure --without-python` (or a similar named option)
2. `cd` into the directory containing the Python bindings
3. call `setup.py` with `system` and `Language::Python.setup_install_args` (as described above)

Sometimes we have to edit a `Makefile` on-the-fly to use our prefix for the Python bindings using Homebrew's [`inreplace`](Formula-Cookbook.md#inreplace) helper method.

## Libraries

Remember: there are very limited cases for libraries (e.g. significant amounts of native code is compiled) so, if in doubt, do not package them.

### Python declarations for libraries

Libraries built for Python 3 should include `depends_on "python@3.x"`, which will bottle against Homebrew's Python 3.x.

### Installing libraries

Libraries may be installed to `libexec` and added to `sys.path` by writing a `.pth` file (named like "homebrew-foo.pth") to the `prefix` site-packages. This simplifies the ensuing drama if pip is accidentally used to upgrade a Homebrew-installed package and prevents the accumulation of stale `.pyc` files in Homebrew's site-packages.

Most formulae presently just install to `prefix`.

### Dependencies for libraries

Library dependencies must be installed so that they are importable. To minimise the potential for linking conflicts, dependencies should be installed to `libexec/<vendor>` and added to `sys.path` by writing a second `.pth` file (named like "homebrew-foo-dependencies.pth") to the `prefix` site-packages.

## Further down the rabbit hole

Additional commentary that explains why Homebrew does some of the things it does.

### Setuptools vs. Distutils vs. pip

Distutils is a module in the Python standard library that provides developers a basic package management API. Setuptools is a module distributed outside the standard library that extends Distutils. It is a convention that Python packages provide a `setup.py` that calls the `setup()` function from either Distutils or Setuptools.

Setuptools provides the `easy_install` command, which is an end-user package management tool that fetches and installs packages from PyPI, the Python Package Index. `pip` is another, newer end-user package management tool, which is also provided outside the standard library. While pip supplants `easy_install`, it does not replace the other functionality of the Setuptools module.

Distutils and pip use a "flat" installation hierarchy that installs modules as individual files under `site-packages` while `easy_install` installs zipped eggs to `site-packages` instead.

Distribute (not to be confused with Distutils) is an obsolete fork of Setuptools. Distlib is a package maintained outside the standard library which is used by pip for some low-level packaging operations and is not relevant to most `setup.py` users.

### Running `setup.py`

For when a formula needs to interact with `setup.py` instead of calling `pip`, Homebrew provides the helper method `Language::Python.setup_install_args` which returns useful arguments for invoking `setup.py`. Your formula should use this instead of invoking `setup.py` explicitly. The syntax is:

```ruby
system Formula["python@3.x"].opt_bin/"python3", *Language::Python.setup_install_args(prefix)
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

[PEP 453](https://legacy.python.org/dev/peps/pep-0453/#recommendations-for-downstream-distributors) makes a recommendation to downstream distributors (us) that sdist tarballs should be installed with `pip` instead of by invoking `setup.py` directly. We do not do this because Apple's Python distribution does not include pip, so we can't assume that pip is available. We could do something clever to work around Apple's piplessness but the value proposition is not yet clear.
