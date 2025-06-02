# -*- encoding: utf-8 -*-
# stub: irb 1.4.1 ruby lib

Gem::Specification.new do |s|
  s.name = "irb".freeze
  s.version = "1.4.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Keiju ISHITSUKA".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-30"
  s.description = "Interactive Ruby command-line tool for REPL (Read Eval Print Loop).".freeze
  s.email = ["keiju@ruby-lang.org".freeze]
  s.executables = ["irb".freeze]
  s.files = ["exe/irb".freeze, "lib/irb.rb".freeze, "lib/irb/cmd/chws.rb".freeze, "lib/irb/cmd/fork.rb".freeze, "lib/irb/cmd/help.rb".freeze, "lib/irb/cmd/info.rb".freeze, "lib/irb/cmd/load.rb".freeze, "lib/irb/cmd/ls.rb".freeze, "lib/irb/cmd/measure.rb".freeze, "lib/irb/cmd/nop.rb".freeze, "lib/irb/cmd/pushws.rb".freeze, "lib/irb/cmd/show_source.rb".freeze, "lib/irb/cmd/subirb.rb".freeze, "lib/irb/cmd/whereami.rb".freeze, "lib/irb/color.rb".freeze, "lib/irb/color_printer.rb".freeze, "lib/irb/completion.rb".freeze, "lib/irb/context.rb".freeze, "lib/irb/easter-egg.rb".freeze, "lib/irb/ext/change-ws.rb".freeze, "lib/irb/ext/history.rb".freeze, "lib/irb/ext/loader.rb".freeze, "lib/irb/ext/multi-irb.rb".freeze, "lib/irb/ext/save-history.rb".freeze, "lib/irb/ext/tracer.rb".freeze, "lib/irb/ext/use-loader.rb".freeze, "lib/irb/ext/workspaces.rb".freeze, "lib/irb/extend-command.rb".freeze, "lib/irb/frame.rb".freeze, "lib/irb/help.rb".freeze, "lib/irb/init.rb".freeze, "lib/irb/input-method.rb".freeze, "lib/irb/inspector.rb".freeze, "lib/irb/lc/error.rb".freeze, "lib/irb/lc/ja/encoding_aliases.rb".freeze, "lib/irb/lc/ja/error.rb".freeze, "lib/irb/locale.rb".freeze, "lib/irb/magic-file.rb".freeze, "lib/irb/notifier.rb".freeze, "lib/irb/output-method.rb".freeze, "lib/irb/ruby-lex.rb".freeze, "lib/irb/src_encoding.rb".freeze, "lib/irb/version.rb".freeze, "lib/irb/workspace.rb".freeze, "lib/irb/ws-for-case-2.rb".freeze, "lib/irb/xmp.rb".freeze]
  s.homepage = "https://github.com/ruby/irb".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Interactive Ruby command-line tool for REPL (Read Eval Print Loop).".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<reline>.freeze, [">= 0.3.0"])
  else
    s.add_dependency(%q<reline>.freeze, [">= 0.3.0"])
  end
end
