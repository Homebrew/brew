# Net::IMAP

Net::IMAP implements Internet Message Access Protocol (IMAP) client
functionality.  The protocol is described in [IMAP](https://tools.ietf.org/html/rfc3501).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'net-imap'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install net-imap

## Usage

### List sender and subject of all recent messages in the default mailbox

```ruby
imap = Net::IMAP.new('mail.example.com')
imap.authenticate('LOGIN', 'joe_user', 'joes_password')
imap.examine('INBOX')
imap.search(["RECENT"]).each do |message_id|
  envelope = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
  puts "#{envelope.from[0].name}: \t#{envelope.subject}"
end
```

### Move all messages from April 2003 from "Mail/sent-mail" to "Mail/sent-apr03"

```ruby
imap = Net::IMAP.new('mail.example.com')
imap.authenticate('LOGIN', 'joe_user', 'joes_password')
imap.select('Mail/sent-mail')
if not imap.list('Mail/', 'sent-apr03')
  imap.create('Mail/sent-apr03')
end
imap.search(["BEFORE", "30-Apr-2003", "SINCE", "1-Apr-2003"]).each do |message_id|
  imap.copy(message_id, "Mail/sent-apr03")
  imap.store(message_id, "+FLAGS", [:Deleted])
end
imap.expunge
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/net-imap.

