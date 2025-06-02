# -*- encoding: utf-8 -*-
# stub: bigdecimal 3.1.5 ruby lib
# stub: ext/bigdecimal/extconf.rb

Gem::Specification.new do |s|
  s.name = "bigdecimal".freeze
  s.version = "3.1.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Kenta Murata".freeze, "Zachary Scott".freeze, "Shigeo Kobayashi".freeze]
  s.date = "2025-01-15"
  s.description = "This library provides arbitrary-precision decimal floating-point number class.".freeze
  s.email = ["mrkn@mrkn.jp".freeze]
  s.extensions = ["ext/bigdecimal/extconf.rb".freeze]
  s.files = ["bigdecimal.rb".freeze, "bigdecimal.so".freeze, "bigdecimal/jacobian.rb".freeze, "bigdecimal/ludcmp.rb".freeze, "bigdecimal/math.rb".freeze, "bigdecimal/newton.rb".freeze, "bigdecimal/util.rb".freeze, "ext/bigdecimal/extconf.rb".freeze]
  s.homepage = "https://github.com/ruby/bigdecimal".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Arbitrary-precision decimal floating-point number library.".freeze
end
