# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/syndication"

module RSS
  class TestSyndication < TestCase

    def setup
      @prefix = "sy"
      @uri = "http://purl.org/rss/1.0/modules/syndication/"

      @parents = %w(channel)

      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end

      @elems = {
        :updatePeriod => "hourly",
        :updateFrequency => "2",
        :updateBase => t,
      }

      @sy_nodes = @elems.collect do |name, value|
        "<#{@prefix}:#{name}>#{CGI.escapeHTML(value.to_s)}</#{@prefix}:#{name}>"
      end.join("\n")

      @rss_source = make_RDF(<<-EOR, {@prefix =>  @uri})
#{make_channel(@sy_nodes)}
#{make_image()}
#{make_item()}
#{make_textinput()}
EOR

      @rss = Parser.parse(@rss_source)
    end

    def test_parser

      assert_nothing_raised do
        Parser.parse(@rss_source)
      end

      @elems.each do |tag, value|
        assert_too_much_tag(tag.to_s, "channel") do
          Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel(("<" + @prefix + ":" + tag.to_s + ">" +
  CGI.escapeHTML(value.to_s) +
  "</" + @prefix + ":" + tag.to_s + ">") * 2)}
#{make_item}
EOR
        end
      end

    end

    def test_accessor

      t = Time.iso8601("2003-01-01T12:00:23+09:00")
      class << t
        alias_method(:to_s, :iso8601)
      end

      new_value = {
        :updatePeriod => "daily",
        :updateFrequency => "11",
        :updateBase => t,
      }

      @elems.each do |name, value|
        value = value.to_i if name == :updateFrequency
        @parents.each do |parent|
          assert_equal(value, @rss.__send__(parent).__send__("sy_#{name}"))
          @rss.__send__(parent).__send__("sy_#{name}=", new_value[name])
          new_val = new_value[name]
          new_val = new_val.to_i if name == :updateFrequency
          assert_equal(new_val, @rss.__send__(parent).__send__("sy_#{name}"))
        end
      end

      %w(hourly daily weekly monthly yearly).each do |x|
        @parents.each do |parent|
          assert_nothing_raised do
            @rss.__send__(parent).sy_updatePeriod = x
          end
        end
      end

      %w(-2 0.3 -0.4).each do |x|
        @parents.each do |parent|
          assert_not_available_value("sy:updateBase", x) do
            @rss.__send__(parent).sy_updateBase = x
          end
        end
      end

    end

    def test_to_s

      @elems.each do |name, value|
        excepted = "<#{@prefix}:#{name}>#{value}</#{@prefix}:#{name}>"
        @parents.each do |parent|
          assert_equal(excepted,
                       @rss.__send__(parent).__send__("sy_#{name}_element"))
        end
      end

      REXML::Document.new(@rss_source).root.each_element do |parent|
        if @parents.include?(parent.name)
          parent.each_element do |elem|
            if elem.namespace == @uri
              assert_equal(elem.text, @elems[elem.name.intern].to_s)
            end
          end
        end
      end
    end
  end
end
