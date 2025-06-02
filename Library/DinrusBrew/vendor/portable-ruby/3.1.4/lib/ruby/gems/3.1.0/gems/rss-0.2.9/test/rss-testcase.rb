# frozen_string_literal: false
require "erb"

require "test/unit"
require_relative 'rss-assertions'

require "rss"

module RSS
  class TestCase < Test::Unit::TestCase
    include ERB::Util

    include RSS
    include Assertions

    XMLDECL_VERSION = "1.0"
    XMLDECL_ENCODING = "UTF-8"
    XMLDECL_STANDALONE = "no"

    RDF_ABOUT = "http://www.xml.com/xml/news.rss"
    RDF_RESOURCE = "http://xml.com/universal/images/xml_tiny.gif"
    TITLE_VALUE = "XML.com"
    LINK_VALUE = "http://xml.com/pub"
    URL_VALUE = "http://xml.com/universal/images/xml_tiny.gif"
    NAME_VALUE = "hogehoge"
    LANGUAGE_VALUE = "ja"
    DESCRIPTION_VALUE = "
    XML.com features a rich mix of information and services
    for the XML community.
    "
    RESOURCES = [
      "http://xml.com/pub/2000/08/09/xslt/xslt.html",
      "http://xml.com/pub/2000/08/09/rdfdb/index.html",
    ]

    CLOUD_DOMAIN = "data.ourfavoritesongs.com"
    CLOUD_PORT = "80"
    CLOUD_PATH = "/RPC2"
    CLOUD_REGISTER_PROCEDURE = "ourFavoriteSongs.rssPleaseNotify"
    CLOUD_PROTOCOL = "xml-rpc"

    ENCLOSURE_URL = "http://www.scripting.com/mp3s/weatherReportSuite.mp3"
    ENCLOSURE_LENGTH = "12216320"
    ENCLOSURE_TYPE = "audio/mpeg"

    CATEGORY_DOMAIN = "http://www.superopendirectory.com/"

    FEED_TITLE = "dive into mark"
    FEED_UPDATED = "2003-12-13T18:30:02Z"
    FEED_AUTHOR_NAME = "John Doe"
    FEED_ID = "urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6"

    ENTRY_TITLE = "Atom-Powered Robots Run Amok"
    ENTRY_LINK = "http://example.org/2003/12/13/atom03"
    ENTRY_ID = "urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a"
    ENTRY_UPDATED = "2003-12-13T18:30:02Z"
    ENTRY_SUMMARY = "Some text."

    t = Time.iso8601("2000-01-01T12:00:05+00:00")
    class << t
      alias_method(:to_s, :iso8601)
    end

    DC_ELEMENTS = {
      :title => "hoge",
      :description =>
        " XML is placing increasingly heavy loads on
          the existing technical infrastructure of the Internet.",
      :creator => "Rael Dornfest (mailto:rael@oreilly.com)",
      :subject => "XML",
      :publisher => "The O'Reilly Network",
      :contributor => "hogehoge",
      :type => "fugafuga",
      :format => "hohoho",
      :identifier => "fufufu",
      :source => "barbar",
      :language => "ja",
      :relation => "cococo",
      :rights => "Copyright (c) 2000 O'Reilly &amp; Associates, Inc.",
      :date => t,
    }

    DC_NODES = DC_ELEMENTS.collect do |name, value|
      "<#{DC_PREFIX}:#{name}>#{value}</#{DC_PREFIX}:#{name}>"
    end.join("\n")

    def default_test
      # This class isn't tested
    end

    private
    def make_xmldecl(v=XMLDECL_VERSION, e=XMLDECL_ENCODING, s=XMLDECL_STANDALONE)
      rv = "<?xml version='#{v}'"
      rv << " encoding='#{e}'" if e
      rv << " standalone='#{s}'" if s
      rv << "?>"
      rv
    end

    def make_RDF(content=nil, xmlns=[])
      <<-EORSS
#{make_xmldecl}
<rdf:RDF xmlns="#{URI}" xmlns:rdf="#{RDF::URI}"
#{xmlns.collect {|pre, uri| "xmlns:#{pre}='#{uri}'"}.join(' ')}>
#{block_given? ? yield : content}
</rdf:RDF>
EORSS
    end

    def make_channel(content=nil)
      <<-EOC
<channel rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>

  <image rdf:resource="#{RDF_RESOURCE}" />

  <items>
    <rdf:Seq>
#{RESOURCES.collect do |res| '<rdf:li resource="' + res + '" />' end.join("\n")}
    </rdf:Seq>
  </items>

  <textinput rdf:resource="#{RDF_RESOURCE}" />

