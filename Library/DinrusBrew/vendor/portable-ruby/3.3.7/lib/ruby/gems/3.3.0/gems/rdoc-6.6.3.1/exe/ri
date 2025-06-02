#!/usr/bin/env ruby

begin
  gem 'rdoc'
rescue NameError => e # --disable-gems
  raise unless e.name == :gem
rescue Gem::LoadError
end

require 'rdoc/ri/driver'

RDoc::RI::Driver.run ARGV
