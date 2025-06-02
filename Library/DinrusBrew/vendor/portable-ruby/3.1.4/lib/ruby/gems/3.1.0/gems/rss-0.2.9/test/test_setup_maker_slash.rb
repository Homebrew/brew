# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestSetupMakerSlash < TestCase
    def test_setup_maker
      elements = {
        "section" => "articles",
        "department" => "not-an-ocean-unless-there-are-lobsters",
        "comments" => 177,
        "hit_parades" => [177, 155, 105, 33, 6, 3, 0],
      }

      rss = RSS::Maker.make("rss1.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        item = maker.items.last
        item.slash_section = elements["section"]
        item.slash_department = elements["department"]
        item.slash_comments = elements["comments"]
        item.slash_hit_parade = elements["hit_parades"].join(",")
      end
      assert_not_nil(rss)

      new_rss = RSS::Maker.make("rss1.0") do |maker|
        rss.setup_maker(maker)
      end
      assert_not_nil(new_rss)

      item = new_rss.items.last
      assert_not_nil(item)

      assert_slash_elements(elements, item)
    end
  end
end
