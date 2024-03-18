# Python

This page describes how Python is handled in Homebrew for users. See [Python for Formula Authors](Python-for-Formula-Authors.md) for advice on writing formulae to install packages written in Python.

Homebrew will install the necessary Python 3 version that is needed to make your packages work. Python 2 (or 1) is not supported.

## Python 3

Homebrew provides formulae for the newest and maintained releases of Python 3 (`python@3.y`) (<https://devguide.python.org/versions/>).
We keep older `python@3.y` versions according to our [versioned formulae guidelines](https://docs.brew.sh/Versions).

**Important:** Python may be upgraded to a newer version at any time. Consider using a version
manager such as `pyenv` if you require stability of minor or patch versions for virtual environments.

The executables are organised as follows:

* `python3` points to Homebrew's Python 3.y (if installed)
* `pip3` points to Homebrew's Python 3.y's pip (if installed)

Unversioned symlinks for `python`, `python-config`, `pip` etc. are installed here:

```sh
$(brew --prefix python)/libexec/bin
```

**Warning!** The executables do not always point to the latest Python 3 version, as there is always a delay between the newest Python 3 release and the homebrew-core repository switching to the newest version.

## Setuptools, pip, etc.

The Python formulae install [pip](https://pip.pypa.io/) (as `pip3`). Python@3.11 and older Python formulae also install [Setuptools](https://pypi.org/project/setuptools/).

Starting with Python@3.12, the bundled Python packages should be updated by reinstalling brewed Python. For older Python formulae, they can be updated as described below.

Setuptools can be updated via `pip`, without having to reinstall brewed Python:

```sh
python3 -m pip install --upgrade setuptools
```

Similarly, `pip` can be used to upgrade itself via:

```sh
python3 -m pip install --upgrade pip
```

## `site-packages` and the `PYTHONPATH`

The `site-packages` is a directory that contains Python modules, including bindings installed by other formulae. Homebrew creates it here:

```sh
$(brew --prefix)/lib/pythonX.Y/site-packages
```

So, for Python 3.y.z, you'll find it at `/usr/local/lib/python3.y/site-packages` on macOS Intel.

Python 3.y also searches for modules in:

* `/Library/Python/3.y/site-packages`
* `~/Library/Python/3.y/lib/python/site-packages`

Homebrew's `site-packages` directory is first created (1) once any Homebrew formulae with Python bindings are installed, or (2) upon `brew install python`.

### Why here?

The reasoning for this location is to preserve your modules between (minor) upgrades or re-installations of Python. Additionally, Homebrew has a strict policy never to write stuff outside of the `brew --prefix`, so we don't spam your system.

## Homebrew-provided Python bindings

Some formulae provide Python bindings.

## Policy for non-brewed Python bindings

These should be installed via `pip install <package>`. To discover, you can use <https://pypi.org/search>.

Starting with Python 3.12, we highly recommend you to use a separate virtualenv for this (see the section about [PEP 668](https://peps.python.org/pep-0668/#marking-an-interpreter-as-using-an-external-package-manager) below).

## Brewed Python modules

For brewed Python, modules installed with `pip` or `python3 setup.py install` will be installed to the `$(brew --prefix)/lib/pythonX.Y/site-packages` directory (explained above). Executable Python scripts will be in `$(brew --prefix)/bin`.

Since the system Python may not know which compiler flags to set when building bindings for software installed by Homebrew, you may need to run:

```sh
CFLAGS="-I$(brew --prefix)/include" LDFLAGS="-L$(brew --prefix)/lib" pip install <package>
```

## PEP 668 (Python@3.12) and virtual environments

Starting with Python@3.12, Homebrew follows [PEP 668](https://peps.python.org/pep-0668/#marking-an-interpreter-as-using-an-external-package-manager).

If you wish to install a non-brew-packaged Python package (from PyPI for example):

* create a virtual environment using `python3 -m venv path/to/venv`. Then use `path/to/venv/bin/python` and `path/to/venv/bin/pip`.
* or use `pipx install xyz`, which will manage a virtual environment for you.
  You can install `pipx` by running `brew install pipx`.
  When you use `pipx` to install a Python application, it will always use a virtual environment for you.

It is possible to install some Python packages as formulae by using `brew install xyz`. We do not recommend using these formulae and instead recommend you install them with pip inside a virtualenv. These system-wide Homebrew Python formulae are often Homebrew-specific formulae that are useful as dependencies for other Homebrew formulae. It is not recommended to rely on them.

## Why is Homebrew's Python being installed as a dependency?

Formulae that declare an unconditional dependency on the `python` formula are bottled against Homebrew's Python 3.y and require it to be installed.
