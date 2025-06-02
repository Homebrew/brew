# frozen_string_literal: false
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"

module RSS
  class TestRSS10Core < TestCase

    def setup
      @rdf_prefix = "rdf"
      @rdf_uri = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      @uri = "http://purl.org/rss/1.0/"
    end

    def test_RDF
      version = "1.0"
      encoding = "UTF-8"
      standalone = false

      rdf = RDF.new(version, encoding, standalone)
      setup_rss10(rdf)
      doc = REXML::Document.new(rdf.to_s)

      xmldecl = doc.xml_decl

      assert_equal(version, xmldecl.version)
      assert_equal(encoding, xmldecl.encoding.to_s)
      assert_equal(standalone, !xmldecl.standalone.nil?)

      assert_equal(@rdf_uri, doc.root.namespace)
    end

    def test_not_displayed_xml_stylesheets
      rdf = RDF.new()
      plain_rdf = rdf.to_s
      3.times do
        rdf.xml_stylesheets.push(XMLStyleSheet.new)
        assert_equal(plain_rdf, rdf.to_s)
      end
    end

    def test_xml_stylesheets
      [
        [{:href => "a.xsl", :type => "text/xsl"}],
        [
          {:href => "a.xsl", :type => "text/xsl"},
          {:href => "a.css", :type => "text/css"},
        ],
      ].each do |attrs_ary|
        assert_xml_stylesheet_pis(attrs_ary)
      end
    end

    def test_channel
      about = "http://hoge.com"
      resource = "http://hoge.com/hoge.png"

      item_title = "item title"
      item_link = "http://hoge.com/item"

      image = RDF::Channel::Image.new(resource)
      items = RDF::Channel::Items.new
      items.Seq.lis << items.class::Seq::Li.new(item_link)
      textinput = RDF::Channel::Textinput.new(resource)

      rss_item = RDF::Item.new
      rss_item.title = item_title
      rss_item.link = item_link
      rss_item.about = item_link

      h = {
        'title' => "fugafuga",
        'link' => "http://hoge.com",
        'description' => "fugafugafugafuga",
        'image' => image,
        'items' => items,
        'textinput' => textinput,
      }

      channel = RDF::Channel.new(about)
      %w(title link description image items textinput).each do |x|
        channel.__send__("#{x}=", h[x])
      end

      doc = REXML::Document.new(make_RDF(<<-EOR))
