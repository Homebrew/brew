# frozen_string_literal: true
##
# RDoc::Markup parses plain text documents and attempts to decompose them into
# their constituent parts.  Some of these parts are high-level: paragraphs,
# chunks of verbatim text, list entries and the like.  Other parts happen at
# the character level: a piece of bold text, a word in code font.  This markup
# is similar in spirit to that used on WikiWiki webs, where folks create web
# pages using a simple set of formatting rules.
#
# RDoc::Markup and other markup formats do no output formatting, this is
# handled by the RDoc::Markup::Formatter subclasses.
#
# = Supported Formats
#
# Besides the RDoc::Markup format, the following formats are built in to RDoc:
#
# markdown::
#   The markdown format as described by
#   http://daringfireball.net/projects/markdown/.  See RDoc::Markdown for
#   details on the parser and supported extensions.
# rd::
#   The rdtool format.  See RDoc::RD for details on the parser and format.
# tomdoc::
#   The TomDoc format as described by http://tomdoc.org/.  See RDoc::TomDoc
#   for details on the parser and supported extensions.
#
# You can choose a markup format using the following methods:
#
# per project::
#   If you build your documentation with rake use RDoc::Task#markup.
#
#   If you build your documentation by hand run:
#
#      rdoc --markup your_favorite_format --write-options
#
#   and commit <tt>.rdoc_options</tt> and ship it with your packaged gem.
# per file::
#   At the top of the file use the <tt>:markup:</tt> directive to set the
#   default format for the rest of the file.
# per comment::
#   Use the <tt>:markup:</tt> directive at the top of a comment you want
#   to write in a different format.
#
# = RDoc::Markup
#
# RDoc::Markup is extensible at runtime: you can add \new markup elements to
# be recognized in the documents that RDoc::Markup parses.
#
# RDoc::Markup is intended to be the basis for a family of tools which share
# the common requirement that simple, plain-text should be rendered in a
# variety of different output formats and media.  It is envisaged that
# RDoc::Markup could be the basis for formatting RDoc style comment blocks,
# Wiki entries, and online FAQs.
#
# == Synopsis
#
# This code converts +input_string+ to HTML.  The conversion takes place in
# the +convert+ method, so you can use the same RDoc::Markup converter to
# convert multiple input strings.
#
#   require 'rdoc'
#
#   h = RDoc::Markup::ToHtml.new(RDoc::Options.new)
#
#   puts h.convert(input_string)
#
# You can extend the RDoc::Markup parser to recognize new markup
# sequences, and to add regexp handling. Here we make WikiWords significant to
# the parser, and also make the sequences {word} and \<no>text...</no> signify
# strike-through text.  We then subclass the HTML output class to deal
# with these:
#
#   require 'rdoc'
#
#   class WikiHtml < RDoc::Markup::ToHtml
#     def handle_regexp_WIKIWORD(target)
#       "<font color=red>" + target.text + "</font>"
#     end
#   end
#
#   markup = RDoc::Markup.new
#   markup.add_word_pair("{", "}", :STRIKE)
#   markup.add_html("no", :STRIKE)
#
#   markup.add_regexp_handling(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
#
#   wh = WikiHtml.new RDoc::Options.new, markup
#   wh.add_tag(:STRIKE, "<strike>", "</strike>")
#
#   puts "<body>#{wh.convert ARGF.read}</body>"
#
# == Encoding
#
# Where Encoding support is available, RDoc will automatically convert all
# documents to the same output encoding.  The output encoding can be set via
# RDoc::Options#encoding and defaults to Encoding.default_external.
#
# = \RDoc Markup Reference
#
# See RDoc::MarkupReference.
#
#--
# Original Author:: Dave Thomas,  dave@pragmaticprogrammer.com
# License:: Ruby license

class RDoc::Markup

  ##
  # An AttributeManager which handles inline markup.

  attr_reader :attribute_manager

  ##
  # Parses +str+ into an RDoc::Markup::Document.

  def self.parse str
    RDoc::Markup::Parser.parse str
  rescue RDoc::Markup::Parser::Error => e
    $stderr.puts <<-EOF
While parsing markup, RDoc encountered a #{e.class}:

#{e}
\tfrom #{e.backtrace.join "\n\tfrom "}

