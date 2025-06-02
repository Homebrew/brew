# NEWS for Ruby 3.3.0

This document is a list of user-visible feature changes
since the **3.2.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Command line options

* A new `performance` warning category was introduced.
  They are not displayed by default even in verbose mode.
  Turn them on with `-W:performance` or `Warning[:performance] = true`. [[Feature #19538]]

* A new `RUBY_CRASH_REPORT` environment variable was introduced to allow
  redirecting Ruby crash reports to a file or sub command. See the `BUG REPORT ENVIRONMENT`
  section of the ruby manpage for further details. [[Feature #19790]]

## Core classes updates

Note: We're only listing outstanding class updates.

* Array

    * Array#pack now raises ArgumentError for unknown directives. [[Bug #19150]]

* Dir

    * Dir.for_fd added for returning a Dir object for the directory specified
      by the provided directory file descriptor. [[Feature #19347]]
    * Dir.fchdir added for changing the directory to the directory specified
      by the provided directory file descriptor. [[Feature #19347]]
    * Dir#chdir added for changing the directory to the directory specified by
      the provided `Dir` object. [[Feature #19347]]

* Encoding

    * `Encoding#replicate` has been removed, it was already deprecated.  [[Feature #18949]]

* Fiber

    * Introduce Fiber#kill. [[Bug #595]]

        ```ruby
        fiber = Fiber.new do
          while true
            puts "Yielding..."
            Fiber.yield
          end
        ensure
          puts "Exiting..."
        end

        fiber.resume
        # Yielding...
        fiber.kill
        # Exiting...
        ```

* MatchData

    * MatchData#named_captures now accepts optional `symbolize_names`
      keyword. [[Feature #19591]]

* Module

    * Module#set_temporary_name added for setting a temporary name for a
      module. [[Feature #19521]]

* ObjectSpace::WeakKeyMap

    * New core class to build collections with weak references.
      The class use equality semantic to lookup keys like a regular hash,
      but it doesn't hold strong references on the keys. [[Feature #18498]]

* ObjectSpace::WeakMap

    * ObjectSpace::WeakMap#delete was added to eagerly clear weak map
      entries. [[Feature #19561]]

* Proc
    * Now Proc#dup and Proc#clone call `#initialize_dup` and `#initialize_clone`
      hooks respectively.  [[Feature #19362]]

* Process

    * New Process.warmup method that notify the Ruby virtual machine that the boot sequence is finished,
      and that now is a good time to optimize the application. This is useful
      for long-running applications. The actual optimizations performed are entirely
      implementation-specific and may change in the future without notice. [[Feature #18885]]

* Process::Status

    * Process::Status#& and Process::Status#>> are deprecated. [[Bug #19868]]

* Range

    * Range#reverse_each can now process beginless ranges with an Integer endpoint. [[Feature #18515]]
    * Range#reverse_each now raises TypeError for endless ranges. [[Feature #18551]]
    * Range#overlap? added for checking if two ranges overlap. [[Feature #19839]]

* Refinement

    * Add Refinement#target as an alternative of Refinement#refined_class.
      Refinement#refined_class is deprecated and will be removed in Ruby
      3.4.  [[Feature #19714]]

* Regexp

    * The cache-based optimization now supports lookarounds and atomic groupings. That is, match
      for Regexp containing these extensions can now also be performed in linear time to the length
      of the input string. However, these cannot contain captures and cannot be nested. [[Feature #19725]]

* String

    * String#unpack now raises ArgumentError for unknown directives. [[Bug #19150]]
    * String#bytesplice now accepts new arguments index/length or range of the
      source string to be copied.  [[Feature #19314]]

* Thread::Queue

    * Thread::Queue#freeze now raises TypeError. [[Bug #17146]]

* Thread::SizedQueue

    * Thread::SizedQueue#freeze now raises TypeError. [[Bug #17146]]

* Time

    * Time.new with a string argument became stricter. [[Bug #19293]]

        ```ruby
        Time.new('2023-12-20')
        #  no time information (ArgumentError)
        ```

* TracePoint

    * TracePoint supports `rescue` event. When the raised exception was rescued,
      the TracePoint will fire the hook. `rescue` event only supports Ruby-level
      `rescue`. [[Feature #19572]]

## Stdlib updates

* RubyGems and Bundler warn if users do `require` the following gems without adding them to Gemfile or gemspec.
  This is because they will become the bundled gems in the future version of Ruby. This warning is suppressed
  if you use bootsnap gem. We recommend to run your application with `DISABLE_BOOTSNAP=1` environmental variable
  at least once. This is limitation of this version.
  [[Feature #19351]] [[Feature #19776]] [[Feature #19843]]
    * abbrev
    * base64
    * bigdecimal
    * csv
    * drb
    * getoptlong
    * mutex_m
    * nkf
    * observer
    * racc
    * resolv-replace
    * rinda
    * syslog

* Socket#recv and Socket#recv_nonblock returns `nil` instead of an empty string on closed
  connections. Socket#recvmsg and Socket#recvmsg_nonblock returns `nil` instead of an empty packet on closed
  connections. [[Bug #19012]]

* Name resolution such as Socket.getaddrinfo, Socket.getnameinfo, Addrinfo.getaddrinfo, etc.
  can now be interrupted. [[Feature #19965]]

* Random::Formatter#alphanumeric is extended to accept optional `chars`
  keyword argument. [[Feature #18183]]

The following default gem is added.

* prism 0.19.0

The following default gems are updated.

* RubyGems 3.5.3
* abbrev 0.1.2
* base64 0.2.0
* benchmark 0.3.0
* bigdecimal 3.1.5
* bundler 2.5.3
* cgi 0.4.1
* csv 3.2.8
* date 3.3.4
* delegate 0.3.1
* drb 2.2.0
* english 0.8.0
* erb 4.0.3
* error_highlight 0.6.0
* etc 1.4.3
* fcntl 1.1.0
* fiddle 1.1.2
* fileutils 1.7.2
* find 0.2.0
* getoptlong 0.2.1
* io-console 0.7.1
* io-nonblock 0.3.0
* io-wait 0.3.1
* ipaddr 1.2.6
* irb 1.11.0
* json 2.7.1
* logger 1.6.0
* mutex_m 0.2.0
* net-http 0.4.0
* net-protocol 0.2.2
* nkf 0.1.3
* observer 0.1.2
* open-uri 0.4.1
* open3 0.2.1
* openssl 3.2.0
* optparse 0.4.0
* ostruct 0.6.0
* pathname 0.3.0
* pp 0.5.0
* prettyprint 0.2.0
* pstore 0.1.3
* psych 5.1.2
* rdoc 6.6.2
* readline 0.0.4
* reline 0.4.1
* resolv 0.3.0
* rinda 0.2.0
* securerandom 0.3.1
* set 1.1.0
* shellwords 0.2.0
* singleton 0.2.0
* stringio 3.1.0
* strscan 3.0.7
* syntax_suggest 2.0.0
* syslog 0.1.2
* tempfile 0.2.1
* time 0.3.0
* timeout 0.4.1
* tmpdir 0.2.0
* tsort 0.2.0
* un 0.3.0
* uri 0.13.0
* weakref 0.1.3
* win32ole 1.8.10
* yaml 0.3.0
* zlib 3.1.0

The following bundled gem is promoted from default gems.

* racc 1.7.3

The following bundled gems are updated.

* minitest 5.20.0
* rake 13.1.0
* test-unit 3.6.1
* rexml 3.2.6
* rss 0.3.0
* net-ftp 0.3.3
* net-imap 0.4.9
* net-smtp 0.4.0
* rbs 3.4.0
* typeprof 0.21.9
* debug 1.9.1

See GitHub releases like [Logger](https://github.com/ruby/logger/releases) or
changelog for details of the default gems or bundled gems.

### Prism

* Introduced [the Prism parser](https://github.com/ruby/prism) as a default gem
    * Prism is a portable, error tolerant, and maintainable recursive descent parser for the Ruby language
* Prism is production ready and actively maintained, you can use it in place of Ripper
    * There is [extensive documentation](https://ruby.github.io/prism/) on how to use Prism
    * Prism is both a C library that will be used internally by CRuby and a Ruby gem that can be used by any tooling which needs to parse Ruby code
    * Notable methods in the Prism API are:
        * `Prism.parse(source)` which returns the AST as part of a parse result object
        * `Prism.parse_comments(source)` which returns the comments
        * `Prism.parse_success?(source)` which returns true if there are no errors
* You can make pull requests or issues directly on [the Prism repository](https://github.com/ruby/prism) if you are interested in contributing
* You can now use `ruby --parser=prism` or `RUBYOPT="--parser=prism"` to experiment with the Prism compiler. Please note that this flag is for debugging only.

## Compatibility issues

* Subprocess creation/forking via the following file open methods is deprecated. [[Feature #19630]]
    * Kernel#open
    * URI.open
    * IO.binread
    * IO.foreach
    * IO.readlines
    * IO.read
    * IO.write

* When given a non-lambda, non-literal block, Kernel#lambda with now raises
  ArgumentError instead of returning it unmodified. These usages have been
  issuing warnings under the `Warning[:deprecated]` category since Ruby 3.0.0.
  [[Feature #19777]]

* The `RUBY_GC_HEAP_INIT_SLOTS` environment variable has been deprecated and
  removed. Environment variables `RUBY_GC_HEAP_%d_INIT_SLOTS` should be
  used instead.  [[Feature #19785]]

* `it` calls without arguments in a block with no ordinary parameters are
  deprecated. `it` will be a reference to the first block parameter in Ruby 3.4.
  [[Feature #18980]]

* Error message for NoMethodError have changed to not use the target object's `#inspect`
  for efficiency, and says "instance of ClassName" instead. [[Feature #18285]]

    ```ruby
    ([1] * 100).nonexisting
    # undefined method `nonexisting' for an instance of Array (NoMethodError)
    ```

* Now anonymous parameters forwarding is disallowed inside a block
  that uses anonymous parameters.  [[Feature #19370]]

## Stdlib compatibility issues

* `racc` is promoted to bundled gems.
    * You need to add `racc` to your `Gemfile` if you use `racc` under bundler environment.
* `ext/readline` is retired
    * We have `reline` that is pure Ruby implementation compatible with `ext/readline` API.
      We rely on `reline` in the future. If you need to use `ext/readline`, you can install
      `ext/readline` via rubygems.org with `gem install readline-ext`.
    * We no longer need to install libraries like `libreadline` or `libedit`.

## C API updates

* `rb_postponed_job` updates
  * New APIs and deprecated APIs (see comments for details)
    * added: `rb_postponed_job_preregister()`
    * added: `rb_postponed_job_trigger()`
    * deprecated: `rb_postponed_job_register()` (and semantic change. see below)
    * deprecated: `rb_postponed_job_register_one()`
  * The postponed job APIs have been changed to address some rare crashes.
    To solve the issue, we introduced new two APIs and deprecated current APIs.
    The semantics of these functions have also changed slightly; `rb_postponed_job_register`
    now behaves like the `once` variant in that multiple calls with the same
    `func` might be coalesced into a single execution of the `func`
    [[Feature #20057]]

* Some updates for internal thread event hook APIs
  * `rb_internal_thread_event_data_t` with a target Ruby thread (VALUE)
    and callback functions (`rb_internal_thread_event_callback`) receive it.
    https://github.com/ruby/ruby/pull/8885
  * The following functions are introduced to manipulate Ruby thread local data
    from internal thread event hook APIs (they are introduced since Ruby 3.2).
    https://github.com/ruby/ruby/pull/8936
    * `rb_internal_thread_specific_key_create()`
    * `rb_internal_thread_specific_get()`
    * `rb_internal_thread_specific_set()`

* `rb_profile_thread_frames()` is introduced to get a frames from
  a specific thread.
  [[Feature #10602]]

* `rb_data_define()` is introduced to define `Data`. [[Feature #19757]]

* `rb_ext_resolve_symbol()` is introduced to search a function from
  extension libraries. [[Feature #20005]]

* IO related updates:
  * The details of `rb_io_t` will be hidden and deprecated attributes
    are added for each members. [[Feature #19057]]
  * `rb_io_path(VALUE io)` is introduced to get a path of `io`.
  * `rb_io_closed_p(VALUE io)` to get opening or closing of `io`.
  * `rb_io_mode(VALUE io)` to get the mode of `io`.
  * `rb_io_open_descriptor()` is introduced to make an IO object from a file
    descriptor.

## Implementation improvements

### Parser

* Replace Bison with [Lrama LALR parser generator](https://github.com/ruby/lrama).
  No need to install Bison to build Ruby from source code anymore.
  We will no longer suffer bison compatibility issues and we can use new features by just implementing it to Lrama. [[Feature #19637]]
  * See [The future vision of Ruby Parser](https://rubykaigi.org/2023/presentations/spikeolaf.html) for detail.
  * Lrama internal parser is a LR parser generated by Racc for maintainability.
  * Parameterizing Rules `(?, *, +)` are supported, it will be used in Ruby parse.y.

### GC / Memory management

* Major performance improvements over Ruby 3.2
    * Young objects referenced by old objects are no longer immediately
      promoted to the old generation. This significantly reduces the frequency of
      major GC collections. [[Feature #19678]]
    * A new `REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO` tuning variable was
      introduced to control the number of unprotected objects cause a major GC
      collection to trigger. The default is set to `0.01` (1%). This significantly
      reduces the frequency of major GC collection. [[Feature #19571]]
    * Write Barriers were implemented for many core types that were missing them,
      notably `Time`, `Enumerator`, `MatchData`, `Method`, `File::Stat`, `BigDecimal`
      and several others. This significantly reduces minor GC collection time and major
      GC collection frequency.
    * Most core classes are now using Variable Width Allocation, notably `Hash`, `Time`,
      `Thread::Backtrace`, `Thread::Backtrace::Location`, `File::Stat`, `Method`.
      This makes these classes faster to allocate and free, use less memory and reduce
      heap fragmentation.
* `defined?(@ivar)` is optimized with Object Shapes.

### YJIT

* Major performance improvements over Ruby 3.2
  * Support for splat and rest arguments has been improved.
  * Registers are allocated for stack operations of the virtual machine.
  * More calls with optional arguments are compiled. Exception handlers are also compiled.
  * Unsupported call types and megamorphic call sites no longer exit to the interpreter.
  * Basic methods like Rails `#blank?` and
    [specialized `#present?`](https://github.com/rails/rails/pull/49909) are inlined.
  * `Integer#*`, `Integer#!=`, `String#!=`, `String#getbyte`,
    `Kernel#block_given?`, `Kernel#is_a?`, `Kernel#instance_of?`, and `Module#===`
    are specially optimized.
  * Compilation speed is now slightly faster than Ruby 3.2.
  * Now more than 3x faster than the interpreter on Optcarrot!
* Significantly improved memory usage over Ruby 3.2
    * Metadata for compiled code uses a lot less memory.
    * `--yjit-call-threshold` is automatically raised from 30 to 120
      when the application has more than 40,000 ISEQs.
    * `--yjit-cold-threshold` is added to skip compiling cold ISEQs.
    * More compact code is generated on Arm64.
* Code GC is now disabled by default
  * `--yjit-exec-mem-size` is treated as a hard limit where compilation of new code stops.
  * No sudden drops in performance due to code GC.
    Better copy-on-write behavior on servers reforking with
    [Pitchfork](https://github.com/shopify/pitchfork).
  * You can still enable code GC if desired with `--yjit-code-gc`
* Add `RubyVM::YJIT.enable` that can enable YJIT at run-time
  * You can start YJIT without modifying command-line arguments or environment variables.
    Rails 7.2 will [enable YJIT by default](https://github.com/rails/rails/pull/49947)
    using this method.
  * This can also be used to enable YJIT only once your application is
    done booting. `--yjit-disable` can be used if you want to use other
    YJIT options while disabling YJIT at boot.
* More YJIT stats are available by default
  * `yjit_alloc_size` and several more metadata-related stats are now available by default.
  * `ratio_in_yjit` stat produced by `--yjit-stats` is now available in release builds,
    a special stats or dev build is no longer required to access most stats.
* Add more profiling capabilities
  * `--yjit-perf` is added to facilitate profiling with Linux perf.
  * `--yjit-trace-exits` now supports sampling with `--yjit-trace-exits-sample-rate=N`
* More thorough testing and multiple bug fixes
* `--yjit-stats=quiet` is added to avoid printing stats on exit.

### MJIT

* MJIT is removed.
    * `--disable-jit-support` is removed. Consider using `--disable-yjit --disable-rjit` instead.

### RJIT

* Introduced a pure-Ruby JIT compiler RJIT.
    * RJIT supports only x86\_64 architecture on Unix platforms.
    * Unlike MJIT, it doesn't require a C compiler at runtime.
* RJIT exists only for experimental purposes.
    * You should keep using YJIT in production.

### M:N Thread scheduler

* M:N Thread scheduler is introduced. [[Feature #19842]]
    * Background: Ruby 1.8 and before, M:1 thread scheduler (M Ruby threads
      with 1 native thread. Called as User level threads or Green threads)
      is used. Ruby 1.9 and later, 1:1 thread scheduler (1 Ruby thread with
      1 native thread). M:1 threads takes lower resources compare with 1:1
      threads because it needs only 1 native threads. However it is difficult
      to support context switching for all of blocking operation so 1:1
      threads are employed from Ruby 1.9. M:N thread scheduler uses N native
      threads for M Ruby threads (N is small number in general). It doesn't
      need same number of native threads as Ruby threads (similar to the M:1
      thread scheduler). Also our M:N threads supports blocking operations
      well same as 1:1 threads. See the ticket for more details.
      Our M:N thread scheduler refers on the goroutine scheduler in the
      Go language.
    * In a ractor, only 1 thread can run in a same time because of
      implementation. Therefore, applications that use only one Ractor
      (most applications) M:N thread scheduler works as M:1 thread scheduler
      with further extension from Ruby 1.8.
    * M:N thread scheduler can introduce incompatibility for C-extensions,
      so it is disabled by default on the main Ractors.
      `RUBY_MN_THREADS=1` environment variable will enable it.
      On non-main Ractors, M:N thread scheduler is enabled (and can not
      disable it now).
    * `N` (the number of native threads) can be specified with `RUBY_MAX_CPU`
      environment variable. The default is 8.
      Note that more than `N` native threads are used to support many kind of
      blocking operations.

[Bug #595]:       https://bugs.ruby-lang.org/issues/595
[Feature #10602]: https://bugs.ruby-lang.org/issues/10602
[Bug #17146]:     https://bugs.ruby-lang.org/issues/17146
[Feature #18183]: https://bugs.ruby-lang.org/issues/18183
[Feature #18285]: https://bugs.ruby-lang.org/issues/18285
[Feature #18498]: https://bugs.ruby-lang.org/issues/18498
[Feature #18515]: https://bugs.ruby-lang.org/issues/18515
[Feature #18551]: https://bugs.ruby-lang.org/issues/18551
[Feature #18885]: https://bugs.ruby-lang.org/issues/18885
[Feature #18949]: https://bugs.ruby-lang.org/issues/18949
[Feature #18980]: https://bugs.ruby-lang.org/issues/18980
[Bug #19012]:     https://bugs.ruby-lang.org/issues/19012
[Feature #19057]: https://bugs.ruby-lang.org/issues/19057
[Bug #19150]:     https://bugs.ruby-lang.org/issues/19150
[Bug #19293]:     https://bugs.ruby-lang.org/issues/19293
[Feature #19314]: https://bugs.ruby-lang.org/issues/19314
[Feature #19347]: https://bugs.ruby-lang.org/issues/19347
[Feature #19351]: https://bugs.ruby-lang.org/issues/19351
[Feature #19362]: https://bugs.ruby-lang.org/issues/19362
[Feature #19370]: https://bugs.ruby-lang.org/issues/19370
[Feature #19521]: https://bugs.ruby-lang.org/issues/19521
[Feature #19538]: https://bugs.ruby-lang.org/issues/19538
[Feature #19561]: https://bugs.ruby-lang.org/issues/19561
[Feature #19571]: https://bugs.ruby-lang.org/issues/19571
[Feature #19572]: https://bugs.ruby-lang.org/issues/19572
[Feature #19591]: https://bugs.ruby-lang.org/issues/19591
[Feature #19630]: https://bugs.ruby-lang.org/issues/19630
[Feature #19637]: https://bugs.ruby-lang.org/issues/19637
[Feature #19678]: https://bugs.ruby-lang.org/issues/19678
[Feature #19714]: https://bugs.ruby-lang.org/issues/19714
[Feature #19725]: https://bugs.ruby-lang.org/issues/19725
[Feature #19757]: https://bugs.ruby-lang.org/issues/19757
[Feature #19776]: https://bugs.ruby-lang.org/issues/19776
[Feature #19777]: https://bugs.ruby-lang.org/issues/19777
[Feature #19785]: https://bugs.ruby-lang.org/issues/19785
[Feature #19790]: https://bugs.ruby-lang.org/issues/19790
[Feature #19839]: https://bugs.ruby-lang.org/issues/19839
[Feature #19842]: https://bugs.ruby-lang.org/issues/19842
[Feature #19843]: https://bugs.ruby-lang.org/issues/19843
[Bug #19868]:     https://bugs.ruby-lang.org/issues/19868
[Feature #19965]: https://bugs.ruby-lang.org/issues/19965
[Feature #20005]: https://bugs.ruby-lang.org/issues/20005
[Feature #20057]: https://bugs.ruby-lang.org/issues/20057
