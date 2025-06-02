---
last_review_date: "1970-01-01"
---

# Gems, Eggs and Perl Modules

On a fresh macOS installation there are two empty directories for
add-ons available to all users:

* `/Library/Ruby`
* `/Library/Perl`

You need sudo to install to these like so: `sudo gem install`
or `sudo cpan -i`.

## Python packages (eggs) without sudo using system Python

An option to avoid sudo is to use an access control list. For example:

```sh
chmod +a 'user:<YOUR_NAME_HERE> allow add_subdirectory,add_file,delete_child,directory_inherit' /Library/Python/3.y/site-packages
```

will let you add packages to Python 3.y as yourself, which
is probably safer than changing the group ownership of the directory.

### So why was I using sudo?

Habit maybe?

One reason is executables go in `/usr/local/bin`. Usually this isn’t a
writable location. But if you installed Homebrew as we recommend on macOS Intel,
`/usr/local` will be writable without sudo. So now you are good to
install the development tools you need without risking the use of sudo.

### An alternative package path

_This is only recommended if you **don't** use a brewed Python._

On macOS, any Python version X.Y [also searches in
`~/Library/Python/X.Y/lib/python/site-packages` for
modules](https://docs.python.org/2/install/index.html#alternate-installation-the-user-scheme).
That path might not yet exist, but you can create it:

```sh
mkdir -p ~/Library/Python/2.7/lib/python/site-packages
```

To teach `easy_install` and `pip` to install there, either use the
`--user` switch or create a `~/.pydistutils.cfg` file with the
following content:

    [install]
    install_lib = ~/Library/Python/$py_version_short/lib/python/site-packages

### Using virtualenv (with system Python)

[Virtualenv](https://virtualenv.pypa.io/) ships `pip` and
creates isolated Python environments with separate `site-packages`,
which therefore don’t need sudo.

## Rubygems without sudo

_This is only recommended if you **don't** use rbenv or RVM._

Brewed Ruby installs executables to `$(brew --prefix ruby)/bin`
without sudo. You should add this to your path. See the caveats in the
`ruby` formula for up-to-date information.

### With system Ruby

To make Ruby install to `/usr/local`, we need to add
`gem: -n/usr/local/bin` to your `~/.gemrc`. It’s YAML, so do it manually
or use this:

```sh
echo "gem: -n/usr/local/bin" >> ~/.gemrc
```

**However, all versions of RubyGems before 1.3.6 are buggy** and ignore
the above setting. Sadly a fresh install of Snow Leopard comes with
1.3.5. Currently the only known way to get around this is to upgrade
rubygems as root:

```sh
sudo gem update --system
```

### An alternative gem path

Just install everything into the Homebrew prefix like this:

```sh
echo "export GEM_HOME=\"$(brew --prefix)\"" >> ~/.bashrc
```

### It doesn’t work! I get some “permissions” error when I try to install stuff

_Note that you may not want to do this, since Apple has decided it
is not a good default._

If you ever did a `sudo gem`, etc. before then a lot of files will have
been created owned by root. Fix with:

```sh
sudo chown -R $(whoami) /Library/Ruby/* /Library/Perl/* /Library/Python/*
```

## Perl CPAN modules without sudo

The Perl module `local::lib` works similarly to rbenv/RVM (although for
modules only, not Perl installations). A simple solution that only
pollutes your `/Library/Perl` a little is to install
[`local::lib`](https://metacpan.org/pod/local::lib) with sudo:

```sh
sudo cpan local::lib
```

Note that this will install some other dependencies like `Module::Install`.
Then put the appropriate incantation in your shell’s startup, e.g. for
`.profile` you'd insert the below; for others see the
[`local::lib`](https://metacpan.org/pod/local::lib) docs.

```sh
eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib)"
```

Now (after you restart your shell) `cpan` or `perl -MCPAN -eshell` etc.
will install modules and binaries in `~/perl5` and the relevant
subdirectories will be in your `PATH` and `PERL5LIB`.

### Avoiding sudo altogether for Perl

If you don’t even want to (or can’t) use sudo for bootstrapping
`local::lib`, just manually install `local::lib` in
`~/perl5` and add the relevant path to `PERL5LIB` before the `.bashrc` eval incantation.

Another alternative is to use `perlbrew` to install a separate copy of Perl in your home directory, or wherever you like:

```sh
curl -L https://install.perlbrew.pl | bash
perlbrew install perl-5.16.2
echo ".~/perl5/perlbrew/etc/bashrc" >> ~/.bashrc
```