---8<---
#{text}
---8<---

RDoc #{RDoc::VERSION}

Ruby #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL} #{RUBY_RELEASE_DATE}

Please file a bug report with the above information at:

https://github.com/ruby/rdoc/issues

    EOF
    raise
  end

  ##
  # Take a block of text and use various heuristics to determine its
  # structure (paragraphs, lists, and so on).  Invoke an event handler as we
  # identify significant chunks.

  def initialize attribute_manager = nil
    @attribute_manager = attribute_manager || RDoc::Markup::AttributeManager.new
    @output = nil
  end

  ##
  # Add to the sequences used to add formatting to an individual word (such
  # as *bold*).  Matching entries will generate attributes that the output
  # formatters can recognize by their +name+.

  def add_word_pair(start, stop, name)
    @attribute_manager.add_word_pair(start, stop, name)
  end

  ##
  # Add to the sequences recognized as general markup.

  def add_html(tag, name)
    @attribute_manager.add_html(tag, name)
  end

  ##
  # Add to other inline sequences.  For example, we could add WikiWords using
  # something like:
  #
  #    parser.add_regexp_handling(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
  #
  # Each wiki word will be presented to the output formatter.

  def add_regexp_handling(pattern, name)
    @attribute_manager.add_regexp_handling(pattern, name)
  end

  ##
  # We take +input+, parse it if necessary, then invoke the output +formatter+
  # using a Visitor to render the result.

  def convert input, formatter
    document = case input
               when RDoc::Markup::Document then
                 input
               else
                 RDoc::Markup::Parser.parse input
               end

    document.accept formatter
  end

  autoload :Parser,                "#{__dir__}/markup/parser"
  autoload :PreProcess,            "#{__dir__}/markup/pre_process"

  # Inline markup classes
  autoload :AttrChanger,           "#{__dir__}/markup/attr_changer"
  autoload :AttrSpan,              "#{__dir__}/markup/attr_span"
  autoload :Attributes,            "#{__dir__}/markup/attributes"
  autoload :AttributeManager,      "#{__dir__}/markup/attribute_manager"
  autoload :RegexpHandling,        "#{__dir__}/markup/regexp_handling"

  # RDoc::Markup AST
  autoload :BlankLine,             "#{__dir__}/markup/blank_line"
  autoload :BlockQuote,            "#{__dir__}/markup/block_quote"
  autoload :Document,              "#{__dir__}/markup/document"
  autoload :HardBreak,             "#{__dir__}/markup/hard_break"
  autoload :Heading,               "#{__dir__}/markup/heading"
  autoload :Include,               "#{__dir__}/markup/include"
  autoload :IndentedParagraph,     "#{__dir__}/markup/indented_paragraph"
  autoload :List,                  "#{__dir__}/markup/list"
  autoload :ListItem,              "#{__dir__}/markup/list_item"
  autoload :Paragraph,             "#{__dir__}/markup/paragraph"
  autoload :Table,                 "#{__dir__}/markup/table"
  autoload :Raw,                   "#{__dir__}/markup/raw"
  autoload :Rule,                  "#{__dir__}/markup/rule"
  autoload :Verbatim,              "#{__dir__}/markup/verbatim"

  # Formatters
  autoload :Formatter,             "#{__dir__}/markup/formatter"

  autoload :ToAnsi,                "#{__dir__}/markup/to_ansi"
  autoload :ToBs,                  "#{__dir__}/markup/to_bs"
  autoload :ToHtml,                "#{__dir__}/markup/to_html"
  autoload :ToHtmlCrossref,        "#{__dir__}/markup/to_html_crossref"
  autoload :ToHtmlSnippet,         "#{__dir__}/markup/to_html_snippet"
  autoload :ToLabel,               "#{__dir__}/markup/to_label"
  autoload :ToMarkdown,            "#{__dir__}/markup/to_markdown"
  autoload :ToRdoc,                "#{__dir__}/markup/to_rdoc"
  autoload :ToTableOfContents,     "#{__dir__}/markup/to_table_of_contents"
  autoload :ToTest,                "#{__dir__}/markup/to_test"
  autoload :ToTtOnly,              "#{__dir__}/markup/to_tt_only"

end
