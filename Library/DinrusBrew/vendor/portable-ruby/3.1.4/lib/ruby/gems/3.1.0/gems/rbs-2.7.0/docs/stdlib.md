# Testing Core API and Standard Library Types

This is a guide for testing core/stdlib types.

## Add Tests

We support writing tests for core/stdlib signatures.

### Writing tests

First, execute `generate:stdlib_test` rake task with a class name that you want to test.

```bash
$ bundle exec rake 'generate:stdlib_test[String]'
Created: test/stdlib/String_test.rb
```

It generates `test/stdlib/[class_name]_test.rb`.
The test scripts would look like the following:

```rb
class StringSingletonTest < Test::Unit::TestCase
  include TypeAssertions

  testing "singleton(::String)"

  def test_initialize
    assert_send_type "() -> String",
                     String, :new
    assert_send_type "(String) -> String",
                     String, :new, ""
    assert_send_type "(String, encoding: Encoding) -> String",
                     String, :new, "", encoding: Encoding::ASCII_8BIT
    assert_send_type "(String, encoding: Encoding, capacity: Integer) -> String",
                     String, :new, "", encoding: Encoding::ASCII_8BIT, capacity: 123
    assert_send_type "(encoding: Encoding, capacity: Integer) -> String",
                     String, :new, encoding: Encoding::ASCII_8BIT, capacity: 123
    assert_send_type "(ToStr) -> String",
                     String, :new, ToStr.new("")
    assert_send_type "(encoding: ToStr) -> String",
                     String, :new, encoding: ToStr.new('Shift_JIS')
    assert_send_type "(capacity: ToInt) -> String",
                     String, :new, capacity: ToInt.new(123)
  end
end

class StringTest < Test::Unit::TestCase
  include TypeAssertions

  # library "pathname", "set", "securerandom"     # Declare library signatures to load
  testing "::String"

  def test_gsub
    assert_send_type "(Regexp, String) -> String",
                     "string", :gsub, /./, ""
    assert_send_type "(String, String) -> String",
                     "string", :gsub, "a", "b"
    assert_send_type "(Regexp) { (String) -> String } -> String",
                     "string", :gsub, /./ do |x| "" end
    assert_send_type "(Regexp) { (String) -> ToS } -> String",
                     "string", :gsub, /./ do |x| ToS.new("") end
    assert_send_type "(Regexp, Hash[String, String]) -> String",
                     "string", :gsub, /./, {"foo" => "bar"}
    assert_send_type "(Regexp) -> Enumerator[String, self]",
                     "string", :gsub, /./
    assert_send_type "(String) -> Enumerator[String, self]",
                     "string", :gsub, ""
    assert_send_type "(ToStr, ToStr) -> String",
                     "string", :gsub, ToStr.new("a"), ToStr.new("b")
  end
end
```

You need include `TypeAssertions` which provide useful methods for you.
`testing` method call tells which class is the subject of the class.
`assert_send_type` method call asserts to be valid types and confirms to be able to execute without exceptions.
And you write the sample programs which calls all of the patterns of overloads.

Note that the instrumentation is based on refinements and you need to write all method calls in the unit class definitions.
If the execution of the program escape from the class definition, the instrumentation is disabled and no check will be done.

### Running tests

You can run the test with:

```
$ bundle exec rake stdlib_test                # Run all tests
$ bundle exec ruby test/stdlib/String_test.rb # Run specific tests
```
