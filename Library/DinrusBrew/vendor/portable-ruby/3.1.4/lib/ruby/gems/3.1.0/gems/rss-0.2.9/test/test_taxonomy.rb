# frozen_string_literal: false
require "cgi"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/2.0"
require "rss/taxonomy"

module RSS
  class TestTaxonomy < TestCase

    def setup
      @prefix = "taxo"
      @uri = "http://purl.org/rss/1.0/modules/taxonomy/"
      @dc_prefix = "dc"
      @dc_uri = "http://purl.org/dc/elements/1.1/"

      @ns = {
        @prefix => @uri,
        @dc_prefix => @dc_uri,
      }

      @topics_parents = %w(channel item)

      @topics_lis = [
        "http://meerkat.oreillynet.com/?c=cat23",
        "http://meerkat.oreillynet.com/?c=47",
        "http://dmoz.org/Computers/Data_Formats/Markup_Languages/XML/",
      ]

      @topics_node = "<#{@prefix}:topics>\n"
      @topics_node << "  <rdf:Bag>\n"
      @topics_lis.each do |value|
        resource = CGI.escapeHTML(value)
        @topics_node << "    <rdf:li resource=\"#{resource}\"/>\n"
      end
      @topics_node << "  </rdf:Bag>\n"
      @topics_node << "</#{@prefix}:topics>"

      @topic_topics_lis = \
      [
       "http://meerkat.oreillynet.com/?c=cat23",
       "http://dmoz.org/Computers/Data_Formats/Markup_Languages/SGML/",
       "http://dmoz.org/Computers/Programming/Internet/",
      ]

      @topic_contents = \
      [
       {
         :link => "http://meerkat.oreillynet.com/?c=cat23",
         :title => "Data: XML",
         :description => "A Meerkat channel",
       },
       {
         :link => "http://dmoz.org/Computers/Data_Formats/Markup_Languages/XML/",
         :title => "XML",
         :subject => "XML",
         :description => "DMOZ category",
         :topics => @topic_topics_lis,
       }
      ]

      @topic_nodes = @topic_contents.collect do |info|
        link = info[:link]
        rv = "<#{@prefix}:topic rdf:about=\"#{link}\">\n"
        info.each do |name, value|
          case name
          when :topics
            rv << "  <#{@prefix}:topics>\n"
            rv << "    <rdf:Bag>\n"
            value.each do |li|
              resource = CGI.escapeHTML(li)
              rv << "      <rdf:li resource=\"#{resource}\"/>\n"
            end
            rv << "    </rdf:Bag>\n"
            rv << "  </#{@prefix}:topics>\n"
          else
            prefix = (name == :link ? @prefix : @dc_prefix)
            rv << "  <#{prefix}:#{name}>#{value}</#{prefix}:#{name}>\n"
          end
        end
        rv << "</#{@prefix}:topic>"
      end

      @rss_source = make_RDF(<<-EOR, @ns)
#{make_channel(@topics_node)}
#{make_image()}
#{make_item(@topics_node)}
#{make_textinput()}
#{@topic_nodes.join("\n")}
EOR

      @rss = Parser.parse(@rss_source)
    end

    def test_parser
      assert_nothing_raised do
        Parser.parse(@rss_source)
      end

      assert_too_much_tag("topics", "channel") do
        Parser.parse(make_RDF(<<-EOR, @ns))
#{make_channel(@topics_node * 2)}
#{make_item()}
EOR
      end

      assert_too_much_tag("topics", "item") do
        Parser.parse(make_RDF(<<-EOR, @ns))
#{make_channel()}
#{make_item(@topics_node * 2)}
EOR
      end
    end

    def test_accessor
      topics = @rss.channel.taxo_topics
      assert_equal(@topics_lis.sort,
                   topics.Bag.lis.collect {|li| li.resource}.sort)
      assert_equal(@topics_lis.sort, topics.resources.sort)

      assert_equal(@rss.taxo_topics.first, @rss.taxo_topic)

      @topic_contents.each_with_index do |info, i|
        topic = @rss.taxo_topics[i]
        info.each do |name, value|
          case name
          when :link
            assert_equal(value, topic.about)
            assert_equal(value, topic.taxo_link)
          when :topics
            assert_equal(value.sort, topic.taxo_topics.resources.sort)
          else
            assert_equal(value, topic.__send__("dc_#{name}"))
          end
        end
      end
    end

    def test_to_s
      @topics_parents.each do |parent|
        meth = "taxo_topics_element"
        assert_equal(@topics_node, @rss.__send__(parent).__send__(meth))
      end

      @topic_nodes.each_with_index do |node, i|
        expected_xml = taxo_xmlns_container(node)
        expected = REXML::Document.new(expected_xml).root.elements[1]
        actual_xml = taxo_xmlns_container(@rss.taxo_topics[i].to_s(true, ""))
        actual = REXML::Document.new(actual_xml).root.elements[1]
        expected_elems = expected.reject {|x| x.is_a?(REXML::Text)}
        actual_elems = actual.reject {|x| x.is_a?(REXML::Text)}
        expected_elems.sort! {|x, y| x.name <=> y.name}
        actual_elems.sort! {|x, y| x.name <=> y.name}
        assert_equal(expected_elems.collect {|x| x.to_s},
                     actual_elems.collect {|x| x.to_s})
        assert_equal(expected.attributes.sort, actual.attributes.sort)
      end
    end

    private
    def taxo_xmlns_container(content)
      xmlns_container({
                        @prefix => @uri,
                        "dc" => "http://purl.org/dc/elements/1.1/",
                        "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
                      },
                      content)
    end
  end
end

