# -*- encoding: utf-8 -*-
# stub: reline 0.5.10 ruby lib

Gem::Specification.new do |s|
  s.name = "reline".freeze
  s.version = "0.5.10".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/ruby/reline/issues", "changelog_uri" => "https://github.com/ruby/reline/releases", "source_code_uri" => "https://github.com/ruby/reline" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["aycabta".freeze]
  s.date = "2025-01-15"
  s.description = "Alternative GNU Readline or Editline implementation by pure Ruby.".freeze
  s.email = ["aycabta@gmail.com".freeze]
  s.files = ["reline.rb".freeze, "reline/config.rb".freeze, "reline/face.rb".freeze, "reline/history.rb".freeze, "reline/io.rb".freeze, "reline/io/ansi.rb".freeze, "reline/io/dumb.rb".freeze, "reline/io/windows.rb".freeze, "reline/key_actor.rb".freeze, "reline/key_actor/base.rb".freeze, "reline/key_actor/composite.rb".freeze, "reline/key_actor/emacs.rb".freeze, "reline/key_actor/vi_command.rb".freeze, "reline/key_actor/vi_insert.rb".freeze, "reline/key_stroke.rb".freeze, "reline/kill_ring.rb".freeze, "reline/line_editor.rb".freeze, "reline/terminfo.rb".freeze, "reline/unicode.rb".freeze, "reline/unicode/east_asian_width.rb".freeze, "reline/version.rb".freeze]
  s.homepage = "https://github.com/ruby/reline".freeze
  s.licenses = ["Ruby".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Alternative GNU Readline or Editline implementation by pure Ruby.".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<io-console>.freeze, ["~> 0.5".freeze])
end
