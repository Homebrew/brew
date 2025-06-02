# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerTrackBack < TestCase

    def setup
      @uri = "http://madskills.com/public/xml/rss/module/trackback/"

      @elements = {
        :ping => "http://bar.com/tb.cgi?tb_id=rssplustrackback",
        :abouts => [
          "http://foo.com/trackback/tb.cgi?tb_id=20020923",
          "http://bar.com/trackback/tb.cgi?tb_id=20041114",
        ],
      }
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        setup_dummy_item(maker)
        item = maker.items.last
        item.trackback_ping = @elements[:ping]
        @elements[:abouts].each do |about|
          item.trackback_abouts.new_about do |new_about|
            new_about.value = about
          end
        end
      end
      assert_trackback(@elements, rss.items.last)
    end

    private
    def accessor_name(name)
      "trackback_#{name}"
    end
  end
end
