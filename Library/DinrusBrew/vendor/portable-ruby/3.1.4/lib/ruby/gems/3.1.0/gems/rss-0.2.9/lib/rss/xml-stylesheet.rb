# frozen_string_literal: false
require_relative "utils"

module RSS

  module XMLStyleSheetMixin
    attr_accessor :xml_stylesheets
    def initialize(*args)
      super
      @xml_stylesheets = []
    end

    private
    def xml_stylesheet_pi
      xsss = @xml_stylesheets.collect do |xss|
        pi = xss.to_s
        pi = nil if /\A\s*\z/ =~ pi
        pi
      end.compact
      xsss.push("") unless xsss.empty?
      xsss.join("\n")
    end
  end

  class XMLStyleSheet

    include Utils

    ATTRIBUTES = %w(href type title media charset alternate)

    GUESS_TABLE = {
      "xsl" => "text/xsl",
      "css" => "text/css",
    }

    attr_accessor(*ATTRIBUTES)
    attr_accessor(:do_validate)
    def initialize(*attrs)
      if attrs.size == 1 and
          (attrs.first.is_a?(Hash) or attrs.first.is_a?(Array))
        attrs = attrs.first
      end
      @do_validate = true
      ATTRIBUTES.each do |attr|
        __send__("#{attr}=", nil)
      end
      vars = ATTRIBUTES.dup
      vars.unshift(:do_validate)
      attrs.each do |name, value|
        if vars.include?(name.to_s)
          __send__("#{name}=", value)
        end
      end
    end

    def to_s
      rv = ""
      if @href
        rv << %Q[<?xml-stylesheet]
        ATTRIBUTES.each do |name|
          if __send__(name)
            rv << %Q[ #{name}="#{h __send__(name)}"]
          end
        end
        rv << %Q[?>]
      end
      rv
    end

    remove_method(:href=)
    def href=(value)
      @href = value
      if @href and @type.nil?
        @type = guess_type(@href)
      end
      @href
    end

    remove_method(:alternate=)
    def alternate=(value)
      if value.nil? or /\A(?:yes|no)\z/ =~ value
        @alternate = value
      else
        if @do_validate
          args = ["?xml-stylesheet?", %Q[alternate="#{value}"]]
          raise NotAvailableValueError.new(*args)
        end
      end
      @alternate
    end

    def setup_maker(maker)
      xss = maker.xml_stylesheets.new_xml_stylesheet
      ATTRIBUTES.each do |attr|
        xss.__send__("#{attr}=", __send__(attr))
      end
    end

    private
    def guess_type(filename)
      /\.([^.]+)$/ =~ filename
      GUESS_TABLE[$1]
    end

  end
end
