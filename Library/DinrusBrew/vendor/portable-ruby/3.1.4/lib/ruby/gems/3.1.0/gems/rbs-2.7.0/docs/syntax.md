# Syntax

## Types

```markdown
_type_ ::= _class-name_ _type-arguments_                (Class instance type)
         | _interface-name_ _type-arguments_            (Interface type)
         | _alias-name_ _type-arguments_                (Alias type)
         | `singleton(` _class-name_ `)`                (Class singleton type)
         | _literal_                                    (Literal type)
         | _type_ `|` _type_                            (Union type)
         | _type_ `&` _type_                            (Intersection type)
         | _type_ `?`                                   (Optional type)
         | `{` _record-name_ `:` _type_ `,` etc. `}`    (Record type)
         | `[]` | `[` _type_ `,` etc. `]`               (Tuples)
         | _type-variable_                              (Type variables)
         | `^(` _parameters_ `) ->` _type_              (Proc type)
         | `self`
         | `instance`
         | `class`
         | `bool`
         | `untyped`
         | `nil`
         | `top`
         | `bot`
         | `void`

_class-name_ ::= _namespace_ /[A-Z]\w*/
_interface-name_ ::= _namespace_ /_[A-Z]\w*/
_alias-name_ ::= _namespace_ /[a-z]\w*/

_type-variable_ ::= /[A-Z]\w*/

_namespace_ ::=                                         (Empty namespace)
              | `::`                                    (Root)
              | _namespace_ /[A-Z]\w*/ `::`             (Namespace)

_type-arguments_ ::=                                    (No type arguments)
                   | `[` _type_ `,` etc. `]`            (Type arguments)

_literal_ ::= _string-literal_
            | _symbol-literal_
            | _integer-literal_
            | `true`
            | `false`
```

### Class instance type

Class instance type denotes _an instance of a class_.

```
Integer                      # Instance of Integer class
::Integer                    # Instance of ::Integer class
Hash[Symbol, String]         # Instance of Hash class with type application of Symbol and String
```

### Interface type

Interface type denotes _type of a value which can be a subtype of the interface_.

```
_ToS                          # _ToS interface
::MyApp::_Each[String]        # Interface name with namespace and type application
```

### Alias type

Alias type denotes an alias declared with _alias declaration_.

The name of type aliases starts with lowercase `[a-z]`.

```
name
::JSON::t                    # Alias name with namespace
list[Integer]                # Type alias can be generic
```

### Class singleton type

Class singleton type denotes _the type of a singleton object of a class_.

```
singleton(String)
singleton(::Hash)            # Class singleton type cannot be parametrized.
```

### Literal type

Literal type denotes _a type with only one value of the literal_.

```
123                         # Integer
"hello world"               # A string
:to_s                       # A symbol
true                        # true or false
```

### Union type

Union type denotes _a type of one of the given types_.

```
Integer | String           # Integer or String
Array[Integer | String]    # Array of Integer or String
```

### Intersection type

Intersection type denotes _a type of all of the given types_.

```
_Reader & _Writer           # _Reader and _Writer
```

Note that `&` has higher precedence than `|` that `A & B | C` is `(A & B) | C`.

### Optional type

Optional type denotes _a type of value or nil_.

```
Integer?
Array[Integer?]
```

### Record type

Records are `Hash` objects, fixed set of keys, and heterogeneous.

```
{ id: Integer, name: String }     # Hash object like `{ id: 31, name: String }`
```

### Tuple type

Tuples are `Array` objects, fixed size and heterogeneous.

```
[ ]                               # Empty like `[]`
[String]                          # Single string like `["hi"]`
[Integer, Integer]                # Pair of integers like `[1, 2]`
[Symbol, Integer, Integer]        # Tuple of Symbol, Integer, and Integer like `[:pair, 30, 22]`
```

*Empty tuple* or *1-tuple* sound strange, but RBS allows these types.

### Type variable

```
U
T
S
Elem
```

Type variables cannot be distinguished from _class instance types_.
They are scoped in _class/module/interface/alias declaration_ or _generic method types_.

```
class Ref[T]              # Object is scoped in the class declaration.
  @value: T               # Type variable `T`
  def map: [X] { (T) -> X } -> Ref[X]   # X is a type variable scoped in the method type.
end
```

### Proc type

Proc type denotes type of procedures, `Proc` instances.

```
^(Integer) -> String                  # A procedure with an `Integer` parameter and returns `String`
^(?String, size: Integer) -> bool     # A procedure with `String` optional parameter, `size` keyword of `Integer`, and returns `bool`
```

### Base types

`self` denotes the type of receiver. The type is used to model the open recursion via `self`.

`instance` denotes the type of instance of the class. `class` is the singleton of the class.

`bool` is an alias of `true | false`.

