[![Actions Status: MinGW](https://github.com/ruby/ruby/workflows/MinGW/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"MinGW")
[![Actions Status: MJIT](https://github.com/ruby/ruby/workflows/MJIT/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"MJIT")
[![Actions Status: Ubuntu](https://github.com/ruby/ruby/workflows/Ubuntu/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"Ubuntu")
[![Actions Status: Windows](https://github.com/ruby/ruby/workflows/Windows/badge.svg)](https://github.com/ruby/ruby/actions?query=workflow%3A"Windows")
[![AppVeyor status](https://ci.appveyor.com/api/projects/status/0sy8rrxut4o0k960/branch/master?svg=true)](https://ci.appveyor.com/project/ruby/ruby/branch/master)
[![Travis Status](https://app.travis-ci.com/ruby/ruby.svg?branch=master)](https://app.travis-ci.com/ruby/ruby)
[![Cirrus Status](https://api.cirrus-ci.com/github/ruby/ruby.svg)](https://cirrus-ci.com/github/ruby/ruby/master)

# What's Ruby

Ruby is an interpreted object-oriented programming language often
used for web development. It also offers many scripting features
to process plain text and serialized files, or manage system tasks.
It is simple, straightforward, and extensible.

## Features of Ruby

*   Simple Syntax
*   **Normal** Object-oriented Features (e.g. class, method calls)
*   **Advanced** Object-oriented Features (e.g. mix-in, singleton-method)
*   Operator Overloading
*   Exception Handling
*   Iterators and Closures
*   Garbage Collection
*   Dynamic Loading of Object Files (on some architectures)
*   Highly Portable (works on many Unix-like/POSIX compatible platforms as
    well as Windows, macOS, etc.) cf.
    https://github.com/ruby/ruby/blob/master/doc/maintainers.rdoc#label-Platform+Maintainers


## How to get Ruby

For a complete list of ways to install Ruby, including using third-party tools
like rvm, see:

https://www.ruby-lang.org/en/downloads/

### Git

The mirror of the Ruby source tree can be checked out with the following command:

    $ git clone https://github.com/ruby/ruby.git

There are some other branches under development. Try the following command
to see the list of branches:

    $ git ls-remote https://github.com/ruby/ruby.git

You may also want to use https://git.ruby-lang.org/ruby.git (actual master of Ruby source)
if you are a committer.

### Subversion

Stable branches for older Ruby versions can be checked out with also the
following command:

    $ svn co https://svn.ruby-lang.org/repos/ruby/branches/ruby_2_6/ ruby

Try the following command to see the list of branches:

    $ svn ls https://svn.ruby-lang.org/repos/ruby/branches/


## Ruby home page

https://www.ruby-lang.org/

## Mailing list

There is a mailing list to discuss Ruby. To subscribe to this list, please
send the following phrase:

    subscribe

in the mail body (not subject) to the address [ruby-talk-request@ruby-lang.org].

[ruby-talk-request@ruby-lang.org]: mailto:ruby-talk-request@ruby-lang.org?subject=Join%20Ruby%20Mailing%20List&body=subscribe

## Requirements to build from repository

1. GNU or BSD make
2. C99 compiler
3. autoconf 2.67 or higher
4. automake 1.15 or higher
5. bison 2.3 or higher
6. Ruby 2.2 or higher

When building from a released version, only a C99 compiler and GNU or BSD make
is required.

## How to compile and install

1.  If you want to use Microsoft Visual C++ to compile Ruby, read
    [win32/README.win32](rdoc-ref:win32/README.win32) instead of this document.

2.  Run `./autogen.sh` to generate configure, when you build the source checked
    out from the Git repository.

3.  Run `./configure`, which will generate `config.h` and `Makefile`.

    Some C compiler flags may be added by default depending on your
    environment. Specify `optflags=..` and `warnflags=..` as necessary to
    override them.

4.  Edit `include/ruby/defines.h` if you need. Usually this step will not be needed.

5.  Optional: Remove comment mark(`#`) before the module names from `ext/Setup`.

    This step is only necessary if you want to link modules statically.

    If you don't want to compile dynamic extensions (probably on architectures
    which do not allow dynamic loading), remove comment mark from the line
    "`#option nodynamic`" in `ext/Setup`.

    Usually this step will not be needed.

6.  Run `make`.

    * On Mac, set RUBY\_CODESIGN environment variable with a signing identity.
      It uses the identity to sign `ruby` binary. See also codesign(1).

7.  Optionally, run '`make check`' to check whether the compiled Ruby
    interpreter works well. If you see the message "`check succeeded`", your
    Ruby works as it should (hopefully).

8.  Run '`make install`'.

    This command will create the following directories and install files into
    them.

    *   `${DESTDIR}${prefix}/bin`
    *   `${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib`
    *   `${DESTDIR}${prefix}/lib/ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/gems/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/share/man/man1`
    *   `${DESTDIR}${prefix}/share/ri/${MAJOR}.${MINOR}.${TEENY}/system`


    If Ruby's API version is '*x.y.z*', the `${MAJOR}` is '*x*', the
    `${MINOR}` is '*y*', and the `${TEENY}` is '*z*'.

    **NOTE**: teeny of the API version may be different from one of Ruby's
    program version

    You may have to be a super user to install Ruby.

If you fail to compile Ruby, please send the detailed error report with the
error log and machine/OS type, to help others.

Some extension libraries may not get compiled because of lack of necessary
external libraries and/or headers, then you will need to run '`make distclean-ext`'
to remove old configuration after installing them in such case.

## Copying

See the file [COPYING](rdoc-ref:COPYING).

## Feedback

Questions about the Ruby language can be asked on the [Ruby-Talk] mailing list
or on websites like https://stackoverflow.com.

Bugs should be reported at https://bugs.ruby-lang.org. Read [HowToReport] for more information.

[Ruby-Talk]: https://www.ruby-lang.org/en/community/mailing-lists
[HowToReport]: https://bugs.ruby-lang.org/projects/ruby/wiki/HowToReport

## Contributing

See the file [CONTRIBUTING.md](rdoc-ref:CONTRIBUTING)

## The Author

Ruby was originally designed and developed by Yukihiro Matsumoto (Matz) in 1995.

<matz@ruby-lang.org>
