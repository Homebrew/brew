# frozen_string_literal: false
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/xml-stylesheet"

module RSS
  class TestXMLStyleSheet < TestCase

    def test_accessor
      [
        {:href => "a.xsl", :type => "text/xsl"},
        {:media => "print", :title => "FOO"},
        {:charset => "UTF-8", :alternate => "yes"},
      ].each do |attrs|
        assert_xml_stylesheet_attrs(attrs, XMLStyleSheet.new(attrs))
      end
    end

    def test_to_s
      [
        {:href => "a.xsl", :type => "text/xsl"},
        {:type => "text/xsl"},
        {:href => "a.xsl", :guess_type => "text/xsl"},
        {:href => "a.css", :type => "text/css"},
        {:href => "a.css", :type => "text/xsl",
         :guess_type => "text/css"},
        {:href => "a.xsl", :type => "text/xsl",
         :title => "sample", :media => "printer",
         :charset => "UTF-8", :alternate => "yes"},
        {:href => "a.css", :guess_type => "text/css",
         :alternate => "no"},
        {:type => "text/xsl", :title => "sample",
         :media => "printer", :charset => "UTF-8",
         :alternate => "yes"},
      ].each do |attrs|
        target, contents = parse_pi(XMLStyleSheet.new(attrs).to_s)
        assert_xml_stylesheet(target, attrs, XMLStyleSheet.new(contents))
      end
    end

    def test_bad_alternate
      %w(a ___ ??? BAD_ALTERNATE).each do |value|
        xss = XMLStyleSheet.new
        assert_raise(NotAvailableValueError) do
          xss.alternate = value
        end
        xss.do_validate = false
        assert_nothing_raised do
          xss.alternate = value
        end
        assert_nil(xss.alternate)
      end
    end

    def test_parse
      [
        [{:href => "a.xsl", :type => "text/xsl"},],
        [{:media => "print", :title => "FOO"},],
        [{:charset => "UTF-8", :alternate => "yes"},],
        [{:href => "a.xsl", :type => "text/xsl"},
         {:type => "text/xsl"},
         {:href => "a.xsl", :guess_type => "text/xsl"},
         {:href => "a.css", :type => "text/css"},
         {:href => "a.css", :type => "text/xsl",
          :guess_type => "text/css"},
         {:href => "a.xsl", :type => "text/xsl",
          :title => "sample", :media => "printer",
          :charset => "UTF-8", :alternate => "yes"},
         {:href => "a.css", :guess_type => "text/css",
          :alternate => "no"},
         {:type => "text/xsl", :title => "sample",
          :media => "printer", :charset => "UTF-8",
          :alternate => "yes"},],
      ].each do |xsss|
        doc = REXML::Document.new(make_sample_RDF)
        root = doc.root
        xsss.each do |xss|
          content = xss.collect do |key, name|
            %Q[#{key}="#{name}"]
          end.join(" ")
          pi = REXML::Instruction.new("xml-stylesheet", content)
          root.previous_sibling = pi
        end
        rss = Parser.parse(doc.to_s)
        have_href_xsss = xsss.find_all {|xss| xss.has_key?(:href)}
        assert_equal(have_href_xsss.size, rss.xml_stylesheets.size)
        rss.xml_stylesheets.each_with_index do |stylesheet, i|
          target, = parse_pi(stylesheet.to_s)
          assert_xml_stylesheet(target, have_href_xsss[i], stylesheet)
        end
      end
    end

    def parse_pi(pi)
      /\A\s*<\?(\S+)([^?]*\?+(?:[^?>][^?]*\?+)*)>\s*\z/ =~ pi
      target = $1
      dummy = REXML::Document.new("<dummy #{$2.to_s.chop}/>").root
      contents = {}
      dummy.attributes.each do |name, value|
        contents[name] = value
      end
      [target, contents]
    end

  end
end
