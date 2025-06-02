# NEWS for Ruby 3.1.0

This document is a list of user-visible feature changes
since the **3.0.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

*   The block argument can now be anonymous if the block will
    only be passed to another method. [[Feature #11256]]

    ```ruby
    def foo(&)
      bar(&)
    end
    ```

*   Pin operator now takes an expression. [[Feature #17411]]

    ```ruby
    Prime.each_cons(2).lazy.find_all{_1 in [n, ^(n + 2)]}.take(3).to_a
    #=> [[3, 5], [5, 7], [11, 13]]
    ```

*   Pin operator now supports instance, class, and global variables.
    [[Feature #17724]]

    ```ruby
    @n = 5
    Prime.each_cons(2).lazy.find{_1 in [n, ^@n]}
    #=> [3, 5]
    ```

*   One-line pattern matching is no longer experimental.

*   Parentheses can be omitted in one-line pattern matching.
    [[Feature #16182]]

    ```ruby
    [0, 1] => _, x
    {y: 2} => y:
    x #=> 1
    y #=> 2
    ```

*   Multiple assignment evaluation order has been made consistent with
    single assignment evaluation order.  With single assignment, Ruby
    uses a left-to-right evaluation order.  With this code:

    ```ruby
    foo[0] = bar
    ```

    The following evaluation order is used:

    1. `foo`
    2. `bar`
    3. `[]=` called on the result of `foo`

    In Ruby before 3.1.0, multiple assignment did not follow this
    evaluation order.  With this code:

    ```ruby
    foo[0], bar.baz = a, b
    ```

    Versions of Ruby before 3.1.0 would evaluate in the following
    order

    1. `a`
    2. `b`
    3. `foo`
    4. `[]=` called on the result of `foo`
    5. `bar`
    6. `baz=` called on the result of `bar`

    Starting in Ruby 3.1.0, the evaluation order is now consistent with
    single assignment, with the left-hand side being evaluated before
    the right-hand side:

    1. `foo`
    2. `bar`
    3. `a`
    4. `b`
    5. `[]=` called on the result of `foo`
    6. `baz=` called on the result of `bar`

    [[Bug #4443]]

*   Values in Hash literals and keyword arguments can be omitted.
    [[Feature #14579]]

    For example,

    * `{x:, y:}` is a syntax sugar of `{x: x, y: y}`.
    * `foo(x:, y:)` is a syntax sugar of `foo(x: x, y: y)`.

    Constant names, local variable names, and method names are allowed as
    key names.  Note that a reserved word is considered as a local
    variable or method name even if it's a pseudo variable name such as
    `self`.

*   Non main-Ractors can get instance variables (ivars) of classes/modules
    if ivars refer to shareable objects.
    [[Feature #17592]]

*   A command syntax is allowed in endless method definitions, i.e.,
    you can now write `def foo = puts "Hello"`.
    Note that `private def foo = puts "Hello"` does not parse.
    [[Feature #17398]]

## Command line options

* `--disable-gems` is now explicitly declared as "just for debugging".
  Never use it in any real-world codebase.
  [[Feature #17684]]

## Core classes updates

Note: We're only listing outstanding class updates.

* Array

    * Array#intersect? is added. [[Feature #15198]]

* Class

    *   Class#subclasses, which returns an array of classes
        directly inheriting from the receiver, not
        including singleton classes.
        [[Feature #18273]]

        ```ruby
        class A; end
        class B < A; end
        class C < B; end
        class D < A; end
        A.subclasses    #=> [D, B]
        B.subclasses    #=> [C]
        C.subclasses    #=> []
        ```

* Enumerable

    *   Enumerable#compact is added. [[Feature #17312]]

    *   Enumerable#tally now accepts an optional hash to count. [[Feature #17744]]

    *   Enumerable#each_cons and each_slice to return a receiver. [[GH-1509]]

        ```ruby
        [1, 2, 3].each_cons(2){}
        # 3.0 => nil
        # 3.1 => [1, 2, 3]

        [1, 2, 3].each_slice(2){}
        # 3.0 => nil
        # 3.1 => [1, 2, 3]
        ```

* Enumerator::Lazy

    *   Enumerator::Lazy#compact is added. [[Feature #17312]]

* File

    *   File.dirname now accepts an optional argument for the level to
        strip path components. [[Feature #12194]]

* GC

    *   "GC.measure_total_time = true" enables the measurement of GC.
        Measurement can introduce overhead. It is enabled by default.
        GC.measure_total_time returns the current setting.
        GC.stat[:time] or GC.stat(:time) returns measured time
        in milli-seconds. [[[Feature #10917]]]

    *   GC.total_time returns measured time in nano-seconds. [[[Feature #10917]]]

* Integer

    *   Integer.try_convert is added. [[Feature #15211]]

* Kernel


    *   Kernel#load now accepts a module as the second argument,
        and will load the file using the given module as the
        top-level module. [[Feature #6210]]

* Marshal

    *   Marshal.load now accepts a `freeze: true` option.
        All returned objects are frozen except for `Class` and
        `Module` instances. Strings are deduplicated. [[Feature #18148]]

* MatchData

    *   MatchData#match is added [[Feature #18172]]

    *   MatchData#match_length is added [[Feature #18172]]

* Method / UnboundMethod

    *   Method#public?, Method#private?, Method#protected?,
        UnboundMethod#public?, UnboundMethod#private?,
        UnboundMethod#protected? have been added. [[Feature #11689]]

* Module

    *   Module#prepend now modifies the ancestor chain if the receiver
        already includes the argument. Module#prepend still does not
        modify the ancestor chain if the receiver has already prepended
        the argument. [[Bug #17423]]

    *   Module#private, #public, #protected, and #module_function will
        now return their arguments.  If a single argument is given, it
        is returned. If no arguments are given, nil is returned.  If
        multiple arguments are given, they are returned as an array.
        [[Feature #12495]]

* Process

    *   Process.\_fork is added. This is a core method for fork(2).
        Do not call this method directly; it is called by existing
        fork methods: Kernel.#fork, Process.fork, and IO.popen("-").
        Application monitoring libraries can overwrite this method to
        hook fork events. [[Feature #17795]]

* Struct

    *   Passing only keyword arguments to Struct#initialize is warned.
        You need to use a Hash literal to set a Hash to a first member.
        [[Feature #16806]]

    *   StructClass#keyword_init? is added [[Feature #18008]]

* String

    *   Update Unicode version to 13.0.0 [[Feature #17750]]
        and Emoji version to 13.0 [[Feature #18029]]

    *   String#unpack and String#unpack1 now accept an `offset:` keyword
        argument to start the unpacking after an arbitrary number of bytes
        have been skipped. If `offset` is outside of the string bounds
        `ArgumentError` is raised. [[Feature #18254]]

* Thread

    *   Thread#native_thread_id is added. [[Feature #17853]]

* Thread::Backtrace

    *   Thread::Backtrace.limit, which returns the value to limit backtrace
        length set by `--backtrace-limit` command line option, is added.
        [[Feature #17479]]

* Thread::Queue

    *   Thread::Queue.new now accepts an Enumerable of initial values.
        [[Feature #17327]]

* Time

    *   Time.new now accepts optional `in:` keyword argument for the
        timezone, as well as `Time.at` and `Time.now`, so that is now
        you can omit minor arguments to `Time.new`. [[Feature #17485]]

        ```ruby
        Time.new(2021, 12, 25, in: "+07:00")
        #=> 2021-12-25 00:00:00 +0700
        ```

        At the same time, time component strings are converted to
        integers more strictly now.

        ```ruby
        Time.new(2021, 12, 25, "+07:30")
        #=> invalid value for Integer(): "+07:30" (ArgumentError)
        ```

        Ruby 3.0 or earlier returned probably unexpected result
        `2021-12-25 07:00:00`, not `2021-12-25 07:30:00` nor
        `2021-12-25 00:00:00 +07:30`.

    *   Time#strftime supports RFC 3339 UTC for unknown offset local
        time, `-0000`, as `%-z`. [[Feature #17544]]

* TracePoint

    *   TracePoint.allow_reentry is added to allow reenter while TracePoint
        callback.
        [[Feature #15912]]

* $LOAD_PATH

    *   $LOAD_PATH.resolve_feature_path does not raise. [[Feature #16043]]

* Fiber Scheduler

    *   Add support for `Addrinfo.getaddrinfo` using `address_resolve` hook.
        [[Feature #17370]]

    *   Introduce non-blocking `Timeout.timeout` using `timeout_after` hook.
        [[Feature #17470]]

    *   Introduce new scheduler hooks `io_read` and `io_write` along with a
        low level `IO::Buffer` for zero-copy read/write. [[Feature #18020]]

    *   IO hooks `io_wait`, `io_read`, `io_write`, receive the original IO object
        where possible. [[Bug #18003]]

    *   Make `Monitor` fiber-safe. [[Bug #17827]]

    *   Replace copy coroutine with pthread implementation. [[Feature #18015]]

* Refinement

    *   New class which represents a module created by Module#refine.
        `include` and `prepend` are deprecated, and `import_methods` is added
        instead. [[Bug #17429]]

## Stdlib updates

*   The following default gem are updated.
    * RubyGems 3.3.3
    * base64 0.1.1
    * benchmark 0.2.0
    * bigdecimal 3.1.1
    * bundler 2.3.3
    * cgi 0.3.1
    * csv 3.2.2
    * date 3.2.2
    * did_you_mean 1.6.1
    * digest 3.1.0
    * drb 2.1.0
    * erb 2.2.3
    * error_highlight 0.3.0
    * etc 1.3.0
    * fcntl 1.0.1
    * fiddle 1.1.0
    * fileutils 1.6.0
    * find 0.1.1
    * io-console 0.5.10
    * io-wait 0.2.1
    * ipaddr 1.2.3
    * irb 1.4.1
    * json 2.6.1
    * logger 1.5.0
    * net-http 0.2.0
    * net-protocol 0.1.2
    * nkf 0.1.1
    * open-uri 0.2.0
    * openssl 3.0.0
    * optparse 0.2.0
    * ostruct 0.5.2
    * pathname 0.2.0
    * pp 0.3.0
    * prettyprint 0.1.1
    * psych 4.0.3
    * racc 1.6.0
    * rdoc 6.4.0
    * readline 0.0.3
    * readline-ext 0.1.4
    * reline 0.3.0
    * resolv 0.2.1
    * rinda 0.1.1
    * ruby2_keywords 0.0.5
    * securerandom 0.1.1
    * set 1.0.2
    * stringio 3.0.1
    * strscan 3.0.1
    * tempfile 0.1.2
    * time 0.2.0
    * timeout 0.2.0
    * tmpdir 0.1.2
    * un 0.2.0
    * uri 0.11.0
    * yaml 0.2.0
    * zlib 2.1.1
*   The following bundled gems are updated.
    * minitest 5.15.0
    * power_assert 2.0.1
    * rake 13.0.6
    * test-unit 3.5.3
    * rexml 3.2.5
    * rbs 2.1.0
    * typeprof 0.21.2
*   The following default gems are now bundled gems.
    * net-ftp 0.1.3
    * net-imap 0.2.3
    * net-pop 0.1.1
    * net-smtp 0.3.1
    * matrix 0.4.2
    * prime 0.1.2
    * debug 1.4.0

* Coverage measurement now supports suspension. You can use `Coverage.suspend`
  to stop the measurement temporarily, and `Coverage.resume` to restart it.
  See [[Feature #18176]] in detail.

* Random::Formatter is moved to random/formatter.rb, so that you can
  use `Random#hex`, `Random#base64`, and so on without SecureRandom.
  [[Feature #18190]]

## Compatibility issues

Note: Excluding feature bug fixes.

* `rb_io_wait_readable`, `rb_io_wait_writable` and `rb_wait_for_single_fd` are
  deprecated in favour of `rb_io_maybe_wait_readable`,
  `rb_io_maybe_wait_writable` and `rb_io_maybe_wait` respectively.
  `rb_thread_wait_fd` and `rb_thread_fd_writable` are deprecated. [[Bug #18003]]

## Stdlib compatibility issues

* `ERB#initialize` warns `safe_level` and later arguments even without -w.
  [[Feature #14256]]

* `lib/debug.rb` is replaced with `debug.gem`

* `Kernel#pp` in `lib/pp.rb` uses the width of `IO#winsize` by default.
  This means that the output width is automatically changed depending on
  your terminal size. [[Feature #12913]]

* Psych 4.0 changes `Psych.load` as `safe_load` by the default.
  You may need to use Psych 3.3.2 for migrating to this behavior.
  [[Bug #17866]]

## C API updates

* Documented. [[GH-4815]]

* `rb_gc_force_recycle` is deprecated and has been changed to a no-op.
  [[Feature #18290]]

## Implementation improvements

* Inline cache mechanism is introduced for reading class variables.
  [[Feature #17763]]

* `instance_eval` and `instance_exec` now only allocate a singleton class when
  required, avoiding extra objects and improving performance. [[GH-5146]]

* The performance of `Struct` accessors is improved. [[GH-5131]]

* `mandatory_only?` builtin special form to improve performance on
  builtin methods. [[GH-5112]]

* Experimental feature Variable Width Allocation in the garbage collector.
  This feature is turned off by default and can be enabled by compiling Ruby
  with flag `USE_RVARGC=1` set. [[Feature #18045]] [[Feature #18239]]

## JIT

* Rename Ruby 3.0's `--jit` to `--mjit`, and alias `--jit` to `--yjit`
  on non-Windows x86-64 platforms and to `--mjit` on others.

### MJIT

* The default `--mjit-max-cache` is changed from 100 to 10000.

* JIT-ed code is no longer cancelled when a TracePoint for class events
  is enabled.

* The JIT compiler no longer skips compilation of methods longer than
  1000 instructions.

* `--mjit-verbose` and `--mjit-warning` output "JIT cancel" when JIT-ed
  code is disabled because TracePoint or GC.compact is used.

### YJIT: New experimental in-process JIT compiler

New JIT compiler available as an experimental feature. [[Feature #18229]]

See [this blog post](https://shopify.engineering/yjit-just-in-time-compiler-cruby
) introducing the project.

* Disabled by default, use `--yjit` command-line option to enable YJIT.

* Performance improvements on benchmarks based on real-world software,
  up to 22% on railsbench, 39% on liquid-render.

* Fast warm-up times.

* Limited to Unix-like x86-64 platforms for now.

## Static analysis

### RBS

*   Generics type parameters can be bounded ([PR](https://github.com/ruby/rbs/pull/844)).

    ```rbs
    # `T` must be compatible with the `_Output` interface.
    # `PrettyPrint[String]` is ok, but `PrettyPrint[Integer]` is a type error.
    class PrettyPrint[T < _Output]
      interface _Output
        def <<: (String) -> void
      end

      attr_reader output: T

      def initialize: (T output) -> void
    end
    ```

*   Type aliases can be generic. ([PR](https://github.com/ruby/rbs/pull/823))

    ```rbs
    # Defines a generic type `list`.
    type list[T] = [ T, list[T] ]
                 | nil

    type str_list = list[String]
    type int_list = list[Integer]
    ```

* [rbs collection](https://github.com/ruby/rbs/blob/master/docs/collection.md) has been introduced to manage gems’ RBSs.

* Many signatures for built-in and standard libraries have been added/updated.

* It includes many bug fixes and performance improvements too.

See the [CHANGELOG.md](https://github.com/ruby/rbs/blob/master/CHANGELOG.md) for more information.

### TypeProf

* [Experimental IDE support](https://github.com/ruby/typeprof/blob/master/doc/ide.md) has been implemented.
* Many bug fixes and performance improvements since Ruby 3.0.0.

## Debugger

* A new debugger [debug.gem](https://github.com/ruby/debug) is bundled.
  debug.gem is a fast debugger implementation, and it provides many features
  like remote debugging, colorful REPL, IDE (VSCode) integration, and more.
  It replaces `lib/debug.rb` standard library.

* `rdbg` command is also installed into `bin/` directory to start and control
  debugging execution.

## error_highlight

A built-in gem called error_highlight has been introduced.
It shows fine-grained error locations in the backtrace.

Example: `title = json[:article][:title]`

If `json` is nil, it shows:

```
$ ruby test.rb
test.rb:2:in `<main>': undefined method `[]' for nil:NilClass (NoMethodError)

title = json[:article][:title]
            ^^^^^^^^^^
```

If `json[:article]` returns nil, it shows:

```
$ ruby test.rb
test.rb:2:in `<main>': undefined method `[]' for nil:NilClass (NoMethodError)

title = json[:article][:title]
                      ^^^^^^^^
```

This feature is enabled by default.
You can disable it by using a command-line option `--disable-error_highlight`.
See [the repository](https://github.com/ruby/error_highlight) in detail.

## IRB Autocomplete and Document Display

The IRB now has an autocomplete feature, where you can just type in the code, and the completion candidates dialog will appear. You can use Tab and Shift+Tab to move up and down.

If documents are installed when you select a completion candidate, the documentation dialog will appear next to the completion candidates dialog, showing part of the content. You can read the full document by pressing Alt+d.

## Miscellaneous changes

* lib/objspace/trace.rb is added, which is a tool for tracing the object
  allocation. Just by requiring this file, tracing is started *immediately*.
  Just by `Kernel#p`, you can investigate where an object was created.
  Note that just requiring this file brings a large performance overhead.
  This is only for debugging purposes. Do not use this in production.
  [[Feature #17762]]

* Now exceptions raised in finalizers will be printed to `STDERR`, unless
  `$VERBOSE` is `nil`.  [[Feature #17798]]

* `ruby -run -e httpd` displays URLs to access.  [[Feature #17847]]

* Add `ruby -run -e colorize` to colorize Ruby code using
  `IRB::Color.colorize_code`.

[Bug #4443]:      https://bugs.ruby-lang.org/issues/4443
[Feature #6210]:  https://bugs.ruby-lang.org/issues/6210
[Feature #10917]: https://bugs.ruby-lang.org/issues/10917
[Feature #11256]: https://bugs.ruby-lang.org/issues/11256
[Feature #11689]: https://bugs.ruby-lang.org/issues/11689
[Feature #12194]: https://bugs.ruby-lang.org/issues/12194
[Feature #12495]: https://bugs.ruby-lang.org/issues/12495
[Feature #12913]: https://bugs.ruby-lang.org/issues/12913
[Feature #14256]: https://bugs.ruby-lang.org/issues/14256
[Feature #14579]: https://bugs.ruby-lang.org/issues/14579
[Feature #15198]: https://bugs.ruby-lang.org/issues/15198
[Feature #15211]: https://bugs.ruby-lang.org/issues/15211
[Feature #15912]: https://bugs.ruby-lang.org/issues/15912
[Feature #16043]: https://bugs.ruby-lang.org/issues/16043
[Feature #16182]: https://bugs.ruby-lang.org/issues/16182
[Feature #16806]: https://bugs.ruby-lang.org/issues/16806
[Feature #17312]: https://bugs.ruby-lang.org/issues/17312
[Feature #17327]: https://bugs.ruby-lang.org/issues/17327
[Feature #17370]: https://bugs.ruby-lang.org/issues/17370
[Feature #17398]: https://bugs.ruby-lang.org/issues/17398
[Feature #17411]: https://bugs.ruby-lang.org/issues/17411
[Bug #17423]:     https://bugs.ruby-lang.org/issues/17423
[Bug #17429]:     https://bugs.ruby-lang.org/issues/17429
[Feature #17470]: https://bugs.ruby-lang.org/issues/17470
[Feature #17479]: https://bugs.ruby-lang.org/issues/17479
[Feature #17485]: https://bugs.ruby-lang.org/issues/17485
[Feature #17544]: https://bugs.ruby-lang.org/issues/17544
[Feature #17592]: https://bugs.ruby-lang.org/issues/17592
[Feature #17684]: https://bugs.ruby-lang.org/issues/17684
[Feature #17724]: https://bugs.ruby-lang.org/issues/17724
[Feature #17744]: https://bugs.ruby-lang.org/issues/17744
[Feature #17750]: https://bugs.ruby-lang.org/issues/17750
[Feature #17762]: https://bugs.ruby-lang.org/issues/17762
[Feature #17763]: https://bugs.ruby-lang.org/issues/17763
[Feature #17795]: https://bugs.ruby-lang.org/issues/17795
[Feature #17798]: https://bugs.ruby-lang.org/issues/17798
[Bug #17827]:     https://bugs.ruby-lang.org/issues/17827
[Feature #17847]: https://bugs.ruby-lang.org/issues/17847
[Feature #17853]: https://bugs.ruby-lang.org/issues/17853
[Bug #17866]:     https://bugs.ruby-lang.org/issues/17866
[Bug #18003]:     https://bugs.ruby-lang.org/issues/18003
[Feature #18008]: https://bugs.ruby-lang.org/issues/18008
[Feature #18015]: https://bugs.ruby-lang.org/issues/18015
[Feature #18020]: https://bugs.ruby-lang.org/issues/18020
[Feature #18029]: https://bugs.ruby-lang.org/issues/18029
[Feature #18045]: https://bugs.ruby-lang.org/issues/18045
[Feature #18148]: https://bugs.ruby-lang.org/issues/18148
[Feature #18172]: https://bugs.ruby-lang.org/issues/18172
[Feature #18176]: https://bugs.ruby-lang.org/issues/18176
[Feature #18190]: https://bugs.ruby-lang.org/issues/18190
[Feature #18229]: https://bugs.ruby-lang.org/issues/18229
[Feature #18239]: https://bugs.ruby-lang.org/issues/18239
[Feature #18254]: https://bugs.ruby-lang.org/issues/18254
[Feature #18273]: https://bugs.ruby-lang.org/issues/18273
[Feature #18290]: https://bugs.ruby-lang.org/issues/18290

[GH-1509]: https://github.com/ruby/ruby/pull/1509
[GH-4815]: https://github.com/ruby/ruby/pull/4815
[GH-5112]: https://github.com/ruby/ruby/pull/5112
[GH-5131]: https://github.com/ruby/ruby/pull/5131
[GH-5146]: https://github.com/ruby/ruby/pull/5146
