# RBS By Example

## Goal

The purpose of this doc is to teach you how to write RBS signatures by using the standard library's methods as a guide.

## Examples

### Zero argument methods

**Example:** `String#empty?`

```ruby
# .rb
"".empty?
# => true
"hello".empty?
# => false
```

```ruby
# .rbs
class String
  def empty?: () -> bool
end
```

`String`'s `#empty` method takes no parameters, and returns a boolean value

### Single argument methods

**Example:** `String#include?`

```ruby
# .rb
"homeowner".include?("house")
# => false
"homeowner".include?("meow")
# => true
```

```ruby
class String
  def include?: (String) -> bool
end
```

`String`'s `include?` method takes one argument, a `String`, and returns a
boolean value

### Variable argument methods

**Example:** `String#end_with?`

```ruby
# .rb
"hello?".end_with?("!")
# => false
"hello?".end_with?("?")
# => true
"hello?".end_with?("?", "!")
# => true
"hello?".end_with?(".", "!")
# => false
```

```ruby
# .rbs
class String
  def end_with?: (*String) -> bool
end
```

`String`'s `#end_with?` method takes any number of `String` arguments, and
returns a boolean value.

### Optional positional arguments

**Example:** `String#ljust`

```ruby
# .rb
"hello".ljust(4)
#=> "hello"
"hello".ljust(20)
#=> "hello               "
"hello".ljust(20, '1234')
#=> "hello123412341234123"
```

```ruby
# .rbs
class String
  def ljust: (Integer, ?String) -> String
end
```

`String`'s `ljust` takes one `Integer` argument, and an optional `String` argument, indicated by the the `?` prefix marker. It returns a `String`.

### Multiple signatures for a single method

**Example:** `Array#*`

```ruby
# .rb
[1, 2, 3] * ","
# => "1,2,3"
[1, 2, 3] * 2
# => [1, 2, 3, 1, 2, 3]
```

*Note:* Some of the signatures after this point include type variables (e.g. `Elem`, `T`).
For now, it's safe to ignore them, but they're included for completeness.

```ruby
# .rbs
class Array[Elem]
  def *: (String) -> String
       | (Integer) -> Array[Elem]
end
```

`Array`'s `*` method, when given a `String` returns a `String`. When given an
`Integer`, it returns an `Array` of the same contained type `Elem` (in our example case, `Elem` corresponds to `Integer`).

### Union types

**Example:** `String#<<`

```ruby
# .rb
a = "hello "
a << "world"
#=> "hello world"
a << 33
#=> "hello world!"
```

```ruby
# .rbs
class String
  def <<: (String | Integer) -> String
end
```

`String`'s `<<` operator takes either a `String` or an `Integer`, and returns a `String`.

### Nilable types

```ruby
# .rb
[1, 2, 3].first
# => 1
[].first
# => nil
[1, 2, 3].first(2)
# => [1, 2]
[].first(2)
# => []
```

```ruby
# .rbs
class Enumerable[Elem]
  def first: () -> Elem?
           | (Integer) -> Array[Elem]
end
```

`Enumerable`'s `#first` method has two different signatures.

When called with no arguments, the return value will either be an instance of
whatever type is contained in the enumerable, or `nil`. We represent that with
the type variable `Elem`, and the `?` suffix nilable marker.

When called with an `Integer` positional argument, the return value will be an
`Array` of whatever type is contained.

The `?` syntax is a convenient shorthand for a union with nil. An equivalent union type woould be `(Elem | nil)`.

### Keyword Arguments

**Example**: `String#lines`

```ruby
# .rb
"hello\nworld\n".lines
# => ["hello\n", "world\n"]
"hello  world".lines(' ')
# => ["hello ", " ", "world"]
"hello\nworld\n".lines(chomp: true)
# => ["hello", "world"]
```

```ruby
# .rbs
class String
  def lines: (?String, ?chomp: bool) -> Array[String]
end
```

`String`'s `#lines` method take two arguments: one optional String argument, and another optional boolean keyword argument. It returns an `Array` of `String`s.

