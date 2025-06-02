# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/1.0"

module RSS
  class TestInherit < TestCase

    class InheritedImage < RSS::RDF::Image
      def self.indent_size; 1; end
      def self.tag_name; 'image'; end
    end

    def setup
      @rss = make_RDF(<<-EOR)
#{make_channel}
#{make_image}
#{make_item}
#{make_textinput}
EOR
    end

    def test_inherit
      rss = RSS::Parser.parse(@rss)
      orig_image = rss.image
      prefix = "[INHERIT]"
      image = InheritedImage.new("#{prefix} #{orig_image.about}")
      image.title = "#{prefix} #{orig_image.title}"
      image.url = "#{prefix} #{orig_image.url}"
      image.link = "#{prefix} #{orig_image.link}"
      rss.image = image

      new_rss = RSS::Parser.parse(rss.to_s)
      new_image = new_rss.image
      assert_equal("#{prefix} #{orig_image.about}", new_image.about)
      assert_equal("#{prefix} #{orig_image.title}", new_image.title)
      assert_equal("#{prefix} #{orig_image.url}", new_image.url)
      assert_equal("#{prefix} #{orig_image.link}", new_image.link)
    end
  end
end