`untyped` is for _a type without type checking_. It is `?` in gradual typing, _dynamic_ in some languages like C#, and _any_ in TypeScript. It is both subtype _and_ supertype of all of the types. (The type was `any` but renamed to `untyped`.)

`nil` is for _nil_.

`top` is a supertype of all of the types. `bot` is a subtype of all of the types.

`void` is a supertype of all of the types.

#### `nil` or `NilClass`?

We recommend using `nil`.

#### `bool` or `boolish`

We have a builtin type alias called `boolish`.
It is an alias of `top` type, and you can use `boolish` if we want to allow any object of any type.

We can see an example at the definition of `Enumerable#find`:

```
module Enumerable[Elem, Return]
  def find: () { (Elem) -> boolish } -> Elem?
end
```

We want to write something like:

```
array.find {|x| x && x.some_test? }               # The block will return (bool | nil)
```

We recommend using `boolish` for method arguments and block return values, if you only use the values for conditions.
You can write `bool` if you strictly want `true | false`.

#### `void`, `boolish`, or `top`?

They are all equivalent for the type system; they are all _top type_.

`void` tells developers a hint that _the value should not be used_. `boolish` implies the value is used as a truth value. `top` is anything else.

## Method Types

```markdown
_method-type_ ::= `(` _parameters_ `) ->` _type_                                       # Method without block
                | `(` _parameters_ `) { (` _parameters_ `) -> ` _type_ `} ->` _type_   # Method with required block
                | `(` _parameters_ `) ?{ (` _parameters_ `) -> ` _type_ `} ->` _type_  # Method with optional block

_parameters_ ::= _required-positionals_ _optional-positionals_ _rest-positional_ _trailing-positionals_ _keywords_

_parameter_ ::= _type_ _var-name_                                  # Parameter with var name
              | _type_                                             # Parameter without var name
_required-positionals_ ::= _parameter_ `,` etc.
_optional-positionals_ ::= `?` _parameter_ `,` etc.
_rest-positional_ ::=                                              # Empty
                    | `*` _parameter_
_trailing-positionals_ ::= _parameter_ `,` etc.
_keywords_ ::=                                                     # Empty
             | `**` _parameter_                                    # Rest keyword
             | _keyword_ `:` _parameter_ `,` _keywords_            # Required keyword
             | `?` _keyword_ `:` _parameter_ `,` _keywords_        # Optional keyword

_var-name_ ::= /[a-z]\w*/
```

### Parameters

A parameter can be a type or a pair of type and variable name.
Variable name can be used for documentation.

### Examples

```
# Two required positional `Integer` parameters, and returns `String`
(Integer, Integer) -> String

# Two optional parameters `size` and `name`.
# `name` is a optional parameter with optional type so that developer can omit, pass a string, or pass `nil`.
(?Integer size, ?String? name) -> String

# Method type with a rest parameter
(*Integer, Integer) -> void

# `size` is a required keyword, with variable name of `sz`.
# `name` is a optional keyword.
# `created_at` is a optional keyword, and the value can be `nil`.
(size: Integer sz, ?name: String, ?created_at: Time?) -> void
```

## Members

