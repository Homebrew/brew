# Writing Signatures Guide

You can write the signature of your applications and libraries.
Signature of your Ruby program would help:

1. Understanding the code structure
2. Finding APIs

And if you ship your gem with signature, the gem users can type check their applications!

## Writing signatures

You first need to write your program's signature.
See [syntax guide](syntax.md).

## Testing signatures

When you finish writing signature, you may want to test the signature.
rbs provides a feature to test your signature.

```
$ RBS_TEST_TARGET='Foo::*' bundle exec ruby -r rbs/test/setup test/foo_test.rb
```

The test installs instrumentations to spy the method calls and check if arguments/return values are correct with respect to the type of the method in signature.
If errors are reported by the test, you will fix the signature.
You will be sure that you ship a correct signature finally.

The instrumentations are implemented using `Module#prepend`.
It defines a module with same name of methods, which asserts the type of arguments/return values and calls `super`.

## Type errors

If the test detects type errors, it will print error messages.

### ArgumentTypeError, BlockArgumentTypeError

The message means there is an unexpected type of argument or block argument.

```
ERROR -- : [Kaigi::Speaker.new] ArgumentTypeError: expected `::String` (email) but given `:"matsumoto@soutaro.com"`
```

### ArgumentError, BlockArgumentError

The message means there is an unexpected argument or missing argument.

```
[Kaigi::Speaker.new] ArgumentError: expected method type (size: ::Symbol, email: ::String, name: ::String) -> ::Kaigi::Speaker
```

### ReturnTypeError, BlockReturnTypeError

The message means the return value from method or block is incorrect.

```
ERROR -- : [Kaigi::Conference#each_speaker] ReturnTypeError: expected `self` but returns `[#<Kaigi::Speaker:0x00007fb2b249e5a0 @name="Soutaro Matsumoto", @email=:"matsumoto@soutaro.com">]`
```

### UnexpectedBlockError, MissingBlockError

The errors are reported when required block is not given or unused block is given.

```
ERROR -- : [Kaigi::Conference#speakers] UnexpectedBlockError: unexpected block is given for `() -> ::Array[::Kaigi::Speaker]`
```

### UnresolvedOverloadingError

The error means there is a type error on overloaded methods.
The `rbs` test framework tries to the best error message for overloaded methods too, but it reports the `UnresolvedOverloadingError` when it fails.

### DuplicatedMethodDefinitionError

The error is reported when a method is defined multiple times, as RBS does not allow duplicate method definitions. When you need to overload a method, use the `...` syntax:

```ruby
# First definition
class C
  def foo: () -> untyped
end

# Second definition, use `...` syntax to tell RBS that we're overloading the method
class C
  def foo: () -> untyped
         | ...
end
```

## Setting up the test

The design of the signature testing aims to be non-intrusive. The setup is done in two steps:

1. Loading the testing library
2. Setting up the test through environment variables

### Loading the library

You need to require `rbs/test/setup` for signature testing.
You can do it using `-r` option through command line argument or the `RUBYOPT` environment variable.

```
$ ruby -r rbs/test/setup run_tests.rb
$ RUBYOPT='-rrbs/test/setup' rake test
```

When you are using Bundler, you may need to require `bundler/setup` explicitly.

```
$ RUBYOPT='-rbundler/setup -rrbs/test/setup' bundle exec rake test
```

### Environment variables

You need to specify `RBS_TEST_TARGET` to run the test, and you can customize the test with the following environment variables.

- `RBS_TEST_SKIP` (optional)
- `RBS_TEST_OPT` (optional)
- `RBS_TEST_LOGLEVEL` (optional)
- `RBS_TEST_RAISE` (optional)

`RBS_TEST_TARGET` is to specify the classes you want to test. `RBS_TEST_TARGET` can contain comma-separated class name pattern, which is one of an exact class name or with wildcard `*`.

- `RBS_TEST_TARGET=Foo::Bar,Foo::Baz` comma separated exact class names
- `RBS_TEST_TARGET=Foo::*` using wildcard

`RBS_TEST_SKIP` is to skip some of the classes which matches with `RBS_TEST_TARGET`.

`RBS_TEST_OPT` is to pass the options for rbs handling.
You may need to specify `-r` or `-I` to load signatures.
The default is `-I sig`.

```
RBS_TEST_OPT='-r pathname -I sig'
```

Replacing `pathname` with the `stdlib` you want to include. For example, if you need to load `Set` and `BigDecimal` in `stdlib`, you would need to have `RBS_TEST_OPT='-r set -r bigdecimal -I sig'`

`RBS_TEST_LOGLEVEL` can be used to configure log level. Defaults to `info`.

`RBS_TEST_RAISE` may help to debug the type signatures.
If the environment variable is set, it raises an exception when a type error is detected.
You can see the backtrace how the type error is caused and debug your program or signature.

So, a typical command line to start the test would look like the following:

```
$ RBS_TEST_LOGLEVEL=error \
  RBS_TEST_TARGET='Kaigi::*' \
  RBS_TEST_SKIP='Kaigi::MonkeyPatch' \
  RBS_TEST_OPT='-rset -rpathname -Isig -Iprivate' \
  RBS_TEST_RAISE=true \
  RUBYOPT='-rbundler/setup -rrbs/test/setup' \
  bundle exec rake test
```

## Testing tips

### Skipping a method

You can skip installing the instrumentation per-method basis using `rbs:test:skip` annotation.

```
class String
  %a{rbs:test:skip} def =~: (Regexp) -> Integer?
end
```
