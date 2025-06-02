# -*- encoding: utf-8 -*-
# stub: net-http 0.4.1 ruby lib

Gem::Specification.new do |s|
  s.name = "net-http".freeze
  s.version = "0.4.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/net-http", "source_code_uri" => "https://github.com/ruby/net-http" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["NARUSE, Yui".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "HTTP client api for Ruby.".freeze
  s.email = ["naruse@airemix.jp".freeze]
  s.files = ["net/http.rb".freeze, "net/http/backward.rb".freeze, "net/http/exceptions.rb".freeze, "net/http/generic_request.rb".freeze, "net/http/header.rb".freeze, "net/http/proxy_delta.rb".freeze, "net/http/request.rb".freeze, "net/http/requests.rb".freeze, "net/http/response.rb".freeze, "net/http/responses.rb".freeze, "net/http/status.rb".freeze, "net/https.rb".freeze]
  s.homepage = "https://github.com/ruby/net-http".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "HTTP client api for Ruby.".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<uri>.freeze, [">= 0".freeze])
end
