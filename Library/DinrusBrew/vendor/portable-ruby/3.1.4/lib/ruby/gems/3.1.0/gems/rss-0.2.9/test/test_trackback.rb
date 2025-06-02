# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/2.0"
require "rss/trackback"

module RSS
  class TestTrackBack < TestCase

    def setup
      @prefix = "trackback"
      @uri = "http://madskills.com/public/xml/rss/module/trackback/"

      @parents = %w(item)

      @elems = {
        :ping => "http://bar.com/tb.cgi?tb_id=rssplustrackback",
        :about => "http://foo.com/trackback/tb.cgi?tb_id=20020923",
      }

      @content_nodes = @elems.collect do |name, value|
        "<#{@prefix}:#{name} rdf:resource=\"#{CGI.escapeHTML(value.to_s)}\"/>"
      end.join("\n")

      @content_nodes2 = @elems.collect do |name, value|
        "<#{@prefix}:#{name}>#{CGI.escapeHTML(value.to_s)}</#{@prefix}:#{name}>"
      end.join("\n")

      @rss_source = make_RDF(<<-EOR, {@prefix =>  @uri})
#{make_channel()}
#{make_image()}
#{make_item(@content_nodes)}
#{make_textinput()}
EOR

      @rss = Parser.parse(@rss_source)

      @rss20_source = make_rss20(nil, {@prefix =>  @uri}) do
        make_channel20(nil) do
          make_item20(@content_nodes2)
        end
      end

      @rss20 = Parser.parse(@rss20_source, false)
    end

    def test_parser

      assert_nothing_raised do
        Parser.parse(@rss_source)
      end

      @elems.find_all{|k, v| k == :ping}.each do |tag, value|
        assert_too_much_tag(tag.to_s, "item") do
          Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel()}
#{make_item(("<" + @prefix + ":" + tag.to_s + " rdf:resource=\"" +
  CGI.escapeHTML(value.to_s) +
  "\"/>") * 2)}
EOR
        end
      end

      @elems.find_all{|k, v| k == :about}.each do |tag, value|
        assert_missing_tag("trackback:ping", "item") do
          Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel()}
#{make_item(("<" + @prefix + ":" + tag.to_s + " rdf:resource=\"" +
  CGI.escapeHTML(value.to_s) +
  "\"/>") * 2)}
EOR
        end

      end

    end

    def test_accessor

      new_value = {
        :ping => "http://baz.com/trackback/tb.cgi?tb_id=20030808",
        :about => "http://hoge.com/trackback/tb.cgi?tb_id=90030808",
      }

      @elems.each do |name, value|
        @parents.each do |parent|
          accessor = "#{RSS::TRACKBACK_PREFIX}_#{name}"
          target = @rss.__send__(parent)
          target20 = @rss20.channel.__send__(parent, -1)
          assert_equal(value, target.__send__(accessor))
          assert_equal(value, target20.__send__(accessor))
          if name == :about
            # abount is zero or more
            target.__send__("#{accessor}=", 0, new_value[name].to_s)
            target20.__send__("#{accessor}=", 0, new_value[name].to_s)
          else
            target.__send__("#{accessor}=", new_value[name].to_s)
            target20.__send__("#{accessor}=", new_value[name].to_s)
          end
          assert_equal(new_value[name], target.__send__(accessor))
          assert_equal(new_value[name], target20.__send__(accessor))
        end
      end

    end

    def test_to_s

      @elems.each do |name, value|
        excepted = %Q!<#{@prefix}:#{name} rdf:resource="#{CGI.escapeHTML(value)}"/>!
        @parents.each do |parent|
          meth = "#{RSS::TRACKBACK_PREFIX}_#{name}_element"
          meth << "s" if name == :about
          assert_equal(excepted, @rss.__send__(parent).__send__(meth))
        end
      end

      REXML::Document.new(@rss_source).root.each_element do |parent|
        if @parents.include?(parent.name)
          parent.each_element do |elem|
            if elem.namespace == @uri
              assert_equal(elem.attributes["resource"], @elems[elem.name.intern])
            end
          end
        end
      end

    end

  end
end

