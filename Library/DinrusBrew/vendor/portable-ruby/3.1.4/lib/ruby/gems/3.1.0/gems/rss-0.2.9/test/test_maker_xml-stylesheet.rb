# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerXMLStyleSheet < TestCase

    def test_xml_stylesheet
      href = 'a.xsl'
      type = 'text/xsl'
      title = 'sample'
      media = 'printer'
      charset = 'UTF-8'
      alternate = 'yes'

      rss = RSS::Maker.make("1.0") do |maker|
        maker.xml_stylesheets.new_xml_stylesheet do |xss|
          xss.href = href
          xss.type = type
          xss.title = title
          xss.media = media
          xss.charset = charset
          xss.alternate = alternate
        end

        setup_dummy_channel(maker)
        setup_dummy_item(maker)
      end

      xss = rss.xml_stylesheets.first
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)


      href = 'http://example.com/index.xsl'
      type = 'text/xsl'
      rss = RSS::Maker.make("1.0") do |maker|
        maker.xml_stylesheets.new_xml_stylesheet do |_xss|
          _xss.href = href
        end

        setup_dummy_channel(maker)
        setup_dummy_item(maker)
      end

      xss = rss.xml_stylesheets.first
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
    end

    def test_not_valid_xml_stylesheet
      href = 'xss.XXX'
      type = "text/xsl"

      rss = RSS::Maker.make("1.0") do |maker|
        maker.xml_stylesheets.new_xml_stylesheet do |xss|
          # xss.href = href
          xss.type = type
        end

        setup_dummy_channel(maker)
        setup_dummy_item(maker)
      end
      assert(rss.xml_stylesheets.empty?)

      rss = RSS::Maker.make("1.0") do |maker|
        maker.xml_stylesheets.new_xml_stylesheet do |xss|
          xss.href = href
          # xss.type = type
        end

        setup_dummy_channel(maker)
        setup_dummy_item(maker)
      end
      assert(rss.xml_stylesheets.empty?)
    end

  end
end
