# -*- encoding: utf-8 -*-
# stub: irb 1.13.1 ruby lib

Gem::Specification.new do |s|
  s.name = "irb".freeze
  s.version = "1.13.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/ruby/irb/releases", "documentation_uri" => "https://github.com/ruby/irb", "homepage_uri" => "https://github.com/ruby/irb", "source_code_uri" => "https://github.com/ruby/irb" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["aycabta".freeze, "Keiju ISHITSUKA".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Interactive Ruby command-line tool for REPL (Read Eval Print Loop).".freeze
  s.email = ["aycabta@gmail.com".freeze, "keiju@ruby-lang.org".freeze]
  s.executables = ["irb".freeze]
  s.files = ["exe/irb".freeze, "irb.rb".freeze, "irb/cmd/nop.rb".freeze, "irb/color.rb".freeze, "irb/color_printer.rb".freeze, "irb/command.rb".freeze, "irb/command/backtrace.rb".freeze, "irb/command/base.rb".freeze, "irb/command/break.rb".freeze, "irb/command/catch.rb".freeze, "irb/command/chws.rb".freeze, "irb/command/context.rb".freeze, "irb/command/continue.rb".freeze, "irb/command/debug.rb".freeze, "irb/command/delete.rb".freeze, "irb/command/disable_irb.rb".freeze, "irb/command/edit.rb".freeze, "irb/command/exit.rb".freeze, "irb/command/finish.rb".freeze, "irb/command/force_exit.rb".freeze, "irb/command/help.rb".freeze, "irb/command/history.rb".freeze, "irb/command/info.rb".freeze, "irb/command/internal_helpers.rb".freeze, "irb/command/irb_info.rb".freeze, "irb/command/load.rb".freeze, "irb/command/ls.rb".freeze, "irb/command/measure.rb".freeze, "irb/command/next.rb".freeze, "irb/command/pushws.rb".freeze, "irb/command/show_doc.rb".freeze, "irb/command/show_source.rb".freeze, "irb/command/step.rb".freeze, "irb/command/subirb.rb".freeze, "irb/command/whereami.rb".freeze, "irb/completion.rb".freeze, "irb/context.rb".freeze, "irb/debug.rb".freeze, "irb/debug/ui.rb".freeze, "irb/default_commands.rb".freeze, "irb/easter-egg.rb".freeze, "irb/ext/change-ws.rb".freeze, "irb/ext/eval_history.rb".freeze, "irb/ext/loader.rb".freeze, "irb/ext/multi-irb.rb".freeze, "irb/ext/tracer.rb".freeze, "irb/ext/use-loader.rb".freeze, "irb/ext/workspaces.rb".freeze, "irb/frame.rb".freeze, "irb/help.rb".freeze, "irb/helper_method.rb".freeze, "irb/helper_method/base.rb".freeze, "irb/helper_method/conf.rb".freeze, "irb/history.rb".freeze, "irb/init.rb".freeze, "irb/input-method.rb".freeze, "irb/inspector.rb".freeze, "irb/lc/error.rb".freeze, "irb/lc/ja/error.rb".freeze, "irb/locale.rb".freeze, "irb/nesting_parser.rb".freeze, "irb/notifier.rb".freeze, "irb/output-method.rb".freeze, "irb/pager.rb".freeze, "irb/ruby-lex.rb".freeze, "irb/source_finder.rb".freeze, "irb/statement.rb".freeze, "irb/version.rb".freeze, "irb/workspace.rb".freeze, "irb/ws-for-case-2.rb".freeze, "irb/xmp.rb".freeze]
  s.homepage = "https://github.com/ruby/irb".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Interactive Ruby command-line tool for REPL (Read Eval Print Loop).".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<reline>.freeze, [">= 0.4.2".freeze])
  s.add_runtime_dependency(%q<rdoc>.freeze, [">= 4.0.0".freeze])
end
