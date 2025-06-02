# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMaker10 < TestCase
    def test_supported?
      assert(RSS::Maker.supported?("1.0"))
      assert(RSS::Maker.supported?("rss1.0"))
      assert(!RSS::Maker.supported?("1.1"))
      assert(!RSS::Maker.supported?("rss1.1"))
    end

    def test_find_class
      assert_equal(RSS::Maker::RSS10, RSS::Maker["1.0"])
      assert_equal(RSS::Maker::RSS10, RSS::Maker["rss1.0"])
    end

    def test_rdf
      assert_raise(LocalJumpError) do
        RSS::Maker.make("1.0")
      end

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)
      end
      assert_equal("1.0", rss.rss_version)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.encoding = "EUC-JP"

        setup_dummy_item(maker)
      end
      assert_equal("1.0", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.standalone = "yes"

        setup_dummy_item(maker)
      end
      assert_equal("1.0", rss.rss_version)
      assert_equal("yes", rss.standalone)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.encoding = "EUC-JP"
        maker.standalone = "yes"

        setup_dummy_item(maker)
      end
      assert_equal("1.0", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)
      assert_equal("yes", rss.standalone)
    end

    def test_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"

      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description

        setup_dummy_item(maker)
      end
      channel = rss.channel
      assert_equal(about, channel.about)
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(1, channel.items.Seq.lis.size)
      assert_nil(channel.image)
      assert_nil(channel.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description

        setup_dummy_image(maker)

        setup_dummy_textinput(maker)

        setup_dummy_item(maker)
      end
      channel = rss.channel
      assert_equal(about, channel.about)
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(1, channel.items.Seq.lis.size)
      assert_equal(rss.image.about, channel.image.resource)
      assert_equal(rss.textinput.about, channel.textinput.resource)
    end

    def test_channel_language
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      language = "ja"

      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description
        maker.channel.language = language

        setup_dummy_item(maker)
      end
      channel = rss.channel
      assert_equal(language, channel.dc_language)
    end

    def test_not_valid_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"

      assert_not_set_error("maker.channel", %w(about)) do
        RSS::Maker.make("1.0") do |maker|
          # maker.channel.about = about
          maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
        end
      end

      assert_not_set_error("maker.channel", %w(title)) do
        RSS::Maker.make("1.0") do |maker|
          maker.channel.about = about
          # maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
        end
      end

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("1.0") do |maker|
          maker.channel.about = about
          maker.channel.title = title
          # maker.channel.link = link
          maker.channel.description = description
        end
      end

      assert_not_set_error("maker.channel", %w(description)) do
        RSS::Maker.make("1.0") do |maker|
          maker.channel.about = about
          maker.channel.title = title
          maker.channel.link = link
          # maker.channel.description = description
        end
      end
    end


    def test_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        maker.image.title = title
        maker.image.url = url

        setup_dummy_item(maker)
      end
      image = rss.image
      assert_equal(url, image.about)
      assert_equal(url, rss.channel.image.resource)
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)

      assert_not_set_error("maker.channel", %w(about title description)) do
        RSS::Maker.make("1.0") do |maker|
          # setup_dummy_channel(maker)
          maker.channel.link = link

          maker.image.title = title
          maker.image.url = url
        end
      end
    end

    def test_not_valid_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        # maker.image.url = url
        maker.image.title = title

        setup_dummy_item(maker)
      end
      assert_nil(rss.channel.image)
      assert_nil(rss.image)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        maker.image.url = url
        # maker.image.title = title

        setup_dummy_item(maker)
      end
      assert_nil(rss.channel.image)
      assert_nil(rss.image)

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)
          # maker.channel.link = link
          maker.channel.link = nil

          maker.image.url = url
          maker.image.title = title

          setup_dummy_item(maker)
        end
      end
    end

    def test_items(with_convenience_way=true)
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"

      assert_not_set_error("maker", %w(items)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)
        end
      end

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        maker.items.new_item do |item|
          item.title = title
          item.link = link
          # item.description = description
        end
      end
      assert_equal(1, rss.items.size)
      item = rss.items.first
      assert_equal(link, item.about)
      assert_equal(title, item.title)
      assert_equal(link, item.link)
      assert_nil(item.description)

      pubDate = Time.now

      item_size = 5
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          maker.items.new_item do |_item|
            _item.title = "#{title}#{i}"
            _item.link = "#{link}#{i}"
            _item.description = "#{description}#{i}"
            _item.date = pubDate - i
          end
        end
        maker.items.do_sort = true
      end
      assert_equal(item_size, rss.items.size)
      rss.items.each_with_index do |_item, i|
        assert_equal("#{link}#{i}", _item.about)
        assert_equal("#{title}#{i}", _item.title)
        assert_equal("#{link}#{i}", _item.link)
        assert_equal("#{description}#{i}", _item.description)
      end

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          maker.items.new_item do |_item|
            _item.title = "#{title}#{i}"
            _item.link = "#{link}#{i}"
            _item.description = "#{description}#{i}"
          end
        end
        maker.items.do_sort = Proc.new do |x, y|
          if with_convenience_way
            y.title[-1] <=> x.title[-1]
          else
            y.title {|t| t.content[-1]} <=> x.title {|t| t.content[-1]}
          end
        end
      end
      assert_equal(item_size, rss.items.size)
      rss.items.reverse.each_with_index do |_item, i|
        assert_equal("#{link}#{i}", _item.about)
        assert_equal("#{title}#{i}", _item.title)
        assert_equal("#{link}#{i}", _item.link)
        assert_equal("#{description}#{i}", _item.description)
      end

      max_size = item_size / 2
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          maker.items.new_item do |_item|
            _item.title = "#{title}#{i}"
            _item.link = "#{link}#{i}"
            _item.description = "#{description}#{i}"
          end
        end
        maker.items.max_size = max_size
      end
      assert_equal(max_size, rss.items.size)
      rss.items.each_with_index do |_item, i|
        assert_equal("#{link}#{i}", _item.about)
        assert_equal("#{title}#{i}", _item.title)
        assert_equal("#{link}#{i}", _item.link)
        assert_equal("#{description}#{i}", _item.description)
      end

      max_size = 0
      assert_not_set_error("maker", %w(items)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)

          item_size.times do |i|
            maker.items.new_item do |_item|
              _item.title = "#{title}#{i}"
              _item.link = "#{link}#{i}"
              _item.description = "#{description}#{i}"
            end
          end
          maker.items.max_size = max_size
        end
      end

      max_size = -2
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          maker.items.new_item do |_item|
            _item.title = "#{title}#{i}"
            _item.link = "#{link}#{i}"
            _item.description = "#{description}#{i}"
          end
        end
        maker.items.max_size = max_size
      end
      assert_equal(item_size + max_size + 1, rss.items.size)
      rss.items.each_with_index do |_item, i|
        assert_equal("#{link}#{i}", _item.about)
        assert_equal("#{title}#{i}", _item.title)
        assert_equal("#{link}#{i}", _item.link)
        assert_equal("#{description}#{i}", _item.description)
      end
    end

    def test_items_with_new_api_since_018
      test_items(false)
    end

    def test_not_valid_items
      title = "TITLE"
      link = "http://hoge.com/"

      assert_not_set_error("maker.item", %w(title)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)

          maker.items.new_item do |item|
            # item.title = title
            item.link = link
          end
        end
      end

      assert_not_set_error("maker.item", %w(link)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)

          maker.items.new_item do |item|
            item.title = title
            # item.link = link
          end
        end
      end

      assert_not_set_error("maker.item", %w(title link)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)

          maker.items.new_item do |item|
            # item.title = title
            # item.link = link
          end
        end
      end
    end

    def test_textinput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name

        setup_dummy_item(maker)
      end
      textinput = rss.textinput
      assert_equal(link, textinput.about)
      assert_equal(link, rss.channel.textinput.resource)
      assert_equal(title, textinput.title)
      assert_equal(name, textinput.name)
      assert_equal(description, textinput.description)
      assert_equal(link, textinput.link)

      assert_not_set_error("maker.channel", %w(about link description title)) do
        RSS::Maker.make("1.0") do |maker|
          # setup_dummy_channel(maker)

          maker.textinput.link = link
          maker.textinput.title = title
          maker.textinput.description = description
          maker.textinput.name = name
        end
      end
    end

    def test_not_valid_textinput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        # maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name

        setup_dummy_item(maker)
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.link = link
        # maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name

        setup_dummy_item(maker)
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.link = link
        maker.textinput.title = title
        # maker.textinput.description = description
        maker.textinput.name = name

        setup_dummy_item(maker)
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        # maker.textinput.name = name

        setup_dummy_item(maker)
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)
    end

  end
end
