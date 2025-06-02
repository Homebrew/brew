# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerContent < TestCase

    def setup
      @uri = "http://purl.org/rss/1.0/modules/content/"

      @elements = {
        :encoded => "<em>ATTENTION</em>",
      }
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        setup_dummy_item(maker)
        item = maker.items.last
        @elements.each do |name, value|
          item.__send__("#{accessor_name(name)}=", value)
        end
      end
      assert_content(@elements, rss.items.last)
    end

    def test_rss20
      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        setup_dummy_item(maker)
        item = maker.items.last
        @elements.each do |name, value|
          item.__send__("#{accessor_name(name)}=", value)
        end
      end
      assert_content(@elements, rss.items.last)
    end

    private
    def accessor_name(name)
      "content_#{name}"
    end
  end
end
