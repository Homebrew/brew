# frozen_string_literal: false
require "rexml/document"
require "rexml/streamlistener"

module RSS

  class REXMLParser < BaseParser

    class << self
      def listener
        REXMLListener
      end
    end

    private
    def _parse
      begin
        REXML::Document.parse_stream(@rss, @listener)
      rescue RuntimeError => e
        raise NotWellFormedError.new{e.message}
      rescue REXML::ParseException => e
        context = e.context
        line = context[0] if context
        raise NotWellFormedError.new(line){e.message}
      end
    end

  end

  class REXMLListener < BaseListener

    include REXML::StreamListener
    include ListenerMixin

    class << self
      def raise_for_undefined_entity?
        false
      end
    end

    def xmldecl(version, encoding, standalone)
      super(version, encoding, standalone == "yes")
      # Encoding is converted to UTF-8 when REXML parse XML.
      @encoding = 'UTF-8'
    end

    alias_method(:cdata, :text)
  end

end