#{block_given? ? yield : content}
</channel>
EOC
    end

    def make_image(content=nil)
      <<-EOI
<image rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <url>#{URL_VALUE}</url>
  <link>#{LINK_VALUE}</link>
#{block_given? ? yield : content}
</image>
EOI
    end

    def make_item(content=nil)
      <<-EOI
<item rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
#{block_given? ? yield : content}
</item>
EOI
    end

    def make_textinput(content=nil)
      <<-EOT
<textinput rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE}</title>
  <description>#{DESCRIPTION_VALUE}</description>
  <name>#{NAME_VALUE}</name>
  <link>#{LINK_VALUE}</link>
#{block_given? ? yield : content}
</textinput>
EOT
    end

    def make_sample_RDF
      make_RDF(<<-EOR)
#{make_channel}
#{make_image}
#{make_item}
#{make_textinput}
EOR
    end

    def make_rss20(content=nil, xmlns=[])
      <<-EORSS
#{make_xmldecl}
<rss version="2.0"
#{xmlns.collect {|pre, uri| "xmlns:#{pre}='#{uri}'"}.join(' ')}>
#{block_given? ? yield : content}
</rss>
EORSS
    end

    def make_sample_items20
      RESOURCES.collect do |res|
        elems = ["<link>#{res}</link>"]
        elems << "<title>title of #{res}</title>"
        elems = elems.join("\n")
        "<item>\n#{elems}\n</item>"
      end.join("\n")
    end

    def make_channel20(content=nil)
      <<-EOC
<channel>
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
  <language>#{LANGUAGE_VALUE}</language>

  <image>
    <url>#{RDF_RESOURCE}</url>
    <title>#{TITLE_VALUE}</title>
    <link>#{LINK_VALUE}</link>
  </image>

#{make_sample_items20}

  <textInput>
    <title>#{TITLE_VALUE}</title>
    <description>#{DESCRIPTION_VALUE}</description>
    <name>#{NAME_VALUE}</name>
    <link>#{RDF_RESOURCE}</link>
  </textInput>

#{block_given? ? yield : content}
</channel>
EOC
    end

    def make_item20(content=nil)
      <<-EOI
<item>
  <title>#{TITLE_VALUE}</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
#{block_given? ? yield : content}
</item>
EOI
    end

    def make_cloud20
      <<-EOC
<cloud
  domain="#{CLOUD_DOMAIN}"
  port="#{CLOUD_PORT}"
  path="#{CLOUD_PATH}"
  registerProcedure="#{CLOUD_REGISTER_PROCEDURE}"
  protocol="#{CLOUD_PROTOCOL}" />
EOC
    end

    def make_sample_rss20
      make_rss20(<<-EOR)
#{make_channel20}
EOR
    end

    def make_feed_without_entry(content=nil, xmlns=[])
      <<-EOA
<feed xmlns="#{Atom::URI}"
#{xmlns.collect {|pre, uri| "xmlns:#{pre}='#{uri}'"}.join(' ')}>
  <id>#{FEED_ID}</id>
  <title>#{FEED_TITLE}</title>
  <updated>#{FEED_UPDATED}</updated>
  <author>
    <name>#{FEED_AUTHOR_NAME}</name>
  </author>
#{block_given? ? yield : content}
</feed>
EOA
    end

    def make_entry(content=nil)
      <<-EOA
  <entry>
    <title>#{ENTRY_TITLE}</title>
    <id>#{ENTRY_ID}</id>
    <updated>#{ENTRY_UPDATED}</updated>
#{block_given? ? yield : content}
  </entry>
EOA
    end

    def make_feed_with_open_entry(content=nil, xmlns=[], &block)
      make_feed_without_entry(<<-EOA, xmlns)
#{make_entry(content, &block)}
EOA
    end

    def make_feed_with_open_entry_source(content=nil, xmlns=[])
      make_feed_with_open_entry(<<-EOA, xmlns)
  <source>
#{block_given? ? yield : content}
  </source>
EOA
    end

    def make_feed(content=nil, xmlns=[])
      make_feed_without_entry(<<-EOA, xmlns)
  <entry>
    <title>#{ENTRY_TITLE}</title>
    <link href="#{ENTRY_LINK}"/>
    <id>#{ENTRY_ID}</id>
    <updated>#{ENTRY_UPDATED}</updated>
    <summary>#{ENTRY_SUMMARY}</summary>
  </entry>
#{block_given? ? yield : content}
EOA
    end

    def make_entry_document(content=nil, xmlns=[])
      <<-EOA