Keyword arguments are declared similar to in ruby, with the keyword immediately followed by a colon. Keyword arguments that are optional are indicated as optional using the same `?` prefix as positional arguments.


### Class methods

**Example**: `Time.now`

```ruby
# .rb
Time.now
# => 2009-06-24 12:39:54 +0900
```

```ruby
class Time
  def self.now: () -> Time
end
```

`Time`'s class method `now` takes no arguments, and returns an instance of the
`Time` class.

### Block Arguments

**Example**: `Array#filter`

```ruby
# .rb
[1,2,3,4,5].filter {|num| num.even? }
# => [2, 4]
%w[ a b c d e f ].filter {|v| v =~ /[aeiou]/ }
# => ["a", "e"]
[1,2,3,4,5].filter
```

```ruby
# .rbs
class Array[Elem]
  def filter: () { (Elem) -> boolish } -> ::Array[Elem]
            | () -> ::Enumerator[Elem, ::Array[Elem]]
end
```

`Array`'s `#filter` method, when called with no arguments returns an Enumerator.

When called with a block, the method returns an `Array` of whatever type the original contained. The block will take one argument, of the type of the contained value, and the block will return a truthy or falsy value.

`boolish` is a special keyword for any type that will be treated as if it were a `bool`.

### Type Variables

**Example**: `Hash`, `Hash#keys`

```ruby
h = { "a" => 100, "b" => 200, "c" => 300, "d" => 400 }
h.keys
# => ["a", "b", "c", "d"]
```

```ruby
# .rbs
class Hash[K, V]
  def keys: () -> Array[K]
end
```

Generic types in RBS are parameterized at declaration time. These type variables are then available throughout all the methods contained in the `class` block.

`Hash`'s `#keys` method takes no arguments, and returns an `Array` of the first type parameter. In the above example, `a` is of concrete type `Hash[String, Integer]`, so `#keys` returns an `Array` for `String`.


```ruby
# .rb
a = [ "a", "b", "c", "d" ]
a.collect {|x| x + "!"}
# => ["a!", "b!", "c!", "d!"]
a.collect.with_index {|x, i| x * i}
# => ["", "b", "cc", "ddd"]
```

```ruby
# .rbs
class Array[Elem]
  def collect: [U] () { (Elem) -> U } -> Array[U]
             | () -> Enumerator[Elem, Array[untyped]]
end
```

Type variables can also be introduced in methods. Here, in `Array`'s `#collect` method, we introduce a type variable `U`. The block passed to `#collect` will receive a parameter of type `Elem`, and return a value of type `U`. Then `#collect` will return an `Array` of type `U`.

In this example, the method receives its signature from the inferred return type of the passed block. When then block is absent, as in when the method returns an `Enumerator`, we can't infer the type, and so the return value of the enumerator can only be described as `Array[untyped]`.

### Tuples

**Examples**: `Enumerable#partition`, `Enumerable#to_h`

```ruby
(1..6).partition { |v| v.even? }
# => [[2, 4, 6], [1, 3, 5]]
```

```ruby
class Enumerable[Elem]
  def partition: () { (Elem) -> boolish } -> [Array[Elem], Array[Elem]]
               | () -> ::Enumerator[Elem, [Array[Elem], Array[Elem] ]]
end
```

`Enumerable`'s `partition` method, when given a block, returns a 2-item tuple of `Array`s containing the original type of the `Enumerable`.

Tuples can be of any size, and they can have mixed types.

```ruby
(1..5).to_h {|x| [x, x ** 2]}
# => {1=>1, 2=>4, 3=>9, 4=>16, 5=>25}
```

```ruby
class Enumerable[Elem]
  def to_h: () -> ::Hash[untyped, untyped]
          | [T, U] () { (Elem) -> [T, U] } -> ::Hash[T, U]
end
```

`Enumerable`'s `to_h` method, when given a block that returns a 2-item tuple, returns a `Hash` with keys the type of the first position in the tuple, and values the type of the second position in the tuple.
