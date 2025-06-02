# power_assert
## About
Power Assert shows each value of variables and method calls in the expression.
It is useful for testing, providing which value wasn't correct when the condition is not satisfied.

    Failure:
       assert { 3.times.to_a.include?(3) }
                  |     |    |
                  |     |    false
                  |     [0, 1, 2]
                  #<Enumerator: 3:times>

## Related Projects
In general, you don't need to use this library directly.
Use following test frameworks or extensions instead.

* [test-unit](https://github.com/test-unit/test-unit)(>= 3.0.0)
  * [Document](http://test-unit.github.io/test-unit/en/Test/Unit/Assertions.html#assert-instance_method)
* [minitest-power_assert](https://github.com/hsbt/minitest-power_assert)
* [rspec-power_assert](https://github.com/joker1007/rspec-power_assert)
* [rspec-matchers-power_assert_matchers](https://github.com/kachick/rspec-matchers-power_assert_matchers)
* [pry-power_assert](https://github.com/yui-knk/pry-power_assert)
* [pry-byebug-power_assert](https://github.com/k-tsj/pry-byebug-power_assert)
* [irb-power_assert](https://github.com/kachick/irb-power_assert)
* [power_p](https://github.com/k-tsj/power_p)

## Requirement
* CRuby 2.5+

## Configuration
To colorize output messages, add <code>require "power_assert/colorize"</code> to your code.
(It requires CRuby 3.0.1+ or irb 1.3.1+)

## Known Limitations
* Expressions must be put in one line. Expressions with folded long lines produce nothing report, e.g.:

```ruby
assert do
  # reported
  func(foo: 0123456789, bar: "abcdefg")
end

assert do
  # won't be reported
  func(foo: 0123456789,
       bar: "abcdefg")
end
```

* Expressions must have one or more method call. Expressions with no method call produce nothing report, e.g.:

```ruby
val = false
assert do
  # reported
  val == true
end

assert do
  # won't be reported
  val
end
```

* Returned values from accessor methods, method missing, or "super" produce nothing report, e.g:

```ruby
class Foo
  attr_accessor :val
end
foo = Foo.new
foo.val = false

assert do
  # reported (only the value of "foo" and the literal "true")
  foo.val == true
end

assert do
  # won't be reported
  foo.val
end
```

* Expressions should not have conditional branches. Expressions with such conditional codes may produce nothing report, e.g.:

```ruby
condition = true
expected = false
actual = true
assert do
  # this will fail but nothing reported
  condition ? expected == actual : expected == actual
end
```

## Reference
* [Power Assert in Ruby (at RubyKaigi 2014) // Speaker Deck](https://speakerdeck.com/k_tsj/power-assert-in-ruby)
