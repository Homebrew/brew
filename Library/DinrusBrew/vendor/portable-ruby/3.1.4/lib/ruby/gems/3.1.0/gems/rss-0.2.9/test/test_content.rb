# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/content"

module RSS
  class TestContent < TestCase
    def setup
      @prefix = "content"
      @uri = "http://purl.org/rss/1.0/modules/content/"

      @elems = {
        :encoded => "<em>ATTENTION</em>",
      }

      @content_nodes = @elems.collect do |name, value|
        "<#{@prefix}:#{name}>#{CGI.escapeHTML(value.to_s)}</#{@prefix}:#{name}>"
      end.join("\n")

      @rss10_source = make_RDF(<<-EOR, {@prefix => @uri})
#{make_channel()}
#{make_image()}
#{make_item(@content_nodes)}
#{make_textinput()}
EOR

      @rss10 = Parser.parse(@rss10_source)


      @rss20_source = make_rss20(<<-EOR, {@prefix =>  @uri})
#{make_channel20(make_item20(@content_nodes))}
EOR

      @rss20 = Parser.parse(@rss20_source)
    end

    def test_parser
      assert_nothing_raised do
        Parser.parse(@rss10_source)
      end

      assert_nothing_raised do
        Parser.parse(@rss20_source)
      end

      @elems.each do |tag, value|
        tag_name = "#{@prefix}:#{tag}"
        content_encodes = make_element(tag_name, {}, value) * 2

        assert_too_much_tag(tag.to_s, "item") do
          Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel}
#{make_item(content_encodes)}
EOR
        end

        assert_too_much_tag(tag.to_s, "item") do
          Parser.parse(make_rss20(<<-EOR, {@prefix => @uri}))
#{make_channel20(make_item20(content_encodes))}
EOR
        end
      end
    end

    def test_accessor
      new_value = {
        :encoded => "<![CDATA[<it>hoge</it>]]>",
      }

      @elems.each do |name, value|
        [@rss10, @rss20].each do |rss|
          meth = "#{RSS::CONTENT_PREFIX}_#{name}"
          parent = rss.items.last
          assert_equal(value, parent.__send__(meth))
          parent.__send__("#{meth}=", new_value[name].to_s)
          assert_equal(new_value[name], parent.__send__(meth))
        end
      end
    end

    def test_to_s
      @elems.each do |name, value|
        excepted = make_element("#{@prefix}:#{name}", {}, value)
        meth = "#{RSS::CONTENT_PREFIX}_#{name}_element"
        [@rss10, @rss20].each do |rss|
          assert_equal(excepted, rss.items.last.__send__(meth))
        end
      end

      [@rss10_source, @rss20_source].each do |source|
        REXML::Document.new(source).root.each_element do |parent|
          next unless parent.name != "item"
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
