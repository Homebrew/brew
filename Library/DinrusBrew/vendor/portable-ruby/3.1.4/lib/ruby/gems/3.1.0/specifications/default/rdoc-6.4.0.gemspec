# -*- encoding: utf-8 -*-
# stub: rdoc 6.4.0 ruby lib

Gem::Specification.new do |s|
  s.name = "rdoc".freeze
  s.version = "6.4.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 2.2".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Eric Hodel".freeze, "Dave Thomas".freeze, "Phil Hagelberg".freeze, "Tony Strauss".freeze, "Zachary Scott".freeze, "Hiroshi SHIBATA".freeze, "ITOYANAGI Sakura".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-30"
  s.description = "RDoc produces HTML and command-line documentation for Ruby projects.\nRDoc includes the +rdoc+ and +ri+ tools for generating and displaying documentation from the command-line.\n".freeze
  s.email = ["drbrain@segment7.net".freeze, "".freeze, "".freeze, "".freeze, "mail@zzak.io".freeze, "hsbt@ruby-lang.org".freeze, "aycabta@gmail.com".freeze]
  s.executables = ["rdoc".freeze, "ri".freeze]
  s.extra_rdoc_files = ["CVE-2013-0256.rdoc".freeze, "CONTRIBUTING.rdoc".freeze, "ExampleMarkdown.md".freeze, "ExampleRDoc.rdoc".freeze, "History.rdoc".freeze, "LEGAL.rdoc".freeze, "LICENSE.rdoc".freeze, "README.rdoc".freeze, "RI.rdoc".freeze, "TODO.rdoc".freeze]
  s.files = ["CONTRIBUTING.rdoc".freeze, "CVE-2013-0256.rdoc".freeze, "ExampleMarkdown.md".freeze, "ExampleRDoc.rdoc".freeze, "History.rdoc".freeze, "LEGAL.rdoc".freeze, "LICENSE.rdoc".freeze, "README.rdoc".freeze, "RI.rdoc".freeze, "TODO.rdoc".freeze, "exe/rdoc".freeze, "exe/ri".freeze, "lib/rdoc.rb".freeze, "lib/rdoc/alias.rb".freeze, "lib/rdoc/anon_class.rb".freeze, "lib/rdoc/any_method.rb".freeze, "lib/rdoc/attr.rb".freeze, "lib/rdoc/class_module.rb".freeze, "lib/rdoc/code_object.rb".freeze, "lib/rdoc/code_objects.rb".freeze, "lib/rdoc/comment.rb".freeze, "lib/rdoc/constant.rb".freeze, "lib/rdoc/context.rb".freeze, "lib/rdoc/context/section.rb".freeze, "lib/rdoc/cross_reference.rb".freeze, "lib/rdoc/encoding.rb".freeze, "lib/rdoc/erb_partial.rb".freeze, "lib/rdoc/erbio.rb".freeze, "lib/rdoc/extend.rb".freeze, "lib/rdoc/generator.rb".freeze, "lib/rdoc/generator/darkfish.rb".freeze, "lib/rdoc/generator/json_index.rb".freeze, "lib/rdoc/generator/markup.rb".freeze, "lib/rdoc/generator/pot.rb".freeze, "lib/rdoc/generator/pot/message_extractor.rb".freeze, "lib/rdoc/generator/pot/po.rb".freeze, "lib/rdoc/generator/pot/po_entry.rb".freeze, "lib/rdoc/generator/ri.rb".freeze, "lib/rdoc/ghost_method.rb".freeze, "lib/rdoc/i18n.rb".freeze, "lib/rdoc/i18n/locale.rb".freeze, "lib/rdoc/i18n/text.rb".freeze, "lib/rdoc/include.rb".freeze, "lib/rdoc/known_classes.rb".freeze, "lib/rdoc/markdown.rb".freeze, "lib/rdoc/markdown/entities.rb".freeze, "lib/rdoc/markdown/literals.rb".freeze, "lib/rdoc/markup.rb".freeze, "lib/rdoc/markup/attr_changer.rb".freeze, "lib/rdoc/markup/attr_span.rb".freeze, "lib/rdoc/markup/attribute_manager.rb".freeze, "lib/rdoc/markup/attributes.rb".freeze, "lib/rdoc/markup/blank_line.rb".freeze, "lib/rdoc/markup/block_quote.rb".freeze, "lib/rdoc/markup/document.rb".freeze, "lib/rdoc/markup/formatter.rb".freeze, "lib/rdoc/markup/hard_break.rb".freeze, "lib/rdoc/markup/heading.rb".freeze, "lib/rdoc/markup/include.rb".freeze, "lib/rdoc/markup/indented_paragraph.rb".freeze, "lib/rdoc/markup/list.rb".freeze, "lib/rdoc/markup/list_item.rb".freeze, "lib/rdoc/markup/paragraph.rb".freeze, "lib/rdoc/markup/parser.rb".freeze, "lib/rdoc/markup/pre_process.rb".freeze, "lib/rdoc/markup/raw.rb".freeze, "lib/rdoc/markup/regexp_handling.rb".freeze, "lib/rdoc/markup/rule.rb".freeze, "lib/rdoc/markup/table.rb".freeze, "lib/rdoc/markup/to_ansi.rb".freeze, "lib/rdoc/markup/to_bs.rb".freeze, "lib/rdoc/markup/to_html.rb".freeze, "lib/rdoc/markup/to_html_crossref.rb".freeze, "lib/rdoc/markup/to_html_snippet.rb".freeze, "lib/rdoc/markup/to_joined_paragraph.rb".freeze, "lib/rdoc/markup/to_label.rb".freeze, "lib/rdoc/markup/to_markdown.rb".freeze, "lib/rdoc/markup/to_rdoc.rb".freeze, "lib/rdoc/markup/to_table_of_contents.rb".freeze, "lib/rdoc/markup/to_test.rb".freeze, "lib/rdoc/markup/to_tt_only.rb".freeze, "lib/rdoc/markup/verbatim.rb".freeze, "lib/rdoc/meta_method.rb".freeze, "lib/rdoc/method_attr.rb".freeze, "lib/rdoc/mixin.rb".freeze, "lib/rdoc/normal_class.rb".freeze, "lib/rdoc/normal_module.rb".freeze, "lib/rdoc/options.rb".freeze, "lib/rdoc/parser.rb".freeze, "lib/rdoc/parser/c.rb".freeze, "lib/rdoc/parser/changelog.rb".freeze, "lib/rdoc/parser/markdown.rb".freeze, "lib/rdoc/parser/rd.rb".freeze, "lib/rdoc/parser/ripper_state_lex.rb".freeze, "lib/rdoc/parser/ruby.rb".freeze, "lib/rdoc/parser/ruby_tools.rb".freeze, "lib/rdoc/parser/simple.rb".freeze, "lib/rdoc/parser/text.rb".freeze, "lib/rdoc/rd.rb".freeze, "lib/rdoc/rd/block_parser.rb".freeze, "lib/rdoc/rd/inline.rb".freeze, "lib/rdoc/rd/inline_parser.rb".freeze, "lib/rdoc/rdoc.rb".freeze, "lib/rdoc/require.rb".freeze, "lib/rdoc/ri.rb".freeze, "lib/rdoc/ri/driver.rb".freeze, "lib/rdoc/ri/formatter.rb".freeze, "lib/rdoc/ri/paths.rb".freeze, "lib/rdoc/ri/store.rb".freeze, "lib/rdoc/ri/task.rb".freeze, "lib/rdoc/rubygems_hook.rb".freeze, "lib/rdoc/servlet.rb".freeze, "lib/rdoc/single_class.rb".freeze, "lib/rdoc/stats.rb".freeze, "lib/rdoc/stats/normal.rb".freeze, "lib/rdoc/stats/quiet.rb".freeze, "lib/rdoc/stats/verbose.rb".freeze, "lib/rdoc/store.rb".freeze, "lib/rdoc/task.rb".freeze, "lib/rdoc/text.rb".freeze, "lib/rdoc/token_stream.rb".freeze, "lib/rdoc/tom_doc.rb".freeze, "lib/rdoc/top_level.rb".freeze, "lib/rdoc/version.rb".freeze]
  s.homepage = "https://ruby.github.io/rdoc".freeze
  s.licenses = ["Ruby".freeze]
  s.rdoc_options = ["--main".freeze, "README.rdoc".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "RDoc produces HTML and command-line documentation for Ruby projects".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<psych>.freeze, [">= 4.0.0"])
  else
    s.add_dependency(%q<psych>.freeze, [">= 4.0.0"])
  end
end
