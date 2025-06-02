# frozen_string_literal: true
##
# Subclass of the RDoc::Markup::ToHtml class that supports looking up method
# names, classes, etc to create links.  RDoc::CrossReference is used to
# generate those links based on the current context.

class RDoc::Markup::ToHtmlCrossref < RDoc::Markup::ToHtml

  # :stopdoc:
  ALL_CROSSREF_REGEXP = RDoc::CrossReference::ALL_CROSSREF_REGEXP
  CLASS_REGEXP_STR    = RDoc::CrossReference::CLASS_REGEXP_STR
  CROSSREF_REGEXP     = RDoc::CrossReference::CROSSREF_REGEXP
  METHOD_REGEXP_STR   = RDoc::CrossReference::METHOD_REGEXP_STR
  # :startdoc:

  ##
  # RDoc::CodeObject for generating references

  attr_accessor :context

  ##
  # Should we show '#' characters on method references?

  attr_accessor :show_hash

  ##
  # Creates a new crossref resolver that generates links relative to +context+
  # which lives at +from_path+ in the generated files.  '#' characters on
  # references are removed unless +show_hash+ is true.  Only method names
  # preceded by '#' or '::' are linked, unless +hyperlink_all+ is true.

  def initialize(options, from_path, context, markup = nil)
    raise ArgumentError, 'from_path cannot be nil' if from_path.nil?

    super options, markup

    @context       = context
    @from_path     = from_path
    @hyperlink_all = @options.hyperlink_all
    @show_hash     = @options.show_hash

    @cross_reference = RDoc::CrossReference.new @context
  end

  def init_link_notation_regexp_handlings
    add_regexp_handling_RDOCLINK

    # The crossref must be linked before tidylink because Klass.method[:sym]
    # will be processed as a tidylink first and will be broken.
    crossref_re = @options.hyperlink_all ? ALL_CROSSREF_REGEXP : CROSSREF_REGEXP
    @markup.add_regexp_handling crossref_re, :CROSSREF

    add_regexp_handling_TIDYLINK
  end

  ##
  # Creates a link to the reference +name+ if the name exists.  If +text+ is
  # given it is used as the link text, otherwise +name+ is used.

  def cross_reference name, text = nil, code = true
    lookup = name

    name = name[1..-1] unless @show_hash if name[0, 1] == '#'

    if !(name.end_with?('+@', '-@')) and name =~ /(.*[^#:])@/
      text ||= "#{CGI.unescape $'} at <code>#{$1}</code>"
      code = false
    else
      text ||= name
    end

    link lookup, text, code
  end

  ##
  # We're invoked when any text matches the CROSSREF pattern.  If we find the
  # corresponding reference, generate a link.  If the name we're looking for
  # contains no punctuation, we look for it up the module/class chain.  For
  # example, ToHtml is found, even without the <tt>RDoc::Markup::</tt> prefix,
  # because we look for it in module Markup first.

  def handle_regexp_CROSSREF(target)
    name = target.text

    return name if name =~ /@[\w-]+\.[\w-]/ # labels that look like emails

    unless @hyperlink_all then
      # This ensures that words entirely consisting of lowercase letters will
      # not have cross-references generated (to suppress lots of erroneous
      # cross-references to "new" in text, for instance)
      return name if name =~ /\A[a-z]*\z/
    end

    cross_reference name
  end

  ##
  # Handles <tt>rdoc-ref:</tt> scheme links and allows RDoc::Markup::ToHtml to
  # handle other schemes.

  def handle_regexp_HYPERLINK target
    return cross_reference $' if target.text =~ /\Ardoc-ref:/

    super
  end

  ##
  # +target+ is an rdoc-schemed link that will be converted into a hyperlink.
  # For the rdoc-ref scheme the cross-reference will be looked up and the
  # given name will be used.
  #
  # All other contents are handled by
  # {the superclass}[rdoc-ref:RDoc::Markup::ToHtml#handle_regexp_RDOCLINK]

  def handle_regexp_RDOCLINK target
    url = target.text

    case url
    when /\Ardoc-ref:/ then
      cross_reference $'
    else
      super
    end
  end

  ##
  # Generates links for <tt>rdoc-ref:</tt> scheme URLs and allows
  # RDoc::Markup::ToHtml to handle other schemes.

  def gen_url url, text
    return super unless url =~ /\Ardoc-ref:/

    name = $'
    cross_reference name, text, name == text
  end

  ##
  # Creates an HTML link to +name+ with the given +text+.

  def link name, text, code = true
    if !(name.end_with?('+@', '-@')) and name =~ /(.*[^#:])@/
      name = $1
      label = $'
    end

    ref = @cross_reference.resolve name, text

    case ref
    when String then
      ref
    else
      path = ref.as_href @from_path

      if code and RDoc::CodeObject === ref and !(RDoc::TopLevel === ref)
        text = "<code>#{CGI.escapeHTML text}</code>"
      end

      if path =~ /#/ then
        path << "-label-#{label}"
      elsif ref.sections and
            ref.sections.any? { |section| label == section.title } then
        path << "##{label}"
      else
        if ref.respond_to?(:aref)
          path << "##{ref.aref}-label-#{label}"
        else
          path << "#label-#{label}"
        end
      end if label

      "<a href=\"#{path}\">#{text}</a>"
    end
  end

end