```markdown
_member_ ::= _ivar-member_                # Ivar definition
           | _method-member_              # Method definition
           | _attribute-member_           # Attribute definition
           | _include-member_             # Mixin (include)
           | _extend-member_              # Mixin (extend)
           | _prepend-member_             # Mixin (prepend)
           | _alias-member_               # Alias
           | _visibility-member_          # Visibility member

_ivar-member_ ::= _ivar-name_ `:` _type_

_method-member_ ::= _visibility_ `def` _method-name_ `:` _method-types_            # Instance method
                  | _visibility_ `def self.` _method-name_ `:` _method-types_      # Singleton method
                  | `def self?.` _method-name_ `:` _method-types_     # Singleton and instance method

_method-types_ ::= _method-type-parameters_ _method-type_                       # Single method type
                 | _method-type-parameters_ _method-type_ `|` _method-types_    # Overloading types
                 | `...`                                                        # Overloading for duplicate definitions

_method-type-parameters_ ::=                                                    # Empty
                           | `[` _type-variable_ `,` ... `]`

_attribute-member_ ::= _visibility_ _attribute-type_ _method-name_ `:` _type_                     # Attribute
                     | _visibility_ _attribute-type_ _method-name_ `(` _ivar-name_ `) :` _type_   # Attribute with variable name specification
                     | _visibility_ _attribute-type_ _method-name_ `() :` _type_                  # Attribute without variable

_visibility_ ::= `public` | `private`

_attribute-type_ ::= `attr_reader` | `attr_writer` | `attr_accessor`

_include-member_ ::= `include` _class-name_ _type-arguments_
                   | `include` _interface-name_ _type-arguments_
_extend-member_ ::= `extend` _class-name_ _type-arguments_
                  | `extend` _interface-name_ _type-arguments_
_prepend-member_ ::= `prepend` _class-name_ _type-arguments_

_alias-member_ ::= `alias` _method-name_ _method-name_
                 | `alias self.` _method-name_ `self.` _method-name_

_visibility-member_ ::= _visibility_

_ivar-name_ ::= /@\w+/
_method-name_ ::= ...
                | /`[^`]+`/
```

### Ivar definition

An instance variable definition consists of the name of an instance variable and its type.

```
@name: String
@value: Hash[Symbol, Key]
```

### Method definition

Method definition has several syntax variations.

You can write `self.` or `self?.` before the name of the method to specify the kind of method: instance, singleton, or module function.

```
def to_s: () -> String                        # Defines a instance method
def self.new: () -> AnObject                  # Defines singleton method
def self?.sqrt: (Numeric) -> Numeric          # self? is for `module_function`s
```

`self?` method definition adds two methods: a public singleton method and a private instance method, which is equivalent to `module_function` in Ruby.

The method type can be connected with `|`s to define an overloaded method.

```
def +: (Float) -> Float
     | (Integer) -> Integer
     | (Numeric) -> Numeric
```

You need extra parentheses on return type to avoid ambiguity.

```
def +: (Float | Integer) -> (Float | Integer)
     | (Numeric) -> Numeric
```

Adding `public` and `private` modifier changes the visibility of the method.

```
private def puts: (*untyped) -> void       # Defines private instance method

public def self.puts: (*untyped) -> void   # Defines public singleton method

public def self?.puts: (*untyped) -> void  # 🚨🚨🚨 Error: `?.` has own visibility semantics (== `module_function`) 🚨🚨🚨
```

### Attribute definition

Attribute definitions help to define methods and instance variables based on the convention of `attr_reader`, `attr_writer` and `attr_accessor` methods in Ruby.

You can specify the name of instance variable using `(@some_name)` syntax and also omit the instance variable definition by specifying `()`.

```
# Defines `id` method and `@id` instance variable.
attr_reader id: Integer
# @id: Integer
# def id: () -> Integer

# Defines `name=` method and `@raw_name` instance variable.
attr_writer name (@raw_name) : String
# @raw_name: String
# def name=: (String) -> String

# Defines `people` and `people=` methods, but no instance variable.
attr_accessor people (): Array[Person]
# def people: () -> Array[Person]
# def people=: (Array[Person]) -> Array[Person]
```

Attribute definitions can have the `public` and `private` modifiers like method definitions:

```
private attr_accessor id: Integer

private attr_reader self.name: String
```

### Mixin (include), Mixin (extend), Mixin (prepend)

You can define mixins between class and modules.

```
include Kernel
include Enumerable[String, void]
extend ActiveSupport::Concern
```

You can also `include` or `extend` an interface.

```
include _Hashing
extend _LikeString
```

This allows importing `def`s from the interface to help developer implementing a set of methods.

### Alias

You can define an alias between methods.

```
def map: [X] () { (String) -> X } -> Array[X]
alias collect map                                   # `#collect` has the same type with `map`
```

### Visibility member

Visibility member allows specifying the default visibility of instance methods and instance attributes.

```rbs
public

def foo: () -> void          # public instance method

attr_reader name: String     # public instance attribute

private

def bar: () -> void          # private instance method

attr_reader email: String    # private instance attribute
```

The visibility _modifiers_ overwrite the default visibility per member bases.

The visibility member requires a new line `\n` after the token.

```rbs
private alias foo bar       # Syntax error
```

## Declarations

```markdown
_decl_ ::= _class-decl_                         # Class declaration
         | _module-decl_                        # Module declaration
         | _interface-decl_                     # Interface declaration
         | _type-alias-decl_                    # Type alias declaration
         | _const-decl_                         # Constant declaration
         | _global-decl_                        # Global declaration

_class-decl_ ::= `class` _class-name_ _module-type-parameters_ _members_ `end`
               | `class` _class-name_ _module-type-parameters_ `<` _class-name_ _type-arguments_ _members_ `end`

_module-decl_ ::= `module` _module-name_ _module-type-parameters_ _members_ `end`
                | `module` _module-name_ _module-type-parameters_ `:` _module-self-types_ _members_ `end`

_module-self-types_ ::= _class-name_ _type-arguments_ `,` _module-self-types_            (Class instance)
                      | _interface-name_ _type-arguments_ `,` _module-self-types_        (Interface)

_interface-decl_ ::= `interface` _interface-name_ _module-type-parameters_ _interface-members_ `end`

_interface-members_ ::= _method-member_              # Method
                      | _include-member_             # Mixin (include)
                      | _alias-member_               # Alias

_type-alias-decl_ ::= `type` _alias-name_ _module-type-parameters_ `=` _type_

_const-decl_ ::= _const-name_ `:` _type_

_global-decl_ ::= _global-name_ `:` _type_

_const-name_ ::= _namespace_ /[A-Z]\w*/
_global-name_ ::= /$[a-zA-Z]\w+/ | ...

_module-type-parameters_ ::=                                                  # Empty
                           | `[` _module-type-parameter_ `,` ... `]`
```

### Class declaration

Class declaration can have type parameters and superclass. When you omit superclass, `::Object` is assumed.

### Module declaration

Module declaration takes optional _self type_ parameter, which defines a constraint about a class when the module is mixed.

```
interface _Each[A, B]
  def each: { (A) -> void } -> B
end

module Enumerable[A, B] : _Each[A, B]
  def count: () -> Integer
end
```

The `Enumerable` module above requires `each` method for enumerating objects.

### Interface declaration

Interface declaration can have parameters but allows only a few of the members.

```
interface _Hashing
  def hash: () -> Integer
  def eql?: (any) -> bool
end
```

There are several limitations which are not described in the grammar.

1. Interface cannot `include` modules
2. Interface cannot have singleton method definitions

```
interface _Foo
  include Bar                  # Error: cannot include modules
  def self.new: () -> Foo      # Error: cannot include singleton method definitions
end
```

### Type alias declaration

You can declare an alias of types.

```
type subject = Attendee | Speaker
type JSON::t = Integer | TrueClass | FalseClass | String | Hash[Symbol, t] | Array[t]
```

Type alias can be generic like class, module, and interface.

```
type list[out T] = [T, list[T]] | nil
```

### Constant type declaration

You can declare a constant.

```
Person::DefaultEmailAddress: String
```

### Global type declaration

You can declare a global variable.

```
$LOAD_PATH: Array[String]
```

### Generics

```md
_module-type-parameter_ ::= _generics-unchecked_ _generics-variance_ _type-variable_ _generics-bound_

_method-type-param_ ::= _type-variable_ _generics-bound_

_generics-bound_ ::=                       (No type bound)
                   | `<` _bound-type_      (The generics parameter is bounded)

_bound-type_ ::= _class-name_ _type-arguments_       (Class instance type)
              | _interface-name_ _type-arguments_    (Interface type)
              | `singleton(` _class-name_ `)`        (Class singleton type)

_generics-variance_ ::=               (Invariant)
                      | `out`         (Covariant)
                      | `in`          (Contravariant)

_generics-unchecked_ ::=              (Empty)
                       | `unchecked`  (Skips variance annotation validation)
```

RBS allows class/module/interface/type alias definitions and methods to be generic.

```rbs
# Simple generic class definition
class Stack[T]
  def push: (T) -> void

  def pop: () -> T
end
```

For classes with type parameters, you may specify if they are "invariant" (default), "covariant" (`out`) or "contravariant" (`in`). See [this definition of covariance and contravariance](https://en.wikipedia.org/wiki/Covariance_and_contravariance_(computer_science)).

For example, an `Array` of `String` can almost be considered to be an `Array` of `Object`, but not the reverse, so we can think of:

```
# The `T` type parameter is covariant.
class Array[out T]
  # etc.
end
```

There's a limitation with this is for mutable objects (like arrays): a mutation could invalidate this.
If an array of `String` is passed to a method as an array of `Objects`, and that method adds an Integer to the array, the promise is broken.

In those cases, one must use the `unchecked` keyword:

```rbs
# Skips the validation of variance of the type parameter `T`.
# The type safety prohibits `out` type parameters to appear at _negative_ position (== method parameter), but we want `Array` to have it.
class Array[unchecked out T]
  def include?: (T) -> bool
end
```

This is how `Array` is actually defined in RBS.

Note that RBS doesn't allow specifying variance related annotations to generic method types.

```rbs
class Foo
  def bar: [out T] () -> T    # Syntax error
end
```

You can also specify the _upper bound_ of the type parameter.

```rbs
class PrettyPrint[T < _Output]
  interface _Output
    def <<: (String) -> void
  end

  attr_reader output: T
end
```

If a type parameter has an upper bound, the type parameter must be instantiated with types that is a subclass of the upper bound.

```rbs
type str_printer = PrettyPrint[String]    # OK
type int_printer = PrettyPrint[Integer]      # Type error
```

The upper bound must be one of a class instance type, interface type, or class singleton type.

### Comments

You can write single line comments. Comments must be on their own line. Comments can lead with whitespace.

```
# This if interface Foo
# Usage of Foo is bar
interface _Foo
  # New foo is a method
  # it will return foo.
  def new: () -> Foo
end
```
