# Unreleased

# 1.18.4

* Allow using bootsnap without bundler. See #488.
* Fix startup failure if the cache directory points to a broken symlink.

# 1.18.3

* Fix the cache corruption issue in the revalidation feature. See #474.
  The cache revalidation feature remains opt-in for now, until it is more battle tested.

# 1.18.2

* Disable stale cache entries revalidation by default as it seems to cause cache corruption issues. See #471 and #474.
  Will be re-enabled in a future version once the root cause is identified.
* Fix a potential compilation issue on some systems. See #470.

# 1.18.1

* Handle `EPERM` errors when opening files with `O_NOATIME`.

# 1.18.0

* `Bootsnap.instrumentation` now receive `:hit` events.
* Add `Bootsnap.log_stats!` to print hit rate statistics on process exit. Can also be enabled with `BOOTSNAP_STATS=1`.
* Revalidate stale cache entries by digesting the source content.
  This should significantly improve performance in environments where `mtime` isn't preserved (e.g. CI systems doing a git clone, etc).
  See #468.
* Open source files and cache entries with `O_NOATIME` when available to reduce disk accesses. See #469.
* `bootsnap precompile --gemfile` now look for `.rb` files in the whole gem and not just the `lib/` directory. See #466.

# 1.17.1

* Fix a compatibility issue with the `prism` library that ships with Ruby 3.3. See #463.
* Improved the `Kernel#require` decorator to not cause a method redefinition warning. See #461.

# 1.17.0

* Ensure `$LOAD_PATH.dup` is Ractor shareable to fix a conflict with `did_you_mean`.
* Allow to ignore directories using absolute paths.
* Support YAML and JSON CompileCache on TruffleRuby.
* Support LoadPathCache on TruffleRuby.

# 1.16.0

* Use `RbConfig::CONFIG["rubylibdir"]` instead of `RbConfig::CONFIG["libdir"]` to check for stdlib files. See #431.
* Fix the cached version of `YAML.load_file` being slightly more permissive than the default `Psych` one. See #434.
  `Date` and `Time` values are now properly rejected, as well as aliases.
  If this causes a regression in your application, it is recommended to load *trusted* YAML files with `YAML.unsafe_load_file`.

# 1.15.0

* Add a readonly mode, for environments in which the updated cache wouldn't be persisted. See #428 and #423.

# 1.14.0

* Require Ruby 2.6.
* Add a way to skip directories during load path scanning.
  If you have large non-ruby directories in the middle of your load path, it can severely slow down scanning.
  Typically this is a problem with `node_modules`. See #277.
* Fix `Bootsnap.unload_cache!`, it simply wouldn't work at all because of a merge mistake. See #421.

# 1.13.0

* Stop decorating `Kernel.load`. This used to be very useful in development because the Rails "classic" autoloader
  was using `Kernel.load` in dev and `Kernel.require` in production. But Zeitwerk is now the default, and it doesn't
  use `Kernel.load` at all.

  People still using the classic autoloader might want to stick to `bootsnap 1.12`.

* Add `Bootsnap.unload_cache!`. Applications can call it at the end of their boot sequence when they know
  no more code will be loaded to reclaim a bit of memory.

# 1.12.0

* `bootsnap precompile` CLI will now also precompile `Rakefile` and `.rake` files.

* Stop decorating `Module#autoload` as it was only useful for supporting Ruby 2.2 and older.

* Remove `uname` and other platform specific version from the cache keys. `RUBY_PLATFORM + RUBY_REVISION` should be
  enough to ensure bytecode compatibility. This should improve caching for alpine based setups. See #409.

# 1.11.1

* Fix the `can't modify frozen Hash` error on load path cache mutation. See #411.

# 1.11.0

* Drop dependency on `fileutils`.

* Better respect `Kernel#require` duck typing. While it almost never comes up in practice, `Kernel#require`
  follow a fairly intricate duck-typing protocol on its argument implemented as `rb_get_path(VALUE)` in MRI.
  So when applicable we bind `rb_get_path` and use it for improved compatibility. See #396 and #406.

* Get rid of the `Kernel.require_relative` decorator by resolving `$LOAD_PATH` members to their real path.
  This way we handle symlinks in `$LOAD_PATH` much more efficiently. See #402 for the detailed explanation.
  
* Drop support for Ruby 2.3 (to allow getting rid of the `Kernel.require_relative` decorator).

# 1.10.3

