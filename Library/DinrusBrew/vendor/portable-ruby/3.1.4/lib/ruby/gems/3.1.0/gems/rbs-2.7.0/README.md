# RBS

RBS is a language to describe the structure of Ruby programs.
You can write down the definition of a class or module: methods defined in the class, instance variables and their types, and inheritance/mix-in relations.
It also allows declaring constants and global variables.

The following is a small example of RBS for a chat app.

<!-- run-start:a.rbs:bundle exec rbs -I a.rbs validate -->
```rb
module ChatApp
  VERSION: String

  class User
    attr_reader login: String
    attr_reader email: String

    def initialize: (login: String, email: String) -> void
  end

  class Bot
    attr_reader name: String
    attr_reader email: String
    attr_reader owner: User

    def initialize: (name: String, owner: User) -> void
  end

  class Message
    attr_reader id: String
    attr_reader string: String
    attr_reader from: User | Bot                     # `|` means union types: `#from` can be `User` or `Bot`
    attr_reader reply_to: Message?                   # `?` means optional type: `#reply_to` can be `nil`

    def initialize: (from: User | Bot, string: String) -> void

    def reply: (from: User | Bot, string: String) -> Message
  end

  class Channel
    attr_reader name: String
    attr_reader messages: Array[Message]
    attr_reader users: Array[User]
    attr_reader bots: Array[Bot]

    def initialize: (name: String) -> void

    def each_member: () { (User | Bot) -> void } -> void  # `{` and `}` means block.
                   | () -> Enumerator[User | Bot, void]   # Method can be overloaded.
  end
end
```
<!-- run-end -->

## The Target Version

* The standard library signatures targets Ruby 3.1. (The latest release of Ruby.)
* The library code targets Ruby 3.1, 3.0, and 2.7. (It runs on 2.6 in fact.)

## Installation

Install the `rbs` gem. `$ gem install rbs` from the command line, or add a line in your `Gemfile`.

```rb
gem "rbs"
```

## CLI

The gem ships with the `rbs` command line tool to demonstrate what it can do and help develop RBS.

```bash
$ rbs version
$ rbs list
$ rbs ancestors ::Object
$ rbs methods ::Object
$ rbs method Object then
```

## Library

There are two important concepts, _environment_ and _definition_.

An _environment_ is a dictionary that keeps track of all declarations. What is the declaration associated with `String` class? An _environment_ will give you the answer.

A _definition_ gives you the detail of the class. What is the type of the return value of `gsub` method of the `String` class? The _definition_ for `String` class knows the list of methods it provides and their types.

The following is a small code to retrieve the definition of the `String#gsub` method.

<!-- run-start:a.rb:bundle exec ruby a.rb -->
```rb
require "rbs"

loader = RBS::EnvironmentLoader.new()

# loader.add(path: Pathname("sig"))   # Load .rbs files from `sig` directory
# loader.add(library: "pathname")     # Load pathname library

environment = RBS::Environment.from_loader(loader).resolve_type_names

# ::String
string = RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root)

# Class declaration for ::String
decl = environment.class_decls[string]

# Builder provides the translation from `declaration` to `definition`
builder = RBS::DefinitionBuilder.new(env: environment)

# Definition of instance of String
instance = builder.build_instance(string)

# Print the types of `gsub` method:
puts instance.methods[:gsub].method_types.join("\n")
# Outputs =>
#  (::Regexp | ::string pattern, ::string replacement) -> ::String
#  (::Regexp | ::string pattern, ::Hash[::String, ::String] hash) -> ::String
#  (::Regexp | ::string pattern) { (::String match) -> ::_ToS } -> ::String
#  (::Regexp | ::string pattern) -> ::Enumerator[::String, self]

# Definition of singleton of String
singleton = builder.build_singleton(string)
# No `gsub` method for String singleton
puts singleton.methods[:gsub]
```
<!-- run-end -->

## Guides

- [Core and standard library signature contribution guide](docs/CONTRIBUTING.md)
- [Writing signatures guide](docs/sigs.md)
- [Stdlib signatures guide](docs/stdlib.md)
- [Syntax](docs/syntax.md)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/rbs.
