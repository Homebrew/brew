# MessagePack

[MessagePack](http://msgpack.org) is an efficient binary serialization format.
It lets you exchange data among multiple languages like JSON but it's faster and smaller.
For example, small integers (like flags or error code) are encoded into a single byte,
and typical short strings only require an extra byte in addition to the strings themselves.

If you ever wished to use JSON for convenience (storing an image with metadata) but could
not for technical reasons (binary data, size, speed...), MessagePack is a perfect replacement.

```ruby
require 'msgpack'
msg = [1,2,3].to_msgpack  #=> "\x93\x01\x02\x03"
MessagePack.unpack(msg)   #=> [1,2,3]
```

Add msgpack to your Gemfile to install with Bundler:

```ruby
# Gemfile
gem 'msgpack'
```

Or, use RubyGems to install:

    gem install msgpack

Or, build msgpack-ruby and install from a checked-out msgpack-ruby repository:

    bundle
    rake
    gem install --local pkg/msgpack


## Use cases

* Create REST API returing MessagePack using Rails + [RABL](https://github.com/nesquena/rabl)
* Store objects efficiently serialized by msgpack on memcached or Redis
  * In fact Redis supports msgpack in [EVAL-scripts](https://redis.io/docs/latest/commands/eval/)
* Upload data in efficient format from mobile devices such as smartphones
  * MessagePack works on iPhone/iPad and Android. See also [Objective-C](https://github.com/msgpack/msgpack-objectivec) and [Java](https://github.com/msgpack/msgpack-java) implementations
* Design a portable protocol to communicate with embedded devices
  * Check also [Fluentd](https://www.fluentd.org) which is a log collector which uses msgpack for the log format (they say it uses JSON but actually it's msgpack, which is compatible with JSON)
* Exchange objects between software components written in different languages
  * You'll need a flexible but efficient format so that components exchange objects while keeping compatibility

## Portability

MessagePack for Ruby should run on x86, ARM, PowerPC, SPARC and other CPU architectures.

And it works with MRI (CRuby) and Rubinius.
Patches to improve portability are highly welcomed.


## Serializing objects

Use `MessagePack.pack` or `to_msgpack`:

```ruby
require 'msgpack'
msg = MessagePack.pack(obj)  # or
msg = obj.to_msgpack
File.binwrite('mydata.msgpack', msg)
```

### Streaming serialization

Packer provides advanced API to serialize objects in streaming style:

```ruby
# serialize a 2-element array [e1, e2]
pk = MessagePack::Packer.new(io)
pk.write_array_header(2).write(e1).write(e2).flush
```

See [API reference](http://ruby.msgpack.org/MessagePack/Packer.html) for details.

## Deserializing objects

Use `MessagePack.unpack`:

```ruby
require 'msgpack'
msg = File.binread('mydata.msgpack')
obj = MessagePack.unpack(msg)
```

### Streaming deserialization

Unpacker provides advanced API to deserialize objects in streaming style:

```ruby
# deserialize objects from an IO
u = MessagePack::Unpacker.new(io)
u.each do |obj|
  # ...
end
```

or event-driven style which works well with EventMachine:

```ruby
# event-driven deserialization
def on_read(data)
  @u ||= MessagePack::Unpacker.new
  @u.feed_each(data) {|obj|
     # ...
  }
end
```

See [API reference](http://ruby.msgpack.org/MessagePack/Unpacker.html) for details.

## Serializing and deserializing symbols

By default, symbols are serialized as strings:

```ruby
packed = :symbol.to_msgpack     # => "\xA6symbol"
MessagePack.unpack(packed)      # => "symbol"
```

This can be customized by registering an extension type for them:

```ruby
MessagePack::DefaultFactory.register_type(0x00, Symbol)

# symbols now survive round trips
packed = :symbol.to_msgpack     # => "\xc7\x06\x00symbol"
MessagePack.unpack(packed)      # => :symbol
```

The extension type for symbols is configurable like any other extension type.
For example, to customize how symbols are packed you can just redefine
Symbol#to_msgpack_ext. Doing this gives you an option to prevent symbols from
being serialized altogether by throwing an exception:

```ruby
class Symbol
  def to_msgpack_ext
    raise "Serialization of symbols prohibited"
  end
end

MessagePack::DefaultFactory.register_type(0x00, Symbol)

[1, :symbol, 'string'].to_msgpack  # => RuntimeError: Serialization of symbols prohibited
```

## Serializing and deserializing Time instances

There are the timestamp extension type in MessagePack,
but it is not registered by default.

To map Ruby's Time to MessagePack's timestamp for the default factory:

```ruby
MessagePack::DefaultFactory.register_type(
  MessagePack::Timestamp::TYPE, # or just -1
  Time,
  packer: MessagePack::Time::Packer,
  unpacker: MessagePack::Time::Unpacker
)
```

See [API reference](http://ruby.msgpack.org/) for details.

## Extension Types

Packer and Unpacker support [Extension types of MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md#types-extension-type).

```ruby
# register how to serialize custom class at first
pk = MessagePack::Packer.new(io)
pk.register_type(0x01, MyClass1, :to_msgpack_ext) # equal to pk.register_type(0x01, MyClass)
pk.register_type(0x02, MyClass2){|obj| obj.how_to_serialize() } # blocks also available

# almost same API for unpacker
uk = MessagePack::Unpacker.new()
uk.register_type(0x01, MyClass1, :from_msgpack_ext)
uk.register_type(0x02){|data| MyClass2.create_from_serialized_data(data) }
```

`MessagePack::Factory` is to create packer and unpacker which have same extension types.

```ruby
factory = MessagePack::Factory.new
factory.register_type(0x01, MyClass1) # same with next line
factory.register_type(0x01, MyClass1, packer: :to_msgpack_ext, unpacker: :from_msgpack_ext)
pk = factory.packer(options_for_packer)
uk = factory.unpacker(options_for_unpacker)
```

For `MessagePack.pack` and `MessagePack.unpack`, default packer/unpacker refer `MessagePack::DefaultFactory`. Call `MessagePack::DefaultFactory.register_type` to enable types process globally.

```ruby
MessagePack::DefaultFactory.register_type(0x03, MyClass3)
MessagePack.unpack(data_with_ext_typeid_03) #=> MyClass3 instance
```

Alternatively, extension types can call the packer or unpacker recursively to generate the extension data:

```ruby
Point = Struct.new(:x, :y)
factory = MessagePack::Factory.new
factory.register_type(
  0x01,
  Point,
  packer: ->(point, packer) {
    packer.write(point.x)
    packer.write(point.y)
  },
  unpacker: ->(unpacker) {
    x = unpacker.read
    y = unpacker.read
    Point.new(x, y)
  },
  recursive: true,
)
factory.load(factory.dump(Point.new(12, 34))) # => #<struct Point x=12, y=34>
```

## Pooling

Creating `Packer` and `Unpacker` objects is expensive. For best performance it is preferable to re-use these objects.

`MessagePack::Factory#pool` makes that easier:

```ruby
factory = MessagePack::Factory.new
factory.register_type(
  0x01,
  Point,
  packer: ->(point, packer) {
    packer.write(point.x)
    packer.write(point.y)
  },
  unpacker: ->(unpacker) {
    x = unpacker.read
    y = unpacker.read
    Point.new(x, y)
  },
  recursive: true,
)
pool = factory.pool(5) # The pool size should match the number of threads expected to use the factory concurrently.

pool.load(pool.dump(Point.new(12, 34))) # => #<struct Point x=12, y=34>
```

## Buffer API

MessagePack for Ruby provides a buffer API so that you can read or write data by hand, not via Packer or Unpacker API.

This [MessagePack::Buffer](http://ruby.msgpack.org/MessagePack/Buffer.html) is backed with a fixed-length shared memory pool which is very fast for small data (<= 4KB),
and has zero-copy capability which significantly affects performance to handle large binary data.

## How to build and run tests

Before building msgpack, you need to install bundler and dependencies.

    gem install bundler
    bundle install

Then, you can run the tasks as follows:

### Build

    bundle exec rake build

### Run tests

    bundle exec rake spec

### Generating docs

    bundle exec rake doc

## How to build -java rubygems

To build -java gems for JRuby, run:

    rake build:java

If this directory has Gemfile.lock (generated with MRI), remove it beforehand.

## Updating documents

Online documentation (https://ruby.msgpack.org) is generated from the gh-pages branch.
To update documents in gh-pages branch:

    bundle exec rake doc
    git checkout gh-pages
    cp doc/* ./ -a

## Copyright

* Author
  * Sadayuki Furuhashi <frsyuki@gmail.com>
* Copyright
  * Copyright (c) 2008-2015 Sadayuki Furuhashi
* License
  * Apache License, Version 2.0
