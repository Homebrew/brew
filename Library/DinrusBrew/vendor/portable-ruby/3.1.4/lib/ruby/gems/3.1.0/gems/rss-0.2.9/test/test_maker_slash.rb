# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerSlash < TestCase
    def setup
      @elements = {
        "section" => "articles",
        "department" => "not-an-ocean-unless-there-are-lobsters",
        "comments" => 177,
        "hit_parades" => [177, 155, 105, 33, 6, 3, 0],
      }
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        setup_dummy_item(maker)
        item = maker.items.last
        @elements.each do |name, value|
          item.send("slash_#{name}=", value)
        end
      end

      item = rss.items.last
      assert_not_nil(item)
      assert_slash_elements(item)
    end

    private
    def assert_slash_elements(target)
      super(@elements, target)
    end
  end
end
