# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/1.0"
require "rss/dublincore"

module RSS
  class TestParser10 < TestCase
    def test_RDF
      assert_ns("", RDF::URI) do
        Parser.parse(<<-EOR)
#{make_xmldecl}
<RDF/>
EOR
      end

      assert_ns("", RDF::URI) do
        Parser.parse(<<-EOR)
#{make_xmldecl}
<RDF xmlns="hoge"/>
EOR
      end

      assert_ns("rdf", RDF::URI) do
        Parser.parse(<<-EOR)
#{make_xmldecl}
<rdf:RDF xmlns:rdf="hoge"/>
EOR
      end

      assert_parse(<<-EOR, :missing_tag, "channel", "RDF")
#{make_xmldecl}
<rdf:RDF xmlns:rdf="#{RSS::RDF::URI}"/>
EOR

      assert_parse(<<-EOR, :missing_tag, "channel", "RDF")
#{make_xmldecl}
<RDF xmlns="#{RSS::RDF::URI}"/>
EOR

      assert_parse(<<-EOR, :missing_tag, "channel", "RDF")
#{make_xmldecl}
<RDF xmlns="#{RSS::RDF::URI}"/>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
#{make_image}
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
#{make_textinput}
EOR

      assert_too_much_tag("image", "RDF") do
        Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_image}
#{make_image}
#{make_item}
#{make_textinput}
EOR
      end

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_item}
#{make_image}
#{make_textinput}
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
#{make_item}
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
#{make_item}
#{make_textinput}
EOR

      1.step(15, 3) do |i|
        rss = make_RDF() do
          res = make_channel
          i.times { res << make_item }
          res
        end
        assert_parse(rss, :nothing_raised)
      end
    end

    def test_undefined_entity
      return unless RSS::Parser.default_parser.raise_for_undefined_entity?
      assert_parse(make_RDF(<<-EOR), :raises, RSS::NotWellFormedError)
#{make_channel}
#{make_image}
<item rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE} &UNKNOWN_ENTITY;</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
</item>
#{make_textinput}
EOR
    end

    def test_channel
      assert_parse(make_RDF(<<-EOR), :missing_attribute, "channel", "rdf:about")
<channel />
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "channel")
<channel rdf:about="http://example.com/"/>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
</channel>
EOR

      assert_parse(make_RDF(<<EOR), :missing_tag, "description", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "items", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "image", "rdf:resource")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image/>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "items", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
</channel>
EOR

      rss = make_RDF(<<-EOR)
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items/>
</channel>
EOR

      assert_missing_tag("Seq", "items") do
        Parser.parse(rss)
      end

      assert_missing_tag("item", "RDF") do
        Parser.parse(rss, false).validate
      end

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
    </rdf:Seq>
  </items>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "textinput", "rdf:resource")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
    </rdf:Seq>
  </items>
  <textinput/>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
    </rdf:Seq>
  </items>
  <textinput rdf:resource="http://example.com/search" />
</channel>
EOR
    end

    def test_rdf_li
      rss = make_RDF(<<-EOR)
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
      <rdf:li \#{rdf_li_attr}/>
    </rdf:Seq>
  </items>
  <textinput rdf:resource="http://example.com/search" />
</channel>
#{make_item}
EOR

      source = Proc.new do |rdf_li_attr|
        eval(%Q[%Q[#{rss}]], binding)
      end

      attr = %q[resource="http://example.com/hoge"]
      assert_parse(source.call(attr), :nothing_raised)

      attr = %q[rdf:resource="http://example.com/hoge"]
      assert_parse(source.call(attr), :nothing_raised)

      assert_parse(source.call(""), :missing_attribute, "li", "resource")
    end

    def test_image
      assert_parse(make_RDF(<<-EOR), :missing_attribute, "image", "rdf:about")
#{make_channel}
<image>
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "image")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "url", "image")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "image")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
  <url>http://example.com/hoge.png</url>
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
  <url>http://example.com/hoge.png</url>
  <link>http://example.com/</link>
