# frozen_string_literal: false
begin
  require "xml/parser"
rescue LoadError
  require "xmlparser"
end

begin
  require "xml/encoding-ja"
rescue LoadError
  require "xmlencoding-ja"
  if defined?(Kconv)
    module XMLEncoding_ja
      class SJISHandler
        include Kconv
      end
    end
  end
end

module XML
  class Parser
    unless defined?(Error)
      # This error is legacy, so we just set it to the new one
      Error = ::XMLParserError # :nodoc:
    end
  end
end

module RSS

  class REXMLLikeXMLParser < ::XML::Parser

    include ::XML::Encoding_ja

    def listener=(listener)
      @listener = listener
    end

    def startElement(name, attrs)
      @listener.tag_start(name, attrs)
    end

    def endElement(name)
      @listener.tag_end(name)
    end

    def character(data)
      @listener.text(data)
    end

    def xmlDecl(version, encoding, standalone)
      @listener.xmldecl(version, encoding, standalone == 1)
    end

    def processingInstruction(target, content)
      @listener.instruction(target, content)
    end

  end

  class XMLParserParser < BaseParser

    class << self
      def listener
        XMLParserListener
      end
    end

    private
    def _parse
      begin
        parser = REXMLLikeXMLParser.new
        parser.listener = @listener
        parser.parse(@rss)
      rescue ::XML::Parser::Error => e
        raise NotWellFormedError.new(parser.line){e.message}
      end
    end

  end

  class XMLParserListener < BaseListener

    include ListenerMixin

    def xmldecl(version, encoding, standalone)
      super
      # Encoding is converted to UTF-8 when XMLParser parses XML.
      @encoding = 'UTF-8'
    end

  end

end
