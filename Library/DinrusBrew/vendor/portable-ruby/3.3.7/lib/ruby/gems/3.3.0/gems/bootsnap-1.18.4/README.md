# Bootsnap [![Actions Status](https://github.com/Shopify/bootsnap/workflows/ci/badge.svg)](https://github.com/Shopify/bootsnap/actions)

Bootsnap is a library that plugs into Ruby, with optional support for `YAML` and `JSON`,
to optimize and cache expensive computations. See [How Does This Work](#how-does-this-work).

#### Performance

- [Discourse](https://github.com/discourse/discourse) reports a boot time reduction of approximately
  50%, from roughly 6 to 3 seconds on one machine;
- One of our smaller internal apps also sees a reduction of 50%, from 3.6 to 1.8 seconds;
- The core Shopify platform -- a rather large monolithic application -- boots about 75% faster,
  dropping from around 25s to 6.5s.
* In Shopify core (a large app), about 25% of this gain can be attributed to `compile_cache_*`
  features; 75% to path caching. This is fairly representative.

## Usage

This gem works on macOS and Linux.

Add `bootsnap` to your `Gemfile`:

```ruby
gem 'bootsnap', require: false
```

If you are using Rails, add this to `config/boot.rb` immediately after `require 'bundler/setup'`:

```ruby
require 'bootsnap/setup'
```

Note that bootsnap writes to `tmp/cache` (or the path specified by `ENV['BOOTSNAP_CACHE_DIR']`),
and that directory *must* be writable. Rails will fail to
boot if it is not. If this is unacceptable (e.g. you are running in a read-only container and
unwilling to mount in a writable tmpdir), you should remove this line or wrap it in a conditional.

**Note also that bootsnap will never clean up its own cache: this is left up to you. Depending on your
deployment strategy, you may need to periodically purge `tmp/cache/bootsnap*`. If you notice deploys
getting progressively slower, this is almost certainly the cause.**

It's technically possible to simply specify `gem 'bootsnap', require: 'bootsnap/setup'`, but it's
important to load Bootsnap as early as possible to get maximum performance improvement.

You can see how this require works [here](https://github.com/Shopify/bootsnap/blob/main/lib/bootsnap/setup.rb).

If you are not using Rails, or if you are but want more control over things, add this to your
application setup immediately after `require 'bundler/setup'` (i.e. as early as possible: the sooner
this is loaded, the sooner it can start optimizing things)

```ruby
require 'bootsnap'
env = ENV['RAILS_ENV'] || "development"
Bootsnap.setup(
  cache_dir:            'tmp/cache',          # Path to your cache
  ignore_directories:   ['node_modules'],     # Directory names to skip.
  development_mode:     env == 'development', # Current working environment, e.g. RACK_ENV, RAILS_ENV, etc
  load_path_cache:      true,                 # Optimize the LOAD_PATH with a cache
  compile_cache_iseq:   true,                 # Compile Ruby code into ISeq cache, breaks coverage reporting.
  compile_cache_yaml:   true,                 # Compile YAML into a cache
  compile_cache_json:   true,                 # Compile JSON into a cache
  readonly:             true,                 # Use the caches but don't update them on miss or stale entries.
)
```

**Protip:** You can replace `require 'bootsnap'` with `BootLib::Require.from_gem('bootsnap',
'bootsnap')` using [this trick](https://github.com/Shopify/bootsnap/wiki/Bootlib::Require). This
will help optimize boot time further if you have an extremely large `$LOAD_PATH`.

Note: Bootsnap and [Spring](https://github.com/rails/spring) are orthogonal tools. While Bootsnap
speeds up the loading of individual source files, Spring keeps a copy of a pre-booted Rails process
on hand to completely skip parts of the boot process the next time it's needed. The two tools work
well together.

### Environment variables

`require 'bootsnap/setup'` behavior can be changed using environment variables:

- `BOOTSNAP_CACHE_DIR` allows to define the cache location.
- `DISABLE_BOOTSNAP` allows to entirely disable bootsnap.
- `DISABLE_BOOTSNAP_LOAD_PATH_CACHE` allows to disable load path caching.
- `DISABLE_BOOTSNAP_COMPILE_CACHE` allows to disable ISeq and YAML caches.
- `BOOTSNAP_READONLY` configure bootsnap to not update the cache on miss or stale entries.
- `BOOTSNAP_LOG` configure bootsnap to log all caches misses to STDERR.
- `BOOTSNAP_STATS` log hit rate statistics on exit. Can't be used if `BOOTSNAP_LOG` is enabled.
- `BOOTSNAP_IGNORE_DIRECTORIES` a comma separated list of directories that shouldn't be scanned.
  Useful when you have large directories of non-ruby files inside `$LOAD_PATH`.
  It defaults to ignore any directory named `node_modules`.

### Environments

All Bootsnap features are enabled in development, test, production, and all other environments according to the configuration in the setup. At Shopify, we use this gem safely in all environments without issue.

If you would like to disable any feature for a certain environment, we suggest changing the configuration to take into account the appropriate ENV var or configuration according to your needs.

### Instrumentation

Bootsnap cache misses can be monitored though a callback:

```ruby
Bootsnap.instrumentation = ->(event, path) { puts "#{event} #{path}" }
```

`event` is either `:hit`, `:miss`, `:stale` or `:revalidated`.
You can also call `Bootsnap.log!` as a shortcut to log all events to STDERR.

To turn instrumentation back off you can set it to nil:

```ruby
Bootsnap.instrumentation = nil
```

## How does this work?

Bootsnap optimizes methods to cache results of expensive computations, and can be grouped
into two broad categories:

* [Path Pre-Scanning](#path-pre-scanning)
    * `Kernel#require` and `Kernel#load` are modified to eliminate `$LOAD_PATH` scans.
* [Compilation caching](#compilation-caching)
    * `RubyVM::InstructionSequence.load_iseq` is implemented to cache the result of ruby bytecode
      compilation.
    * `YAML.load_file` is modified to cache the result of loading a YAML object in MessagePack format
      (or Marshal, if the message uses types unsupported by MessagePack).
    * `JSON.load_file` is modified to cache the result of loading a JSON object in MessagePack format

### Path Pre-Scanning

*(This work is a minor evolution of [bootscale](https://github.com/byroot/bootscale)).*

Upon initialization of bootsnap or modification of the path (e.g. `$LOAD_PATH`),
`Bootsnap::LoadPathCache` will fetch a list of requirable entries from a cache, or, if necessary,
perform a full scan and cache the result.

Later, when we run (e.g.) `require 'foo'`, ruby *would* iterate through every item on our
`$LOAD_PATH` `['x', 'y', ...]`,  looking for `x/foo.rb`, `y/foo.rb`, and so on. Bootsnap instead
looks at all the cached requirables for each `$LOAD_PATH` entry and substitutes the full expanded
path of the match ruby would have eventually chosen.

If you look at the syscalls generated by this behaviour, the net effect is that what would
previously look like this:

```
open  x/foo.rb # (fail)
# (imagine this with 500 $LOAD_PATH entries instead of two)
open  y/foo.rb # (success)
close y/foo.rb
open  y/foo.rb
...
```

becomes this:

```
open y/foo.rb
...
```

The following diagram flowcharts the overrides that make the `*_path_cache` features work.

![Flowchart explaining
Bootsnap](https://cloud.githubusercontent.com/assets/3074765/24532120/eed94e64-158b-11e7-9137-438d759b2ac8.png)

Bootsnap classifies path entries into two categories: stable and volatile. Volatile entries are
scanned each time the application boots, and their caches are only valid for 30 seconds. Stable
entries do not expire -- once their contents has been scanned, it is assumed to never change.

The only directories considered "stable" are things under the Ruby install prefix
(`RbConfig::CONFIG['prefix']`, e.g. `/usr/local/ruby` or `~/.rubies/x.y.z`), and things under the
`Gem.path` (e.g. `~/.gem/ruby/x.y.z`) or `Bundler.bundle_path`. Everything else is considered
"volatile".

In addition to the [`Bootsnap::LoadPathCache::Cache`
source](https://github.com/Shopify/bootsnap/blob/main/lib/bootsnap/load_path_cache/cache.rb),
this diagram may help clarify how entry resolution works:

![How path searching works](https://cloud.githubusercontent.com/assets/3074765/25388270/670b5652-299b-11e7-87fb-975647f68981.png)


It's also important to note how expensive `LoadError`s can be. If ruby invokes
`require 'something'`, but that file isn't on `$LOAD_PATH`, it takes `2 *
$LOAD_PATH.length` filesystem accesses to determine that. Bootsnap caches this
result too, raising a `LoadError` without touching the filesystem at all.

### Compilation Caching

*(A more readable implementation of this concept can be found in
[yomikomu](https://github.com/ko1/yomikomu)).*

Ruby has complex grammar and parsing it is not a particularly cheap operation. Since 1.9, Ruby has
translated ruby source to an internal bytecode format, which is then executed by the Ruby VM. Since
2.3.0, Ruby [exposes an API](https://ruby-doc.org/core-2.3.0/RubyVM/InstructionSequence.html) that
allows caching that bytecode. This allows us to bypass the relatively-expensive compilation step on
subsequent loads of the same file.

We also noticed that we spend a lot of time loading YAML and JSON documents during our application boot, and
that MessagePack and Marshal are *much* faster at deserialization than YAML and JSON, even with a fast
implementation. We use the same strategy of compilation caching for YAML and JSON documents, with the
equivalent of Ruby's "bytecode" format being a MessagePack document (or, in the case of YAML
documents with types unsupported by MessagePack, a Marshal stream).

These compilation results are stored in a cache directory, with filenames generated by taking a hash
of the full expanded path of the input file (FNV1a-64).

Whereas before, the sequence of syscalls generated to `require` a file would look like:

```
open    /c/foo.rb -> m
fstat64 m
close   m
open    /c/foo.rb -> o
fstat64 o
fstat64 o
read    o
read    o
...
close   o
```

With bootsnap, we get:

```
open      /c/foo.rb -> n
fstat64   n
close     n
open      /c/foo.rb -> n
fstat64   n
open      (cache) -> m
read      m
read      m
close     m
close     n
```

This may look worse at a glance, but underlies a large performance difference.

*(The first three syscalls in both listings -- `open`, `fstat64`, `close` -- are not inherently
useful. [This ruby patch](https://bugs.ruby-lang.org/issues/13378) optimizes them out when coupled
with bootsnap.)*

Bootsnap writes a cache file containing a 64 byte header followed by the cache contents. The header
is a cache key including several fields:

* `version`, hardcoded in bootsnap. Essentially a schema version;
* `ruby_platform`, A hash of `RUBY_PLATFORM` (e.g. x86_64-linux-gnu) variable.
* `compile_option`, which changes with `RubyVM::InstructionSequence.compile_option` does;
* `ruby_revision`, A hash of `RUBY_REVISION`, the exact version of Ruby;
* `size`, the size of the source file;
* `mtime`, the last-modification timestamp of the source file when it was compiled; and
* `data_size`, the number of bytes following the header, which we need to read it into a buffer.

If the key is valid, the result is loaded from the value. Otherwise, it is regenerated and clobbers
the current cache.

### Putting it all together

Imagine we have this file structure:

```
/
├── a
├── b
└── c
    └── foo.rb
```

And this `$LOAD_PATH`:

```
["/a", "/b", "/c"]
```

When we call `require 'foo'` without bootsnap, Ruby would generate this sequence of syscalls:


```
open    /a/foo.rb -> -1
open    /b/foo.rb -> -1
open    /c/foo.rb -> n
close   n
open    /c/foo.rb -> m
fstat64 m
close   m
open    /c/foo.rb -> o
fstat64 o
fstat64 o
read    o
read    o
...
close   o
```

With bootsnap, we get:

```
open      /c/foo.rb -> n
fstat64   n
close     n
open      /c/foo.rb -> n
fstat64   n
open      (cache) -> m
read      m
read      m
close     m
close     n
```

If we call `require 'nope'` without bootsnap, we get:

```
open    /a/nope.rb -> -1
open    /b/nope.rb -> -1
open    /c/nope.rb -> -1
open    /a/nope.bundle -> -1
open    /b/nope.bundle -> -1
open    /c/nope.bundle -> -1
```

...and if we call `require 'nope'` *with* bootsnap, we get...

```
# (nothing!)
```

## Precompilation

In development environments the bootsnap compilation cache is generated on the fly when source files are loaded.
But in production environments, such as docker images, you might need to precompile the cache.

To do so you can use the `bootsnap precompile` command.

Example:

```bash
$ bundle exec bootsnap precompile --gemfile app/ lib/
```

## When not to use Bootsnap

*Alternative engines*: Bootsnap is pretty reliant on MRI features, and parts are disabled entirely on alternative ruby
engines.

*Non-local filesystems*: Bootsnap depends on `tmp/cache` (or whatever you set its cache directory
to) being on a relatively fast filesystem. If you put it on a network mount, bootsnap is very likely
to slow your application down quite a lot.
