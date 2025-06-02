# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerSyndication < TestCase

    def setup
      @uri = "http://purl.org/rss/1.0/modules/syndication/"

      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end

      @elements = {
        :updatePeriod => "hourly",
        :updateFrequency => "2",
        :updateBase => t,
      }
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        set_elements(maker.channel)
        setup_dummy_item(maker)
      end
      assert_syndication(@elements, rss.channel)
    end

    private
    def accessor_name(name)
      "sy_#{name}"
    end

    def set_elements(target)
      @elements.each do |name, value|
        target.__send__("#{accessor_name(name)}=", value)
      end
    end

  end
end
