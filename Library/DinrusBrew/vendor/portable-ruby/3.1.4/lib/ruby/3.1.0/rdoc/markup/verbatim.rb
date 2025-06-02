# frozen_string_literal: true
##
# A section of verbatim text

class RDoc::Markup::Verbatim < RDoc::Markup::Raw

  ##
  # Format of this verbatim section

  attr_accessor :format

  def initialize *parts # :nodoc:
    super

    @format = nil
  end

  def == other # :nodoc:
    super and @format == other.format
  end

  ##
  # Calls #accept_verbatim on +visitor+

  def accept visitor
    visitor.accept_verbatim self
  end

  ##
  # Collapses 3+ newlines into two newlines

  def normalize
    parts = []

    newlines = 0

    @parts.each do |part|
      case part
      when /^\s*\n/ then
        newlines += 1
        parts << part if newlines == 1
      else
        newlines = 0
        parts << part
      end
    end

    parts.pop if parts.last =~ /\A\r?\n\z/

    @parts = parts
  end

  def pretty_print q # :nodoc:
    self.class.name =~ /.*::(\w{1,4})/i

    q.group 2, "[#{$1.downcase}: ", ']' do
      if @format then
        q.text "format: #{@format}"
        q.breakable
      end

      q.seplist @parts do |part|
        q.pp part
      end
    end
  end

  ##
  # Is this verbatim section Ruby code?

  def ruby?
    @format ||= nil # TODO for older ri data, switch the tree to marshal_dump
    @format == :ruby
  end

  ##
  # The text of the section

  def text
    @parts.join
  end

end