* Fix Regexp and Date type support in YAML compile cache. (#400)

* Improve the YAML compile cache to support `UTF-8` symbols. (#398, #399)
  [The default `MessagePack` symbol serializer assumes all symbols are ASCII](https://github.com/msgpack/msgpack-ruby/pull/211),
  because of this, non-ASCII compatible symbol would be restored with `ASCII_8BIT` encoding (AKA `BINARY`).
  Bootsnap now properly cache them in `UTF-8`.

  Note that the above only apply for actual YAML symbols (e..g `--- :foo`).
  The issue is still present for string keys parsed with `YAML.load_file(..., symbolize_names: true)`, that is a bug
  in `msgpack` that will hopefully be solved soon, see: https://github.com/msgpack/msgpack-ruby/pull/246

* Entirely disable the YAML compile cache if `Encoding.default_internal` is set to an encoding not supported by `msgpack`. (#398)
  `Psych` coerce strings to `Encoding.default_internal`, but `MessagePack` doesn't. So in this scenario we can't provide
  YAML caching at all without returning the strings in the wrong encoding.
  This never came up in practice but might as well be safe.

# 1.10.2

* Reduce the `Kernel.require` extra stack frames some more. Now bootsnap should only add one extra frame per `require` call.

* Better check `freeze` option support in JSON compile cache.
  Previously `JSON.load_file(..., freeze: true)` would be cached even when the msgpack version is missing support for it.

# 1.10.1

* Fix `Kernel#autoload`'s fallback path always being executed.

* Consider `unlink` failing with `ENOENT` as a success.

# 1.10.0

* Delay requiring `FileUtils`. (#285)
  `FileUtils` can be installed as a gem, so it's best to wait for bundler to have setup the load path before requiring it.

* Improve support of Psych 4. (#392)
  Since `1.8.0`, `YAML.load_file` was no longer cached when Psych 4 was used. This is because `load_file` loads
  in safe mode by default, so the Bootsnap cache could defeat that safety.
  Now when precompiling YAML files, Bootsnap first try to parse them in safe mode, and if it can't fallback to unsafe mode,
  and the cache contains a flag that records whether it was generated in safe mode or not.
  `YAML.unsafe_load_file` will use safe caches just fine, but `YAML.load_file` will fallback to uncached YAML parsing
  if the cache was generated using unsafe parsing.

* Minimize the Kernel.require extra stack frames. (#393)
  This should reduce the noise generated by bootsnap on `LoadError`.

# 1.9.4

* Ignore absolute paths in the loaded feature index. (#385)
  This fixes a compatibility issue with Zeitwerk when Zeitwerk is loaded before bootsnap. It also should
  reduce the memory usage and improve load performance of Zeitwerk managed files.

* Automatically invalidate the load path cache whenever the Ruby version change. (#387)
  This is to avoid issues in case the same installation path is re-used for subsequent ruby patch releases.

# 1.9.3

* Only disable the compile cache for source files impacted by [Ruby 3.0.3 [Bug 18250]](https://bugs.ruby-lang.org/issues/18250).
  This should keep the performance loss to a minimum.

# 1.9.2

* Disable compile cache if [Ruby 3.0.3's ISeq cache bug](https://bugs.ruby-lang.org/issues/18250) is detected.
  AKA `iseq.rb:13 to_binary: wrong argument type false (expected Symbol)`
* Fix `Kernel.load` behavior: before `load 'a'` would load `a.rb` (and other tried extensions) and wouldn't load `a` unless `development_mode: true`, now only `a` would be loaded and files with extensions wouldn't be.

# 1.9.1

* Removed a forgotten debug statement in JSON precompilation.

# 1.9.0

* Added a compilation cache for `JSON.load_file`. (#370)

# 1.8.1

* Fixed support for older Psych. (#369)

# 1.8.0

* Improve support for Psych 4. (#368)

# 1.7.7

* Fix `require_relative` in evaled code on latest ruby 3.1.0-dev. (#366)

# 1.7.6

* Fix reliance on `set` to be required.
* Fix `Encoding::UndefinedConversionError` error for Rails applications when precompiling cache. (#364)

# 1.7.5

* Handle a regression of Ruby 2.7.3 causing Bootsnap to call the deprecated `untaint` method. (#360)
* Gracefully handle read-only file system as well as other errors preventing to persist the load path cache. (#358)

# 1.7.4

* Stop raising errors when encountering various file system errors. The cache is now best effort,
  if somehow it can't be saved, bootsnap will gracefully fallback to the original operation (e.g. `Kernel.require`).
  (#353, #177, #262)

# 1.7.3

* Disable YAML precompilation when encountering YAML tags. (#351)

# 1.7.2

* Fix compatibility with msgpack < 1. (#349)

# 1.7.1

* Warn Ruby 2.5 users if they turn ISeq caching on. (#327, #244)
* Disable ISeq caching for the whole 2.5.x series again.
* Better handle hashing of Ruby strings. (#318)

# 1.7.0

* Fix detection of YAML files in gems.
* Adds an instrumentation API to monitor cache misses.
* Allow to control the behavior of `require 'bootsnap/setup'` using environment variables.
* Deprecate the `disable_trace` option.
* Deprecate the `ActiveSupport::Dependencies` (AKA Classic autoloader) integration. (#344) 

# 1.6.0

* Fix a Ruby 2.7/3.0 issue with `YAML.load_file` keyword arguments. (#342)
* `bootsnap precompile` CLI use multiple processes to complete faster. (#341)
* `bootsnap precompile` CLI also precompile YAML files. (#340)
* Changed the load path cache directory from `$BOOTSNAP_CACHE_DIR/bootsnap-load-path-cache` to `$BOOTSNAP_CACHE_DIR/bootsnap/load-path-cache` for ease of use. (#334)
* Changed the compile cache directory from `$BOOTSNAP_CACHE_DIR/bootsnap-compile-cache` to `$BOOTSNAP_CACHE_DIR/bootsnap/compile-cache` for ease of use. (#334)

# 1.5.1

* Workaround a Ruby bug in InstructionSequence.compile_file. (#332)

# 1.5.0

* Add a command line to statically precompile the ISeq cache. (#326)

# 1.4.9

* [Windows support](https://github.com/Shopify/bootsnap/pull/319)
* [Fix potential crash](https://github.com/Shopify/bootsnap/pull/322)

# 1.4.8

* [Prevent FallbackScan from polluting exception cause](https://github.com/Shopify/bootsnap/pull/314)

# 1.4.7

* Various performance enhancements
* Fix race condition in heavy concurrent load scenarios that would cause bootsnap to raise

# 1.4.6

* Fix bug that was erroneously considering that files containing `.` in the names were being
  required if a different file with the same name was already being required

  Example:
  
      require 'foo'
      require 'foo.en'

  Before bootsnap was considering `foo.en` to be the same file as `foo`

* Use glibc as part of the ruby_platform cache key

# 1.4.5

* MRI 2.7 support
* Fixed concurrency bugs

# 1.4.4

* Disable ISeq cache in `bootsnap/setup` by default in Ruby 2.5

# 1.4.3

* Fix some cache permissions and umask issues after switch to mkstemp

# 1.4.2

* Fix bug when removing features loaded by relative path from `$LOADED_FEATURES`
* Fix bug with propagation of `NameError` up from nested calls to `require`

# 1.4.1

* Don't register change observers to frozen objects.

# 1.4.0

* When running in development mode, always fall back to a full path scan on LoadError, making
  bootsnap more able to detect newly-created files. (#230)
* Respect `$LOADED_FEATURES.delete` in order to support code reloading, for integration with
  Zeitwerk. (#230)
* Minor performance improvement: flow-control exceptions no longer generate backtraces.
* Better support for requiring from environments where some features are not supported (especially
  JRuby). (#226)k
* More robust handling of OS errors when creating files. (#225)

# 1.3.2

* Fix Spring + Bootsnap incompatibility when there are files with similar names.
* Fix `YAML.load_file` monkey patch to keep accepting File objects as arguments.
* Fix the API for `ActiveSupport::Dependencies#autoloadable_module?`.
* Some performance improvements.

# 1.3.1

* Change load path scanning to more correctly follow symlinks.

# 1.3.0

* Handle cases where load path entries are symlinked (https://github.com/Shopify/bootsnap/pull/136)

# 1.2.1

* Fix method visibility of `Kernel#require`.

# 1.2.0

* Add `LoadedFeaturesIndex` to preserve fix a common bug related to `LOAD_PATH` modifications after
  loading bootsnap.

# 1.1.8

* Don't cache YAML documents with `!ruby/object`
* Fix cache write mode on Windows

# 1.1.7

* Create cache entries as 0775/0664 instead of 0755/0644
* Better handling around cache updates in highly-parallel workloads

# 1.1.6

* Assortment of minor bugfixes

# 1.1.5

* bugfix re-release of 1.1.4

# 1.1.4 (yanked)

* Avoid loading a constant twice by checking if it is already defined

# 1.1.3

* Properly resolve symlinked path entries

# 1.1.2

* Minor fix: deprecation warning

# 1.1.1

* Fix crash in `Native.compile_option_crc32=` on 32-bit platforms.

# 1.1.0

* Add `bootsnap/setup`
* Support jruby (without compile caching features)
* Better deoptimization when Coverage is enabled
* Consider `Bundler.bundle_path` to be stable

# 1.0.0

* (none)

# 0.3.2

* Minor performance savings around checking validity of cache in the presence of relative paths.
* When coverage is enabled, skips optimization instead of exploding.

# 0.3.1

* Don't whitelist paths under `RbConfig::CONFIG['prefix']` as stable; instead use `['libdir']` (#41).
* Catch `EOFError` when reading load-path-cache and regenerate cache.
* Support relative paths in load-path-cache.

# 0.3.0

* Migrate CompileCache from xattr as a cache backend to a cache directory
    * Adds support for Linux and FreeBSD

# 0.2.15

* Support more versions of ActiveSupport (`depend_on`'s signature varies; don't reiterate it)
* Fix bug in handling autoloaded modules that raise NoMethodError
