# frozen_string_literal: true
##
# A heading with a level (1-6) and text

RDoc::Markup::Heading =
  Struct.new :level, :text do

  @to_html = nil
  @to_label = nil

  ##
  # A singleton RDoc::Markup::ToLabel formatter for headings.

  def self.to_label
    @to_label ||= RDoc::Markup::ToLabel.new
  end

  ##
  # A singleton plain HTML formatter for headings.  Used for creating labels
  # for the Table of Contents

  def self.to_html
    return @to_html if @to_html

    markup = RDoc::Markup.new
    markup.add_regexp_handling RDoc::CrossReference::CROSSREF_REGEXP, :CROSSREF

    @to_html = RDoc::Markup::ToHtml.new nil

    def @to_html.handle_regexp_CROSSREF target
      target.text.sub(/^\\/, '')
    end

    @to_html
  end

  ##
  # Calls #accept_heading on +visitor+

  def accept visitor
    visitor.accept_heading self
  end

  ##
  # An HTML-safe anchor reference for this header.

  def aref
    "label-#{self.class.to_label.convert text.dup}"
  end

  ##
  # Creates a fully-qualified label which will include the label from
  # +context+.  This helps keep ids unique in HTML.

  def label context = nil
    label = aref

    label = [context.aref, label].compact.join '-' if
      context and context.respond_to? :aref

    label
  end

  ##
  # HTML markup of the text of this label without the surrounding header
  # element.

  def plain_html
    self.class.to_html.to_html(text.dup)
  end

  def pretty_print q # :nodoc:
    q.group 2, "[head: #{level} ", ']' do
      q.pp text
    end
  end

end
