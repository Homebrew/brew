# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerImage < TestCase

    def setup
      @uri = "http://web.resource.org/rss/1.0/modules/image/"

      @favicon_infos = {
        "about" => "http://www.kuro5hin.org/favicon.ico",
        "image_size" => "small",
        "dc_title" => "example",
      }
      @item_infos = {
        "about" => "http://www.example.org/item.png",
        "resource" => "http://www.example.org/item",
        "dc_title" => "Example Image",
        "image_width" => "100",
        "image_height" => "65",
      }
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        @favicon_infos.each do |name, value|
          maker.channel.image_favicon.__send__("#{name}=", value)
        end

        setup_dummy_image(maker)

        setup_dummy_item(maker)
        item = maker.items.last
        @item_infos.each do |name, value|
          item.image_item.__send__("#{name}=", value)
        end

        setup_dummy_textinput(maker)
      end

      setup_rss = RSS::Maker.make("1.0") do |maker|
        rss.setup_maker(maker)
      end

      [rss, setup_rss].each_with_index do |target, i|
        favicon = target.channel.image_favicon
        assert_equal(@favicon_infos["about"], favicon.about)
        assert_equal(@favicon_infos["image_size"], favicon.image_size)
        assert_equal(@favicon_infos["dc_title"], favicon.dc_title)

        item = target.items.last.image_item
        assert_equal(@item_infos["about"], item.about)
        assert_equal(@item_infos["resource"], item.resource)
        assert_equal(@item_infos["image_width"].to_i, item.image_width)
        assert_equal(@item_infos["image_height"].to_i, item.image_height)
        assert_equal(@item_infos["dc_title"], item.dc_title)
      end
    end
  end
end