#{channel}
<items>
#{rss_item}
</items>
EOR
      c = doc.root.elements[1]

      assert_equal(about, c.attributes["about"])
      %w(title link description image textinput).each do |x|
        elem = c.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        if x == "image" or x == "textinput"
          excepted = resource
          res = elem.attributes.get_attribute("resource")
          assert_equal(@rdf_uri, res.namespace)
          value = res.value
        else
          excepted = h[x]
          value = elem.text
        end
        assert_equal(excepted, value)
      end
      assert_equal(@uri, c.elements["items"].namespace)
      assert_equal("items", c.elements["items"].name)
    end

    def test_channel_image
      resource = "http://hoge.com/hoge.png"
      image = RDF::Channel::Image.new(resource)

      doc = REXML::Document.new(make_RDF(image.to_s))
      i = doc.root.elements[1]

      assert_equal("image", i.name)
      assert_equal(@uri, i.namespace)

      res = i.attributes.get_attribute("resource")

      assert_equal(@rdf_uri, res.namespace)
      assert_equal(resource, res.value)
    end

    def test_channel_textinput
      resource = "http://hoge.com/hoge.png"
      textinput = RDF::Channel::Textinput.new(resource)

      doc = REXML::Document.new(make_RDF(textinput.to_s))
      t = doc.root.elements[1]

      assert_equal("textinput", t.name)
      assert_equal(@uri, t.namespace)

      res = t.attributes.get_attribute("resource")

      assert_equal(@rdf_uri, res.namespace)
      assert_equal(resource, res.value)
    end

    def test_channel_items
      item_link = "http://example.com/item"

      items = RDF::Channel::Items.new
      li = items.Seq.class::Li.new(item_link)
      items.Seq.lis << li

      doc = REXML::Document.new(make_RDF(items.to_s))
      i = doc.root.elements[1]

      assert_equal("items", i.name)
      assert_equal(@uri, i.namespace)

      assert_equal(1, i.elements.size)
      seq = i.elements[1]
      assert_equal("Seq", seq.name)
      assert_equal(@rdf_uri, seq.namespace)

      assert_equal(1, seq.elements.size)
      l = seq.elements[1]
      assert_equal("li", l.name)
      assert_equal(@rdf_uri, l.namespace)
      assert_equal(item_link, l.attributes["resource"])
    end

    def test_seq
      item_link = "http://example.com/item"
      seq = RDF::Seq.new
      li = seq.class::Li.new(item_link)
      seq.lis << li

      doc = REXML::Document.new(make_RDF(seq.to_s))
      s = doc.root.elements[1]

      assert_equal("Seq", s.name)
      assert_equal(@rdf_uri, s.namespace)

      assert_equal(1, s.elements.size)
      l = s.elements[1]
      assert_equal("li", l.name)
      assert_equal(@rdf_uri, l.namespace)
      assert_equal(item_link, l.attributes["resource"])
    end

    def test_li
      resource = "http://hoge.com/"
      li = RDF::Li.new(resource)

      doc = REXML::Document.new(make_RDF(li.to_s))
      l = doc.root.elements[1]

      assert_equal("li", l.name)
      assert_equal(@rdf_uri, l.namespace(l.prefix))

      res = l.attributes.get_attribute("resource")

      assert_equal('', res.instance_eval("@prefix"))
      assert_equal(resource, res.value)
    end

    def test_image
      about = "http://hoge.com"
      h = {
        'title' => "fugafuga",
        'url' => "http://hoge.com/hoge",
        'link' => "http://hoge.com/fuga",
      }

      image = RDF::Image.new(about)
      %w(title url link).each do |x|
        image.__send__("#{x}=", h[x])
      end

      doc = REXML::Document.new(make_RDF(image.to_s))
      i = doc.root.elements[1]

      assert_equal(about, i.attributes["about"])
      %w(title url link).each do |x|
        elem = i.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        assert_equal(h[x], elem.text)
      end
    end

    def test_item
      about = "http://hoge.com"
      h = {
        'title' => "fugafuga",
        'link' => "http://hoge.com/fuga",
        'description' => "hogehogehoge",
      }

      item = RDF::Item.new(about)
      %w(title link description).each do |x|
        item.__send__("#{x}=", h[x])
      end

      doc = REXML::Document.new(make_RDF(item.to_s))
      i = doc.root.elements[1]

      assert_equal(about, i.attributes["about"])
      %w(title link description).each do |x|
        elem = i.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        assert_equal(h[x], elem.text)
      end
    end

    def test_textinput
      about = "http://hoge.com"
      h = {
        'title' => "fugafuga",
        'link' => "http://hoge.com/fuga",
        'name' => "foo",
        'description' => "hogehogehoge",
      }

      textinput = RDF::Textinput.new(about)
      %w(title link name description).each do |x|
        textinput.__send__("#{x}=", h[x])
      end

      doc = REXML::Document.new(make_RDF(textinput.to_s))
      t = doc.root.elements[1]

      assert_equal(about, t.attributes["about"])
      %w(title link name description).each do |x|
        elem = t.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        assert_equal(h[x], elem.text)
      end
    end

    def test_to_xml
      rss = RSS::Parser.parse(make_sample_RDF)
      assert_equal(rss.to_s, rss.to_xml)
      assert_equal(rss.to_s, rss.to_xml("1.0"))
      rss09 = rss.to_xml("0.91") do |maker|
        maker.channel.language = "en-us"
      end
      rss09 = RSS::Parser.parse(rss09)
      assert_equal("0.91", rss09.rss_version)
      assert_equal(["rss", "0.91", nil], rss09.feed_info)
      rss20 = RSS::Parser.parse(rss.to_xml("2.0"))
      assert_equal("2.0", rss20.rss_version)
      assert_equal(["rss", "2.0", nil], rss20.feed_info)

      atom_xml = rss.to_xml("atom") do |maker|
        maker.channel.author = "Alice"
        maker.channel.updated ||= Time.now
        maker.items.each do |item|
          item.updated ||= Time.now
        end
      end
      atom = RSS::Parser.parse(atom_xml)
      assert_equal(["atom", "1.0", "feed"], atom.feed_info)
    end
  end
end
