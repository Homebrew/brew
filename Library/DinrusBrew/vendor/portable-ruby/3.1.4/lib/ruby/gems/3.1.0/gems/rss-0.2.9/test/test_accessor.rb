# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/1.0"
require "rss/2.0"
require "rss/syndication"
require "rss/image"

module RSS
  class TestAccessor < TestCase
    def test_date
      channel = Rss::Channel.new
      channel.pubDate = nil
      assert_nil(channel.pubDate)

      time = Time.now
      channel.pubDate = time
      assert_equal(time, channel.pubDate)

      time = Time.parse(Time.now.rfc822)
      channel.pubDate = time.rfc822
      assert_equal(time, channel.pubDate)

      time = Time.parse(Time.now.iso8601)
      value = time.iso8601
      assert_not_available_value("pubDate", value) do
        channel.pubDate = value
      end

      channel.do_validate = false
      time = Time.parse(Time.now.iso8601)
      value = time.iso8601
      channel.pubDate = value
      assert_equal(time, channel.pubDate)

      channel.pubDate = nil
      assert_nil(channel.pubDate)
    end

    def test_integer
      image_item = RDF::Item::ImageItem.new

      image_item.width = nil
      assert_nil(image_item.width)

      width = 10
      image_item.width = width
      assert_equal(width, image_item.width)

      width = 10.0
      image_item.width = width
      assert_equal(width, image_item.width)

      width = "10"
      image_item.width = width
      assert_equal(width.to_i, image_item.width)

      width = "10.0"
      assert_not_available_value("image:width", width) do
        image_item.width = width
      end

      image_item.do_validate = false
      width = "10.0"
      image_item.width = width
      assert_equal(width.to_i, image_item.width)

      image_item.width = nil
      assert_nil(image_item.width)
    end

    def test_positive_integer
      channel = RDF::Channel.new

      channel.sy_updateFrequency = nil
      assert_nil(channel.sy_updateFrequency)

      freq = 10
      channel.sy_updateFrequency = freq
      assert_equal(freq, channel.sy_updateFrequency)

      freq = 10.0
      channel.sy_updateFrequency = freq
      assert_equal(freq, channel.sy_updateFrequency)

      freq = "10"
      channel.sy_updateFrequency = freq
      assert_equal(freq.to_i, channel.sy_updateFrequency)

      freq = "10.0"
      assert_not_available_value("sy:updateFrequency", freq) do
        channel.sy_updateFrequency = freq
      end

      channel.do_validate = false
      freq = "10.0"
      channel.sy_updateFrequency = freq
      assert_equal(freq.to_i, channel.sy_updateFrequency)

      channel.sy_updateFrequency = nil
      assert_nil(channel.sy_updateFrequency)
    end
  end
end
