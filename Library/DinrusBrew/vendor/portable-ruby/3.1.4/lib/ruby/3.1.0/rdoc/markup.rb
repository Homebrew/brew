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
# == Block Markup
#
# === Paragraphs and Verbatim
#
# The markup engine looks for a document's natural left margin.  This is
# used as the initial margin for the document.
#
# Consecutive lines starting at this margin are considered to be a
# paragraph. Empty lines separate paragraphs.
#
# Any line that starts to the right of the current margin is treated
# as verbatim text.  This is useful for code listings:
#
#   3.times { puts "Ruby" }
#
# In verbatim text, two or more blank lines are collapsed into one,
# and trailing blank lines are removed:
#
#   This is the first line
#
#
#   This is the second non-blank line,
#   after 2 blank lines in the source markup.
#
#
# There were two trailing blank lines right above this paragraph, that
# have been removed. In addition, the verbatim text has been shifted
# left, so the amount of indentation of verbatim text is unimportant.
#
# For HTML output RDoc makes a small effort to determine if a verbatim section
# contains Ruby source code.  If so, the verbatim block will be marked up as
# HTML.  Triggers include "def", "class", "module", "require", the "hash
# rocket"# (=>) or a block call with a parameter.
#
# === Headers
#
# A line starting with an equal sign (=) is treated as a
# heading.  Level one headings have one equals sign, level two headings
# have two, and so on until level six, which is the maximum
# (seven hyphens or more result in a level six heading).
#
# For example, the above header was obtained with:
#
#   === Headers
#
# In HTML output headers have an id matching their name.  The above example's
# HTML is:
#
#   <h3 id="label-Headers">Headers</h3>
#
# If a heading is inside a method body the id will be prefixed with the
# method's id.  If the above header where in the documentation for a method
# such as:
#
#   ##
#   # This method does fun things
#   #
#   # = Example
#   #
#   #   Example of fun things goes here ...
#
#   def do_fun_things
#   end
#
# The header's id would be:
#
#   <h1 id="method-i-do_fun_things-label-Example">Example</h1>
#
# The label can be linked-to using <tt>SomeClass@Headers</tt>.  See
# {Links}[RDoc::Markup@Links] for further details.
#
# === Rules
#
# A line starting with three or more hyphens (at the current indent)
# generates a horizontal rule.
#
#   ---
#
# produces:
#
# ---
#
# === Simple Lists
#
# If a paragraph starts with a "*", "-", "<digit>." or "<letter>.",
# then it is taken to be the start of a list.  The margin is increased to be
# the first non-space following the list start flag.  Subsequent lines
# should be indented to this new margin until the list ends.  For example:
#
#   * this is a list with three paragraphs in
#     the first item.  This is the first paragraph.
#
#     And this is the second paragraph.
#
#     1. This is an indented, numbered list.
#     2. This is the second item in that list
#
#     This is the third conventional paragraph in the
#     first list item.
#
#   * This is the second item in the original list
#
# produces:
#
# * this is a list with three paragraphs in
#   the first item.  This is the first paragraph.
#
#   And this is the second paragraph.
#
#   1. This is an indented, numbered list.
#   2. This is the second item in that list
#
#   This is the third conventional paragraph in the
#   first list item.
#
# * This is the second item in the original list
#
# === Labeled Lists
#
# You can also construct labeled lists, sometimes called description
# or definition lists.  Do this by putting the label in square brackets
# and indenting the list body:
#
#   [cat]  a small furry mammal
#          that seems to sleep a lot
#
#   [ant]  a little insect that is known
#          to enjoy picnics
#
# produces:
#
# [cat]  a small furry mammal
#        that seems to sleep a lot
#
# [ant]  a little insect that is known
#        to enjoy picnics
#
# If you want the list bodies to line up to the left of the labels,
# use two colons:
#
#   cat::  a small furry mammal
#          that seems to sleep a lot
#
#   ant::  a little insect that is known
#          to enjoy picnics
#
# produces:
#
# cat::  a small furry mammal
#        that seems to sleep a lot
#
# ant::  a little insect that is known
#        to enjoy picnics
#
# Notice that blank lines right after the label are ignored in labeled lists:
#
#   [one]
#
#       definition 1
#
#   [two]
#
#       definition 2
#
# produces the same output as
#
#   [one]  definition 1
#   [two]  definition 2
#
#
# === Lists and Verbatim
#
# If you want to introduce a verbatim section right after a list, it has to be
# less indented than the list item bodies, but more indented than the list
# label, letter, digit or bullet. For instance:
#
#   *   point 1
#
#   *   point 2, first paragraph
#
#       point 2, second paragraph
#         verbatim text inside point 2
#       point 2, third paragraph
#     verbatim text outside of the list (the list is therefore closed)
#   regular paragraph after the list
#
# produces:
#
# *   point 1
#
# *   point 2, first paragraph
#
#     point 2, second paragraph
#       verbatim text inside point 2
#     point 2, third paragraph
#   verbatim text outside of the list (the list is therefore closed)
# regular paragraph after the list
#
# == Text Markup
#
# === Bold, Italic, Typewriter Text
#
# You can use markup within text (except verbatim) to change the
# appearance of parts of that text.  Out of the box, RDoc::Markup
# supports word-based and general markup.
#
# Word-based markup uses flag characters around individual words:
#
# <tt>\*_word_\*</tt>::  displays _word_ in a *bold* font
# <tt>\__word_\_</tt>::  displays _word_ in an _emphasized_ font
# <tt>\+_word_\+</tt>::  displays _word_ in a +code+ font
#
# General markup affects text between a start delimiter and an end
# delimiter.  Not surprisingly, these delimiters look like HTML markup.
#
# <tt>\<b>_text_</b></tt>::    displays _text_ in a *bold* font
# <tt>\<em>_text_</em></tt>::  displays _text_ in an _emphasized_ font
#                              (alternate tag: <tt>\<i></tt>)
# <tt>\<tt>_text_\</tt></tt>:: displays _text_ in a +code+ font
#                              (alternate tag: <tt>\<code></tt>)
#
# Unlike conventional Wiki markup, general markup can cross line
# boundaries.  You can turn off the interpretation of markup by
# preceding the first character with a backslash (see <i>Escaping
# Text Markup</i>, below).
#
# === Links
#
# Links to starting with +http:+, +https:+, +mailto:+, +ftp:+ or +www.+
# are recognized.  An HTTP url that references an external image is converted
# into an inline image element.
#
# Classes and methods will be automatically linked to their definition.  For
# example, <tt>RDoc::Markup</tt> will link to this documentation.  By default
# methods will only be automatically linked if they contain an <tt>_</tt> (all
# methods can be automatically linked through the <tt>--hyperlink-all</tt>
# command line option).
#
# Single-word methods can be linked by using the <tt>#</tt> character for
# instance methods or <tt>::</tt> for class methods.  For example,
# <tt>#convert</tt> links to #convert.  A class or method may be combined like
# <tt>RDoc::Markup#convert</tt>.
#
# A heading inside the documentation can be linked by following the class
# or method by an <tt>@</tt> then the heading name.
# <tt>RDoc::Markup@Links</tt> will link to this section like this:
# RDoc::Markup@Links.  Spaces in headings with multiple words must be escaped
# with <tt>+</tt> like <tt>RDoc::Markup@Escaping+Text+Markup</tt>.
# Punctuation and other special characters must be escaped like CGI.escape.
#
# The <tt>@</tt> can also be used to link to sections.  If a section and a
# heading share the same name the section is preferred for the link.
#
# Links can also be of the form <tt>label[url]</tt>, in which case +label+ is
# used in the displayed text, and +url+ is used as the target.  If +label+
# contains multiple words, put it in braces: <tt>{multi word label}[url]</tt>.
# The +url+ may be an +http:+-type link or a cross-reference to a class,
# module or method with a label.
#
# Links with the <code>rdoc-image:</code> scheme will create an image tag for
# HTML output.  Only fully-qualified URLs are supported.
#
# Links with the <tt>rdoc-ref:</tt> scheme will link to the referenced class,
# module, method, file, etc.  If the referenced item is does not exist
# no link will be generated and <tt>rdoc-ref:</tt> will be removed from the
# resulting text.
#
# Links starting with <tt>rdoc-label:label_name</tt> will link to the
# +label_name+.  You can create a label for the current link (for
# bidirectional links) by supplying a name for the current link like
# <tt>rdoc-label:label-other:label-mine</tt>.
#
# Links starting with +link:+ refer to local files whose path is relative to
# the <tt>--op</tt> directory.  Use <tt>rdoc-ref:</tt> instead of
# <tt>link:</tt> to link to files generated by RDoc as the link target may
# be different across RDoc generators.
#
# Example links:
#
#   https://github.com/ruby/rdoc
#   mailto:user@example.com
#   {RDoc Documentation}[http://rdoc.rubyforge.org]
#   {RDoc Markup}[rdoc-ref:RDoc::Markup]
#
# === Escaping Text Markup
#
# Text markup can be escaped with a backslash, as in \<tt>, which was obtained
# with <tt>\\<tt></tt>.  Except in verbatim sections and between \<tt> tags,
# to produce a backslash you have to double it unless it is followed by a
# space, tab or newline. Otherwise, the HTML formatter will discard it, as it
# is used to escape potential links:
#
#   * The \ must be doubled if not followed by white space: \\.
#   * But not in \<tt> tags: in a Regexp, <tt>\S</tt> matches non-space.
#   * This is a link to {ruby-lang}[www.ruby-lang.org].
#   * This is not a link, however: \{ruby-lang.org}[www.ruby-lang.org].
#   * This will not be linked to \RDoc::RDoc#document
#
# generates:
#
# * The \ must be doubled if not followed by white space: \\.
# * But not in \<tt> tags: in a Regexp, <tt>\S</tt> matches non-space.
# * This is a link to {ruby-lang}[www.ruby-lang.org]
# * This is not a link, however: \{ruby-lang.org}[www.ruby-lang.org]
# * This will not be linked to \RDoc::RDoc#document
#
# Inside \<tt> tags, more precisely, leading backslashes are removed only if
# followed by a markup character (<tt><*_+</tt>), a backslash, or a known link
# reference (a known class or method). So in the example above, the backslash
# of <tt>\S</tt> would be removed if there was a class or module named +S+ in
# the current context.
#
# This behavior is inherited from RDoc version 1, and has been kept for
# compatibility with existing RDoc documentation.
#
# === Conversion of characters
#
# HTML will convert two/three dashes to an em-dash. Other common characters are
# converted as well:
#
#   em-dash::  -- or ---
#   ellipsis:: ...
#
#   single quotes:: 'text' or `text'
#   double quotes:: "text" or ``text''
#
#   copyright:: (c)
#   registered trademark:: (r)
#
# produces:
#
# em-dash::  -- or ---
# ellipsis:: ...
#
# single quotes:: 'text' or `text'
# double quotes:: "text" or ``text''
#
# copyright:: (c)
# registered trademark:: (r)
#
#
# == Documenting Source Code
#
# Comment blocks can be written fairly naturally, either using <tt>#</tt> on
# successive lines of the comment, or by including the comment in
# a <tt>=begin</tt>/<tt>=end</tt> block.  If you use the latter form,
# the <tt>=begin</tt> line _must_ be flagged with an +rdoc+ tag:
#
#   =begin rdoc
#   Documentation to be processed by RDoc.
#
#   ...
#   =end
#
# RDoc stops processing comments if it finds a comment line starting
# with <tt>--</tt> right after the <tt>#</tt> character (otherwise,
# it will be treated as a rule if it has three dashes or more).
# This can be used to separate external from internal comments,
# or to stop a comment being associated with a method, class, or module.
# Commenting can be turned back on with a line that starts with <tt>++</tt>.
#
#   ##
#   # Extract the age and calculate the date-of-birth.
#   #--
#   # FIXME: fails if the birthday falls on February 29th
#   #++
#   # The DOB is returned as a Time object.
#
#   def get_dob(person)
#     # ...
#   end
#
# Names of classes, files, and any method names containing an underscore or
# preceded by a hash character are automatically linked from comment text to
# their description. This linking works inside the current class or module,
# and with ancestor methods (in included modules or in the superclass).
#
# Method parameter lists are extracted and displayed with the method
# description.  If a method calls +yield+, then the parameters passed to yield
# will also be displayed:
#
#   def fred
#     ...
#     yield line, address
#
# This will get documented as:
#
#   fred() { |line, address| ... }
#
# You can override this using a comment containing ':yields: ...' immediately
# after the method definition
#
#   def fred # :yields: index, position
#     # ...
#
#     yield line, address
#
# which will get documented as
#
#    fred() { |index, position| ... }
#
# +:yields:+ is an example of a documentation directive.  These appear
# immediately after the start of the document element they are modifying.
#
# RDoc automatically cross-references words with underscores or camel-case.
# To suppress cross-references, prefix the word with a \ character.  To
# include special characters like "<tt>\n</tt>", you'll need to use
# two \ characters in normal text, but only one in \<tt> text:
#
#   "\\n" or "<tt>\n</tt>"
#
# produces:
#
# "\\n" or "<tt>\n</tt>"
#
# == Directives
#
# Directives are keywords surrounded by ":" characters.
#
# === Controlling what is documented
#
# [+:nodoc:+ / <tt>:nodoc: all</tt>]
#   This directive prevents documentation for the element from
#   being generated.  For classes and modules, methods, aliases,
#   constants, and attributes directly within the affected class or
#   module also will be omitted.  By default, though, modules and
#   classes within that class or module _will_ be documented.  This is
#   turned off by adding the +all+ modifier.
#
#     module MyModule # :nodoc:
#       class Input
#       end
#     end
#
#     module OtherModule # :nodoc: all
#       class Output
#       end
#     end
#
#   In the above code, only class <tt>MyModule::Input</tt> will be documented.
#
#   The +:nodoc:+ directive, like +:enddoc:+, +:stopdoc:+ and +:startdoc:+
#   presented below, is local to the current file: if you do not want to
#   document a module that appears in several files, specify +:nodoc:+ on each
#   appearance, at least once per file.
#
# [+:stopdoc:+ / +:startdoc:+]
#   Stop and start adding new documentation elements to the current container.
#   For example, if a class has a number of constants that you don't want to
#   document, put a +:stopdoc:+ before the first, and a +:startdoc:+ after the
#   last.  If you don't specify a +:startdoc:+ by the end of the container,
#   disables documentation for the rest of the current file.
#
# [+:doc:+]
#   Forces a method or attribute to be documented even if it wouldn't be
#   otherwise.  Useful if, for example, you want to include documentation of a
#   particular private method.
#
# [+:enddoc:+]
#   Document nothing further at the current level: directives +:startdoc:+ and
#   +:doc:+ that appear after this will not be honored for the current container
#   (file, class or module), in the current file.
#
# [+:notnew:+ / +:not_new:+ / +:not-new:+ ]
#   Only applicable to the +initialize+ instance method.  Normally RDoc
#   assumes that the documentation and parameters for +initialize+ are
#   actually for the +new+ method, and so fakes out a +new+ for the class.
#   The +:notnew:+ directive stops this.  Remember that +initialize+ is private,
#   so you won't see the documentation unless you use the +-a+ command line
#   option.
#
# === Method arguments
#
# [+:arg:+ or +:args:+ _parameters_]
#   Overrides the default argument handling with exactly these parameters.
#
#     ##
#     #  :args: a, b
#
#     def some_method(*a)
#     end
#
# [+:yield:+ or +:yields:+ _parameters_]
#   Overrides the default yield discovery with these parameters.
#
#     ##
#     # :yields: key, value
#
#     def each_thing &block
#       @things.each(&block)
#     end
#
# [+:call-seq:+]
#   Lines up to the next blank line or lines with a common prefix in the
#   comment are treated as the method's calling sequence, overriding the
#   default parsing of method parameters and yield arguments.
#
#   Multiple lines may be used.
#
#     # :call-seq:
#     #   ARGF.readlines(sep=$/)     -> array
#     #   ARGF.readlines(limit)      -> array
#     #   ARGF.readlines(sep, limit) -> array
#     #
#     #   ARGF.to_a(sep=$/)     -> array
#     #   ARGF.to_a(limit)      -> array
#     #   ARGF.to_a(sep, limit) -> array
#     #
#     # The remaining lines are documentation ...
#
# === Sections
#
# Sections allow you to group methods in a class into sensible containers.  If
# you use the sections 'Public', 'Internal' and 'Deprecated' (the three
# allowed method statuses from TomDoc) the sections will be displayed in that
# order placing the most useful methods at the top.  Otherwise, sections will
# be displayed in alphabetical order.
#
# [+:category:+ _section_]
#   Adds this item to the named +section+ overriding the current section.  Use
#   this to group methods by section in RDoc output while maintaining a
#   sensible ordering (like alphabetical).
#
#     # :category: Utility Methods
#     #
#     # CGI escapes +text+
#
#     def convert_string text
#       CGI.escapeHTML text
#     end
#
#   An empty category will place the item in the default category:
#
#     # :category:
#     #
#     # This method is in the default category
#
#     def some_method
#       # ...
#     end
#
#   Unlike the :section: directive, :category: is not sticky.  The category
#   only applies to the item immediately following the comment.
#
#   Use the :section: directive to provide introductory text for a section of
#   documentation.
#
# [+:section:+ _title_]
#   Provides section introductory text in RDoc output.  The title following
#   +:section:+ is used as the section name and the remainder of the comment
#   containing the section is used as introductory text.  A section's comment
#   block must be separated from following comment blocks.  Use an empty title
#   to switch to the default section.
#
#   The :section: directive is sticky, so subsequent methods, aliases,
#   attributes, and classes will be contained in this section until the
#   section is changed.  The :category: directive will override the :section:
#   directive.
#
#   A :section: comment block may have one or more lines before the :section:
#   directive.  These will be removed, and any identical lines at the end of
#   the block are also removed.  This allows you to add visual cues to the
#   section.
#
#   Example:
#
#     # ----------------------------------------
#     # :section: My Section
#     # This is the section that I wrote.
#     # See it glisten in the noon-day sun.
#     # ----------------------------------------
#
#     ##
#     # Comment for some_method
#
#     def some_method
#       # ...
#     end
#
# === Other directives
#
# [+:markup:+ _type_]
#   Overrides the default markup type for this comment with the specified
#   markup type.  For Ruby files, if the first comment contains this directive
#   it is applied automatically to all comments in the file.
#
#   Unless you are converting between markup formats you should use a
#   <code>.rdoc_options</code> file to specify the default documentation
#   format for your entire project.  See RDoc::Options@Saved+Options for
#   instructions.
#
#   At the top of a file the +:markup:+ directive applies to the entire file:
#
#     # coding: UTF-8
#     # :markup: TomDoc
#
#     # TomDoc comment here ...
#
#     class MyClass
#       # ...
#
#   For just one comment:
#
#       # ...
#     end
#
#     # :markup: RDoc
#     #
#     # This is a comment in RDoc markup format ...
#
#     def some_method
#       # ...
#
#   See Markup@CONTRIBUTING for instructions on adding a new markup format.
#
# [+:include:+ _filename_]
#   Include the contents of the named file at this point. This directive
#   must appear alone on one line, possibly preceded by spaces. In this
#   position, it can be escaped with a \ in front of the first colon.
#
#   The file will be searched for in the directories listed by the +--include+
#   option, or in the current directory by default.  The contents of the file
#   will be shifted to have the same indentation as the ':' at the start of
#   the +:include:+ directive.
#
# [+:title:+ _text_]
#   Sets the title for the document.  Equivalent to the <tt>--title</tt>
#   command line parameter.  (The command line parameter overrides any :title:
#   directive in the source).
#
# [+:main:+ _name_]
#   Equivalent to the <tt>--main</tt> command line parameter.
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

  autoload :Parser,                'rdoc/markup/parser'
  autoload :PreProcess,            'rdoc/markup/pre_process'

  # Inline markup classes
  autoload :AttrChanger,           'rdoc/markup/attr_changer'
  autoload :AttrSpan,              'rdoc/markup/attr_span'
  autoload :Attributes,            'rdoc/markup/attributes'
  autoload :AttributeManager,      'rdoc/markup/attribute_manager'
  autoload :RegexpHandling,        'rdoc/markup/regexp_handling'

  # RDoc::Markup AST
  autoload :BlankLine,             'rdoc/markup/blank_line'
  autoload :BlockQuote,            'rdoc/markup/block_quote'
  autoload :Document,              'rdoc/markup/document'
  autoload :HardBreak,             'rdoc/markup/hard_break'
  autoload :Heading,               'rdoc/markup/heading'
  autoload :Include,               'rdoc/markup/include'
  autoload :IndentedParagraph,     'rdoc/markup/indented_paragraph'
  autoload :List,                  'rdoc/markup/list'
  autoload :ListItem,              'rdoc/markup/list_item'
  autoload :Paragraph,             'rdoc/markup/paragraph'
  autoload :Table,                 'rdoc/markup/table'
  autoload :Raw,                   'rdoc/markup/raw'
  autoload :Rule,                  'rdoc/markup/rule'
  autoload :Verbatim,              'rdoc/markup/verbatim'

  # Formatters
  autoload :Formatter,             'rdoc/markup/formatter'

  autoload :ToAnsi,                'rdoc/markup/to_ansi'
  autoload :ToBs,                  'rdoc/markup/to_bs'
  autoload :ToHtml,                'rdoc/markup/to_html'
  autoload :ToHtmlCrossref,        'rdoc/markup/to_html_crossref'
  autoload :ToHtmlSnippet,         'rdoc/markup/to_html_snippet'
  autoload :ToLabel,               'rdoc/markup/to_label'
  autoload :ToMarkdown,            'rdoc/markup/to_markdown'
  autoload :ToRdoc,                'rdoc/markup/to_rdoc'
  autoload :ToTableOfContents,     'rdoc/markup/to_table_of_contents'
  autoload :ToTest,                'rdoc/markup/to_test'
  autoload :ToTtOnly,              'rdoc/markup/to_tt_only'

end

