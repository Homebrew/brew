# Prime

Prime numbers and factorization library.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prime'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install prime

## Usage

```ruby
require 'prime'

# Prime is the set of all prime numbers, and it is Enumerable.
Prime.take(4)             #=> [2, 3, 5, 7]
Prime.first(4)            #=> [2, 3, 5, 7]
Prime.each(7).to_a        #=> [2, 3, 5, 7]

# Determining whether an arbitrary integer is a prime number
Prime.prime?(7)           #=> true
8.prime?                  #=> false

# Factorization in prime numbers
Prime.prime_division(8959)                          #=> [[17, 2], [31, 1]]
Prime.int_from_prime_division([[17, 2], [31, 1]])   #=> 8959
17**2 * 31                                          #=> 8959
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/prime.

## License

The gem is available as open source under the terms of the [BSD-2-Clause](LICENSE.txt).