<entry xmlns="#{Atom::URI}"
#{xmlns.collect {|pre, uri| "xmlns:#{pre}='#{uri}'"}.join(' ')}>
  <id>#{ENTRY_ID}</id>
  <title>#{ENTRY_TITLE}</title>
  <updated>#{ENTRY_UPDATED}</updated>
  <author>
    <name>#{FEED_AUTHOR_NAME}</name>
  </author>
#{block_given? ? yield : content}
</entry>
EOA
    end

    def make_entry_document_with_open_source(content=nil, xmlns=[])
      make_entry_document(<<-EOA, xmlns)
  <source>
#{block_given? ? yield : content}
  </source>
EOA
    end

    def make_element(elem_name, attrs, contents)
      attrs_str = attrs.collect do |name, value|
        "#{h name}='#{h value}'"
      end.join(" ")
      attrs_str = " #{attrs_str}" unless attrs_str.empty?

      if contents.is_a?(String)
        contents_str = h(contents)
      else
        contents_str = contents.collect do |name, value|
          "#{Element::INDENT}<#{h name}>#{h value}</#{h name}>"
        end.join("\n")
        contents_str = "\n#{contents_str}\n"
      end

      "<#{h elem_name}#{attrs_str}>#{contents_str}</#{h elem_name}>"
    end

    def xmlns_container(xmlns_decls, content)
      attributes = xmlns_decls.collect do |prefix, uri|
        "xmlns:#{h prefix}=\"#{h uri}\""
      end.join(" ")
      "<dummy #{attributes}>#{content}</dummy>"
    end

    private
    def setup_rss10(rdf)
      assert_equal("", rdf.to_s)

      channel = RDF::Channel.new
      assert_equal("", channel.to_s)
      channel.about = "http://example.com/index.rdf"
      channel.title = "title"
      channel.link = "http://example.com/"
      channel.description = "description"
      assert_equal("", channel.to_s)

      item_title = "item title"
      item_link = "http://example.com/item"
      channel.items = RDF::Channel::Items.new
      channel.items.Seq.lis << RDF::Channel::Items::Seq::Li.new(item_link)
      assert_not_equal("", channel.to_s)

      rdf.channel = channel
      assert_equal("", rdf.to_s)

      item = RDF::Item.new
      item.title = item_title
      item.link = item_link
      item.about = item_link
      rdf.items << item
      assert_not_equal("", rdf.to_s)
    end

    def setup_rss20(rss)
      assert_equal("", rss.to_s)

      channel = Rss::Channel.new
      assert_equal("", channel.to_s)
      channel.title = "title"
      channel.link = "http://example.com/"
      channel.description = "description"
      assert_not_equal("", channel.to_s)

      rss.channel = channel
      assert_not_equal("", rss.to_s)
    end

    def setup_dummy_channel(maker)
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com/feed.xml"
      description = "fugafugafugafuga"
      language = "ja"

      maker.channel.about = about
      maker.channel.title = title
      maker.channel.link = link
      maker.channel.description = description
      maker.channel.language = language
    end

    def setup_dummy_channel_atom(maker)
      updated = Time.now
      author = "Foo"

      setup_dummy_channel(maker)
      maker.channel.links.first.rel = "self"
      maker.channel.links.first.type = "application/atom+xml"
      maker.channel.updated = updated
      maker.channel.author = author
    end

    def setup_dummy_image(maker)
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      maker.channel.link = link if maker.channel.link.nil?

      maker.image.title = title
      maker.image.url = url
    end

    def setup_dummy_textinput(maker)
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com/search.cgi"

      maker.textinput.title = title
      maker.textinput.description = description
      maker.textinput.name = name
      maker.textinput.link = link
    end

    def setup_dummy_item(maker)
      title = "TITLE"
      link = "http://hoge.com/"

      item = maker.items.new_item
      item.title = title
      item.link = link
    end

    def setup_dummy_item_atom(maker)
      setup_dummy_item(maker)

      item = maker.items.first
      item.id = "http://example.net/xxx"
      item.updated = Time.now
    end

    def setup_taxo_topic(target, topics)
      topics.each do |topic|
        taxo_topic = target.taxo_topics.new_taxo_topic
        topic.each do |name, value|
          case name
          when :link
            taxo_topic.taxo_link = value
          when :topics
            value.each do |t|
              taxo_topic.taxo_topics << t
            end
          else
            dc_elems = taxo_topic.__send__("dc_#{name}s")
            dc_elem = dc_elems.__send__("new_#{name}")
            dc_elem.value = value
          end
        end
      end
    end
  end
end
