# Net::POP3

This library provides functionality for retrieving
email via POP3, the Post Office Protocol version 3. For details
of POP3, see [RFC1939] (http://www.ietf.org/rfc/rfc1939.txt).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'net-pop'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install net-pop

## Usage

This example retrieves messages from the server and deletes them
on the server.

Messages are written to files named 'inbox/1', 'inbox/2', ....
Replace 'pop.example.com' with your POP3 server address, and
'YourAccount' and 'YourPassword' with the appropriate account
details.

```ruby
require 'net/pop'

pop = Net::POP3.new('pop.example.com')
pop.start('YourAccount', 'YourPassword')             # (1)
if pop.mails.empty?
  puts 'No mail.'
else
  i = 0
  pop.each_mail do |m|   # or "pop.mails.each ..."   # (2)
    File.open("inbox/#{i}", 'w') do |f|
      f.write m.pop
    end
    m.delete
    i += 1
  end
  puts "#{pop.mails.size} mails popped."
end
pop.finish                                           # (3)
```

1. Call Net::POP3#start and start POP session.
2. Access messages by using POP3#each_mail and/or POP3#mails.
3. Close POP session by calling POP3#finish or use the block form of #start.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/net-pop.
