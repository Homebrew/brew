# frozen_string_literal: true
##
# Handle common directives that can occur in a block of text:
#
#   \:include: filename
#
# Directives can be escaped by preceding them with a backslash.
#
# RDoc plugin authors can register additional directives to be handled by
# using RDoc::Markup::PreProcess::register.
#
# Any directive that is not built-in to RDoc (including those registered via
# plugins) will be stored in the metadata hash on the CodeObject the comment
# is attached to.  See RDoc::Markup@Directives for the list of built-in
# directives.

class RDoc::Markup::PreProcess

  ##
  # An RDoc::Options instance that will be filled in with overrides from
  # directives

  attr_accessor :options

  ##
  # Adds a post-process handler for directives.  The handler will be called
  # with the result RDoc::Comment (or text String) and the code object for the
  # comment (if any).

  def self.post_process &block
    @post_processors << block
  end

  ##
  # Registered post-processors

  def self.post_processors
    @post_processors
  end

  ##
  # Registers +directive+ as one handled by RDoc.  If a block is given the
  # directive will be replaced by the result of the block, otherwise the
  # directive will be removed from the processed text.
  #
  # The block will be called with the directive name and the directive
  # parameter:
  #
  #   RDoc::Markup::PreProcess.register 'my-directive' do |directive, param|
  #     # replace text, etc.
  #   end

  def self.register directive, &block
    @registered[directive] = block
  end

  ##
  # Registered directives

  def self.registered
    @registered
  end

  ##
  # Clears all registered directives and post-processors

  def self.reset
    @post_processors = []
    @registered = {}
  end

  reset

  ##
  # Creates a new pre-processor for +input_file_name+ that will look for
  # included files in +include_path+

  def initialize(input_file_name, include_path)
    @input_file_name = input_file_name
    @include_path = include_path
    @options = nil
  end

  ##
  # Look for directives in the given +text+.
  #
  # Options that we don't handle are yielded.  If the block returns false the
  # directive is restored to the text.  If the block returns nil or no block
  # was given the directive is handled according to the registered directives.
  # If a String was returned the directive is replaced with the string.
  #
  # If no matching directive was registered the directive is restored to the
  # text.
  #
  # If +code_object+ is given and the directive is unknown then the
  # directive's parameter is set as metadata on the +code_object+.  See
  # RDoc::CodeObject#metadata for details.

  def handle text, code_object = nil, &block
    if RDoc::Comment === text then
      comment = text
      text = text.text
    end

    # regexp helper (square brackets for optional)
    # $1      $2  $3        $4      $5
    # [prefix][\]:directive:[spaces][param]newline
    text = text.gsub(/^([ \t]*(?:#|\/?\*)?[ \t]*)(\\?):(\w+):([ \t]*)(.+)?(\r?\n|$)/) do
      # skip something like ':toto::'
      next $& if $4.empty? and $5 and $5[0, 1] == ':'

      # skip if escaped
      next "#$1:#$3:#$4#$5\n" unless $2.empty?

      # This is not in handle_directive because I didn't want to pass another
      # argument into it
      if comment and $3 == 'markup' then
        next "#{$1.strip}\n" unless $5
        comment.format = $5.downcase
        next "#{$1.strip}\n"
      end

      handle_directive $1, $3, $5, code_object, text.encoding, &block
    end

    if comment then
      comment.text = text
    else
      comment = text
    end

    self.class.post_processors.each do |handler|
      handler.call comment, code_object
    end

    text
  end

  ##
  # Performs the actions described by +directive+ and its parameter +param+.
  #
  # +code_object+ is used for directives that operate on a class or module.
  # +prefix+ is used to ensure the replacement for handled directives is
  # correct.  +encoding+ is used for the <tt>include</tt> directive.
  #
  # For a list of directives in RDoc see RDoc::Markup.
  #--
  # When 1.8.7 support is ditched prefix can be defaulted to ''

  def handle_directive prefix, directive, param, code_object = nil,
                       encoding = nil
    blankline = "#{prefix.strip}\n"
    directive = directive.downcase

    case directive
    when 'arg', 'args' then
      return "#{prefix}:#{directive}: #{param}\n" unless code_object && code_object.kind_of?(RDoc::AnyMethod)

      code_object.params = param

      blankline
    when 'category' then
      if RDoc::Context === code_object then
        section = code_object.add_section param
        code_object.temporary_section = section
      elsif RDoc::AnyMethod === code_object then
        code_object.section_title = param
      end

      blankline # ignore category if we're not on an RDoc::Context
    when 'doc' then
      return blankline unless code_object
      code_object.document_self = true
      code_object.force_documentation = true

      blankline
    when 'enddoc' then
      return blankline unless code_object
      code_object.done_documenting = true

      blankline
    when 'include' then
      filename = param.split(' ', 2).first
      include_file filename, prefix, encoding
    when 'main' then
      @options.main_page = param if @options.respond_to? :main_page

      blankline
    when 'nodoc' then
      return blankline unless code_object
      code_object.document_self = nil # notify nodoc
      code_object.document_children = param !~ /all/i

      blankline
    when 'notnew', 'not_new', 'not-new' then
      return blankline unless RDoc::AnyMethod === code_object

      code_object.dont_rename_initialize = true

      blankline
    when 'startdoc' then
      return blankline unless code_object

      code_object.start_doc
      code_object.force_documentation = true

      blankline
    when 'stopdoc' then
      return blankline unless code_object

      code_object.stop_doc

      blankline
    when 'title' then
      @options.default_title = param if @options.respond_to? :default_title=

      blankline
    when 'yield', 'yields' then
      return blankline unless code_object
      # remove parameter &block
      code_object.params = code_object.params.sub(/,?\s*&\w+/, '') if code_object.params

      code_object.block_params = param

      blankline
    else
      result = yield directive, param if block_given?

      case result
      when nil then
        code_object.metadata[directive] = param if code_object

        if RDoc::Markup::PreProcess.registered.include? directive then
          handler = RDoc::Markup::PreProcess.registered[directive]
          result = handler.call directive, param if handler
        else
          result = "#{prefix}:#{directive}: #{param}\n"
        end
      when false then
        result = "#{prefix}:#{directive}: #{param}\n"
      end

      result
    end
  end

  ##
  # Handles the <tt>:include: _filename_</tt> directive.
  #
  # If the first line of the included file starts with '#', and contains
  # an encoding information in the form 'coding:' or 'coding=', it is
  # removed.
  #
  # If all lines in the included file start with a '#', this leading '#'
  # is removed before inclusion. The included content is indented like
  # the <tt>:include:</tt> directive.
  #--
  # so all content will be verbatim because of the likely space after '#'?
  # TODO shift left the whole file content in that case
  # TODO comment stop/start #-- and #++ in included file must be processed here

  def include_file name, indent, encoding
    full_name = find_include_file name

    unless full_name then
      warn "Couldn't find file to include '#{name}' from #{@input_file_name}"
      return ''
    end

    content = RDoc::Encoding.read_file full_name, encoding, true
    content = RDoc::Encoding.remove_magic_comment content

    # strip magic comment
    content = content.sub(/\A# .*coding[=:].*$/, '').lstrip

    # strip leading '#'s, but only if all lines start with them
    if content =~ /^[^#]/ then
      content.gsub(/^/, indent)
    else
      content.gsub(/^#?/, indent)
    end
  end

  ##
  # Look for the given file in the directory containing the current file,
  # and then in each of the directories specified in the RDOC_INCLUDE path

  def find_include_file(name)
    to_search = [File.dirname(@input_file_name)].concat @include_path
    to_search.each do |dir|
      full_name = File.join(dir, name)
      stat = File.stat(full_name) rescue next
      return full_name if stat.readable?
    end
    nil
  end

end
