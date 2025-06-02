# Net::FTP

This class implements the File Transfer Protocol.  If you have used a
command-line FTP program, and are familiar with the commands, you will be
able to use this class easily.  Some extra features are included to take
advantage of Ruby's style and strengths.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'net-ftp'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install net-ftp

## Usage

### Example 1

```ruby
ftp = Net::FTP.new('example.com')
ftp.login
files = ftp.chdir('pub/lang/ruby/contrib')
files = ftp.list('n*')
ftp.getbinaryfile('nif.rb-0.91.gz', 'nif.gz', 1024)
ftp.close
```

### Example 2

```ruby
Net::FTP.open('example.com') do |ftp|
  ftp.login
  files = ftp.chdir('pub/lang/ruby/contrib')
  files = ftp.list('n*')
  ftp.getbinaryfile('nif.rb-0.91.gz', 'nif.gz', 1024)
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/net-ftp.
