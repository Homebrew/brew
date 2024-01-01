# Python

This page describes how Python is handled in Homebrew for users. See [Python for Formula Authors](Python-for-Formula-Authors.md) for advice on writing formulae to install packages written in Python.

Homebrew should work with any [CPython](https://stackoverflow.com/questions/2324208/is-there-any-difference-between-cpython-and-python) and defaults to the macOS system Python.

Homebrew provides formulae to brew Python 3.y. A `python@2` formula was provided until the end of 2019, at which point it was removed due to the Python 2 deprecation.

**Important:** If you choose to use a Python which isn't either of these two (system Python or brewed Python), the Homebrew team cannot support any breakage that may occur.

## Python 3.y

Homebrew provides formulae for maintained releases of Python 3.y (`python@3.y`).

**Important:** Python may be upgraded to a newer version at any time. Consider using a version
manager such as `pyenv` if you require stability of minor or patch versions for virtual environments.

The executables are organised as follows:

* `python3` points to Homebrew's Python 3.y (if installed)
* `pip3` points to Homebrew's Python 3.y's pip (if installed)

Unversioned symlinks for `python`, `python-config`, `pip` etc. are installed here:

```sh
$(brew --prefix python)/libexec/bin
```

## Setuptools, pip, etc.

The Python formulae install [pip](https://pip.pypa.io/) (as `pip3`) and [Setuptools](https://pypi.org/project/setuptools/).

Setuptools can be updated via `pip`, without having to re-brew Python:

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

So, for Python 3.y.z, you'll find it at `/usr/local/lib/python3.y/site-packages`.

Python 3.y also searches for modules in:

* `/Library/Python/3.y/site-packages`
* `~/Library/Python/3.y/lib/python/site-packages`

Homebrew's `site-packages` directory is first created (1) once any Homebrew formulae with Python bindings are installed, or (2) upon `brew install python`.

### Why here?

The reasoning for this location is to preserve your modules between (minor) upgrades or re-installations of Python. Additionally, Homebrew has a strict policy never to write stuff outside of the `brew --prefix`, so we don't spam your system.

## Homebrew-provided Python bindings

Some formulae provide Python bindings.

**Warning!** Python may crash (see [Common Issues](Common-Issues.md)) when you `import <module>` from a brewed Python if you ran `brew install <formula_with_python_bindings>` against the system Python. If you decide to switch to the brewed Python, then reinstall all formulae with Python bindings (e.g. `pyside`, `wxwidgets`, `pyqt`, `pygobject3`, `opencv`, `vtk` and `boost-python`).

## Policy for non-brewed Python bindings

These should be installed via `pip install <package>`. To discover, you can use <https://pypi.org/search>.

**Note:** macOS's system Python does not provide `pip`. Follow the [pip documentation](https://pip.pypa.io/en/stable/installation/) to install it for your system Python if you would like it.

## Brewed Python modules

For brewed Python, modules installed with `pip` or `python3 setup.py install` will be installed to the `$(brew --prefix)/lib/pythonX.Y/site-packages` directory (explained above). Executable Python scripts will be in `$(brew --prefix)/bin`.

Since the system Python may not know which compiler flags to set when building bindings for software installed by Homebrew, you may need to run:

```sh
CFLAGS="-I$(brew --prefix)/include" LDFLAGS="-L$(brew --prefix)/lib" pip install <package>
```

## Virtualenv

**Warning!** When you `brew install` formulae that provide Python bindings, you should **not be in an active virtual environment.**

Activate the virtualenv *after* you've brewed, or brew in a fresh terminal window. This will ensure Python modules are installed into Homebrew's `site-packages` and *not* into that of the virtual environment.

Virtualenv has a `--system-site-packages` switch to allow "global" (i.e. Homebrew's) `site-packages` to be accessible from within the virtualenv.

## Why is Homebrew's Python being installed as a dependency?

Formulae that declare an unconditional dependency on the `python` formula are bottled against Homebrew's Python 3.y and require it to be installed.