</image>
EOR

      rss = make_RDF(<<-EOR)
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <link>http://example.com/</link>
  <url>http://example.com/hoge.png</url>
  <title>hoge</title>
</image>
EOR

      assert_missing_tag("item", "RDF") do
        Parser.parse(rss)
      end

      assert_missing_tag("item", "RDF") do
        Parser.parse(rss, false).validate
      end
    end

    def test_item
      assert_parse(make_RDF(<<-EOR), :missing_attribute, "item", "rdf:about")
#{make_channel}
#{make_image}
<item>
</item>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "item")
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
</item>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "item")
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
</item>
EOR

      assert_too_much_tag("title", "item") do
        Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
  <title>hoge</title>
  <link>http://example.com/hoge.html</link>
</item>
EOR
      end

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
  <link>http://example.com/hoge.html</link>
</item>
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
  <link>http://example.com/hoge.html</link>
  <description>hogehoge</description>
</item>
EOR
    end

    def test_textinput
      assert_parse(make_RDF(<<-EOR), :missing_attribute, "textinput", "rdf:about")
#{make_channel}
#{make_image}
#{make_item}
<textinput>
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "description", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
</textinput>
EOR

      assert_too_much_tag("title", "textinput") do
        Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <title>hoge</title>
  <description>hogehoge</description>
</textinput>
EOR
      end

      assert_parse(make_RDF(<<-EOR), :missing_tag, "name", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <description>hogehoge</description>
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <description>hogehoge</description>
  <name>key</name>
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <description>hogehoge</description>
  <name>key</name>
  <link>http://example.com/search.html</link>
</textinput>
EOR
    end

    def test_ignore
      name = "a"
      rss = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
<#{name}/>
EOR
      assert_not_expected_tag(name, ::RSS::URI, "RDF") do
        Parser.parse(rss, true, false)
      end

      uri = ""
      name = "a"
      rss = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
<#{name} xmlns=""/>
EOR
      assert_parse(rss, :nothing_raised)
      assert_not_expected_tag(name, uri, "RDF") do
        Parser.parse(rss, true, false)
      end

      uri = "http://example.com/"
      name = "a"
      rss = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
<x:#{name} xmlns:x="#{uri}"/>
EOR
      assert_parse(rss, :nothing_raised)
      assert_not_expected_tag(name, uri, "RDF") do
        Parser.parse(rss, true, false)
      end

      uri = ::RSS::URI
      name = "a"
      rss = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
#{make_image("<#{name}/>")}
EOR
      assert_parse(rss, :nothing_raised)
      assert_not_expected_tag(name, uri, "image") do
        Parser.parse(rss, true, false)
      end

      uri = CONTENT_URI
      name = "encoded"
      elem = "<#{name} xmlns='#{uri}'/>"
      rss = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
#{make_image(elem)}
EOR
      assert_parse(rss, :nothing_raised)
      assert_not_expected_tag(name, uri, "image") do
        Parser.parse(rss, true, false)
      end
    end

    def test_unknown_duplicated_element
      xmlns = {"test" => "http://localhost/test"}
      assert_parse(make_RDF(<<-EOR, xmlns), :nothing_raised)
        #{make_channel("<test:string/>")}
        #{make_item}
        #{make_image}
      EOR
    end

    def test_unknown_case_insensitive_duplicated_element
      xmlns = {
        "foaf" => "http://xmlns.com/foaf/0.1/",
        "dc" => "http://purl.org/dc/elements/1.1/",
      }
      assert_parse(make_RDF(<<-EOR, xmlns), :nothing_raised)
        #{make_channel}
        #{make_item}
        #{make_image}
        <foaf:Image rdf:about="http://example.com/myself.png">
          <dc:title>Myself</dc:title>
          <dc:link>http://example.com/</dc:link>
        </foaf:Image>
      EOR
    end
  end
end

