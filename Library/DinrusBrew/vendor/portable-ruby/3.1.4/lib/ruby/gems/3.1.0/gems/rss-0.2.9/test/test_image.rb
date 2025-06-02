# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/image"

module RSS
  class TestImage < TestCase

    def setup
      @prefix = "image"
      @uri = "http://purl.org/rss/1.0/modules/image/"

      @favicon_attrs = {
        "rdf:about" => "http://www.kuro5hin.org/favicon.ico",
        "#{@prefix}:size" => "small",
      }
      @favicon_contents = {"dc:title" => "Kuro5hin",}
      @items = [
        [
          {
            "rdf:about" => "http://www.example.org/item.png",
            "rdf:resource" => "http://www.example.org/item",
          },
          {
            "dc:title" => "Example Image",
            "#{@prefix}:width" => "100",
            "#{@prefix}:height" => "65",
          },
        ],
        [
          {
            "rdf:about" => "http://www.kuro5hin.org/images/topics/culture.jpg",
          },
          {
            "dc:title" => "Culture",
            "#{@prefix}:width" => "80",
            "#{@prefix}:height" => "50",
          },
        ]
      ]


      @channel_nodes = make_element("#{@prefix}:favicon",
                                    @favicon_attrs,
                                    @favicon_contents)
      items = ""
      @items.each do |attrs, contents|
        image_item = make_element("#{@prefix}:item", attrs, contents)
        items << make_item(image_item)
      end

      @ns = {
        @prefix => @uri,
        DC_PREFIX => DC_URI,
      }
      @rss_source = make_RDF(<<-EOR, @ns)
#{make_channel(@channel_nodes)}
#{make_image}
#{items}
#{make_textinput}
EOR

      @rss = Parser.parse(@rss_source)
    end

    def test_parser
      assert_nothing_raised do
        Parser.parse(@rss_source)
      end

      assert_too_much_tag("favicon", "channel") do
        Parser.parse(make_RDF(<<-EOR, @ns))
#{make_channel(@channel_nodes * 2)}
#{make_item}
EOR
      end

      attrs = {"rdf:about" => "http://www.example.org/item.png"}
      contents = [["#{@prefix}:width", "80"]] * 5
      image_item = make_element("#{@prefix}:item", attrs, contents)
      assert_too_much_tag("width", "item") do
        Parser.parse(make_RDF(<<-EOR, @ns))
#{make_channel}
#{make_item(image_item)}
EOR
      end
    end

    def test_favicon_accessor
      favicon = @rss.channel.image_favicon
      [
        %w(about rdf:about http://example.com/favicon.ico),
        %w(size image:size large),
        %w(image_size image:size medium),
      ].each do |name, full_name, new_value|
        assert_equal(@favicon_attrs[full_name], favicon.__send__(name))
        favicon.__send__("#{name}=", new_value)
        assert_equal(new_value, favicon.__send__(name))
        favicon.__send__("#{name}=", @favicon_attrs[full_name])
        assert_equal(@favicon_attrs[full_name], favicon.__send__(name))
      end

      %w(small medium large).each do |value|
        assert_nothing_raised do
          favicon.size = value
          favicon.image_size = value
        end
      end

      %w(aaa AAA SMALL MEDIUM LARGE).each do |value|
        args = ["#{@prefix}:favicon", value, "#{@prefix}:size"]
        assert_not_available_value(*args) do
          favicon.size = value
        end
        assert_not_available_value(*args) do
          favicon.image_size = value
        end
      end

      [
        %w(dc_title dc:title sample-favicon),
      ].each do |name, full_name, new_value|
        assert_equal(@favicon_contents[full_name], favicon.__send__(name))
        favicon.__send__("#{name}=", new_value)
        assert_equal(new_value, favicon.__send__(name))
        favicon.__send__("#{name}=", @favicon_contents[full_name])
        assert_equal(@favicon_contents[full_name], favicon.__send__(name))
      end
    end

    def test_item_accessor
      @rss.items.each_with_index do |item, i|
        image_item = item.image_item
        attrs, contents = @items[i]
        [
          %w(about rdf:about http://example.com/image.png),
          %w(resource rdf:resource http://example.com/),
        ].each do |name, full_name, new_value|
          assert_equal(attrs[full_name], image_item.__send__(name))
          image_item.__send__("#{name}=", new_value)
          assert_equal(new_value, image_item.__send__(name))
          image_item.__send__("#{name}=", attrs[full_name])
          assert_equal(attrs[full_name], image_item.__send__(name))
        end

        [
          ["width", "image:width", "111"],
          ["image_width", "image:width", "44"],
          ["height", "image:height", "222"],
          ["image_height", "image:height", "88"],
        ].each do |name, full_name, new_value|
          assert_equal(contents[full_name].to_i, image_item.__send__(name))
          image_item.__send__("#{name}=", new_value)
          assert_equal(new_value.to_i, image_item.__send__(name))
          image_item.__send__("#{name}=", contents[full_name])
          assert_equal(contents[full_name].to_i, image_item.__send__(name))
        end

        [
          ["dc_title", "dc:title", "sample-image"],
        ].each do |name, full_name, new_value|
          assert_equal(contents[full_name], image_item.__send__(name))
          image_item.__send__("#{name}=", new_value)
          assert_equal(new_value, image_item.__send__(name))
          image_item.__send__("#{name}=", contents[full_name])
          assert_equal(contents[full_name], image_item.__send__(name))
        end
      end
    end

    def test_favicon_to_s
      favicon = @rss.channel.image_favicon
      expected_xml = image_xmlns_container(make_element("#{@prefix}:favicon",
                                                        @favicon_attrs,
                                                        @favicon_contents))
      expected = REXML::Document.new(expected_xml)
      actual_xml = image_xmlns_container(favicon.to_s(false, ""))
      actual = REXML::Document.new(actual_xml)
      assert_equal(expected.to_s, actual.to_s)
    end

    def test_item_to_s
      @rss.items.each_with_index do |item, i|
        attrs, contents = @items[i]
        expected_xml = make_element("#{@prefix}:item", attrs, contents)
        expected_xml = image_xmlns_container(expected_xml)
        expected = REXML::Document.new(expected_xml)
        actual_xml = image_xmlns_container(item.image_item.to_s(false, ""))
        actual = REXML::Document.new(actual_xml)

        assert_equal(expected[0].attributes, actual[0].attributes)

        %w(image:height image:width dc:title).each do |name|
          actual_target = actual.elements["//#{name}"]
          expected_target = expected.elements["//#{name}"]
          assert_equal(expected_target.to_s, actual_target.to_s)
        end
      end
    end

    private
    def image_xmlns_container(content)
      xmlns_container({
                        @prefix => @uri,
                        "dc" => "http://purl.org/dc/elements/1.1/",
                        "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
                      },
                      content)
    end
  end
end
