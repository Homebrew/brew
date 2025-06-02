# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerAtomFeed < TestCase
    def test_supported?
      assert(RSS::Maker.supported?("atom"))
      assert(RSS::Maker.supported?("atom:feed"))
      assert(RSS::Maker.supported?("atom1.0"))
      assert(RSS::Maker.supported?("atom1.0:feed"))
      assert(!RSS::Maker.supported?("atom2.0"))
      assert(!RSS::Maker.supported?("atom2.0:feed"))
    end

    def test_find_class
      assert_equal(RSS::Maker::Atom::Feed, RSS::Maker["atom"])
      assert_equal(RSS::Maker::Atom::Feed, RSS::Maker["atom:feed"])
      assert_equal(RSS::Maker::Atom::Feed, RSS::Maker["atom1.0"])
      assert_equal(RSS::Maker::Atom::Feed, RSS::Maker["atom1.0:feed"])
    end

    def test_root_element
      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
      end
      assert_equal(["atom", "1.0", "feed"], feed.feed_info)

      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.encoding = "EUC-JP"
      end
      assert_equal(["atom", "1.0", "feed"], feed.feed_info)
      assert_equal("EUC-JP", feed.encoding)

      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.standalone = "yes"
      end
      assert_equal(["atom", "1.0", "feed"], feed.feed_info)
      assert_equal("yes", feed.standalone)

      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.encoding = "EUC-JP"
        maker.standalone = "yes"
      end
      assert_equal(["atom", "1.0", "feed"], feed.feed_info)
      assert_equal("EUC-JP", feed.encoding)
      assert_equal("yes", feed.standalone)
    end

    def test_invalid_feed
      assert_not_set_error("maker.channel", %w(id title author updated)) do
        Maker.make("atom") do |maker|
        end
      end

      assert_not_set_error("maker.channel", %w(id title updated)) do
        Maker.make("atom") do |maker|
          maker.channel.author = "foo"
        end
      end

      assert_not_set_error("maker.channel", %w(title updated)) do
        Maker.make("atom") do |maker|
          maker.channel.author = "foo"
          maker.channel.id = "http://example.com"
        end
      end

      assert_not_set_error("maker.channel", %w(updated)) do
        Maker.make("atom") do |maker|
          maker.channel.author = "foo"
          maker.channel.id = "http://example.com"
          maker.channel.title = "Atom Feed"
        end
      end

      assert_not_set_error("maker.channel", %w(author)) do
        Maker.make("atom") do |maker|
          maker.channel.id = "http://example.com"
          maker.channel.title = "Atom Feed"
          maker.channel.updated = Time.now
        end
      end

      feed = Maker.make("atom") do |maker|
        maker.channel.author = "Foo"
        maker.channel.id = "http://example.com"
        maker.channel.title = "Atom Feed"
        maker.channel.updated = Time.now
      end
      assert_not_nil(feed)
    end

    def test_author
      assert_maker_atom_persons("feed",
                                ["channel", "authors"],
                                ["authors"],
                                "maker.channel.author") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_not_set_error("maker.channel", %w(author)) do
        RSS::Maker.make("atom") do |maker|
          setup_dummy_channel_atom(maker)
          setup_dummy_item_atom(maker)
          maker.channel.authors.clear
        end
      end

      assert_maker_atom_persons("feed",
                                ["items", "first", "authors"],
                                ["entries", "first", "authors"],
                                "maker.item.author") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_persons("feed",
                                ["items", "first", "source", "authors"],
                                ["entries", "first", "source", "authors"],
                                "maker.item.source.author") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_category
      assert_maker_atom_categories("feed",
                                   ["channel", "categories"],
                                   ["categories"],
                                   "maker.channel.category") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_categories("feed",
                                   ["items", "first", "categories"],
                                   ["entries", "first", "categories"],
                                   "maker.item.category") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_categories("feed",
                                   ["items", "first", "source", "categories"],
                                   ["entries", "first", "source", "categories"],
                                   "maker.item.source.category") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_contributor
      assert_maker_atom_persons("feed",
                                ["channel", "contributors"],
                                ["contributors"],
                                "maker.channel.contributor") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_persons("feed",
                                ["items", "first", "contributors"],
                                ["entries", "first", "contributors"],
                                "maker.item.contributor") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_persons("feed",
                                ["items", "first", "source", "contributors"],
                                ["entries", "first", "source", "contributors"],
                                "maker.item.source.contributor") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_generator
      assert_maker_atom_generator("feed",
                                  ["channel", "generator"],
                                  ["generator"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_generator("feed",
                                  ["items", "first", "source", "generator"],
                                  ["entries", "first", "source", "generator"],
                                  "maker.item.source.generator") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_icon
      assert_maker_atom_icon("feed", ["channel"], ["icon"], "icon") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_icon("feed",
                             ["items", "first", "source", "icon"],
                             ["entries", "first", "source", "icon"],
                             nil, "maker.item.source.icon") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_link
      assert_maker_atom_links("feed",
                              ["channel", "links"],
                              ["links"],
                              "maker.channel.link") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_links("feed",
                              ["items", "first", "links"],
                              ["entries", "first", "links"],
                              "maker.item.link") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_links("feed",
                              ["items", "first", "source", "links"],
                              ["entries", "first", "source", "links"],
                              "maker.item.source.link", true) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_logo
      assert_maker_atom_logo("feed", ["channel"], ["logo"], "logo") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_logo("feed", ["image"], ["logo"], "url") do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_logo("feed",
                             ["items", "first", "source", "logo"],
                             ["entries", "first", "source", "logo"],
                             nil, "maker.item.source.logo") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_rights
      assert_maker_atom_text_construct("feed",
                                       ["channel", "copyright"],
                                       ["rights"]) do |maker|
        setup_dummy_channel_atom(maker)
      end

      assert_maker_atom_text_construct("feed",
                                       ["items", "first", "rights"],
                                       ["entries", "first", "rights"],
                                       nil, nil, "maker.item.rights"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_text_construct("feed",
                                       ["items", "first", "source", "rights"],
                                       ["entries", "first", "source", "rights"],
                                       nil, nil, "maker.item.source.rights"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_subtitle
      assert_maker_atom_text_construct("feed",
                                       ["channel", "subtitle"],
                                       ["subtitle"],
                                       nil, nil,
                                       "maker.channel.description") do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.description = nil
      end

      assert_maker_atom_text_construct("feed",
                                       ["channel", "subtitle"],
                                       ["subtitle"],
                                       nil, nil,
                                       "maker.channel.description") do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.description {|d| d.content = nil}
      end

      assert_maker_atom_text_construct("feed",
                                       ["items", "first", "source", "subtitle"],
                                       ["entries", "first",
                                        "source", "subtitle"],
                                       nil, nil,
                                       "maker.item.source.subtitle") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_title
      assert_maker_atom_text_construct("feed",
                                       ["channel", "title"], ["title"],
                                       "maker.channel", ["title"]) do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.title = nil
      end

      assert_maker_atom_text_construct("feed",
                                       ["items", "first", "title"],
                                       ["entries", "first", "title"],
                                       "maker.item", ["title"],
                                       "maker.item.title") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.items.first.title = nil
      end

      assert_maker_atom_text_construct("feed",
                                       ["items", "first", "source", "title"],
                                       ["entries", "first", "source", "title"],
                                       nil, nil, "maker.item.source.title"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_updated
      assert_maker_atom_date_construct("feed",
                                       ["channel", "updated"], ["updated"],
                                       "maker.channel", ["updated"]) do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.updated = nil
      end

      assert_maker_atom_date_construct("feed",
                                       ["items", "first", "updated"],
                                       ["entries", "first", "updated"],
                                       "maker.item", ["updated"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.items.first.updated = nil
      end

      assert_maker_atom_date_construct("feed",
                                       ["items", "first", "source", "updated"],
                                       ["entries", "first", "source", "updated"]
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_published
      assert_maker_atom_date_construct("feed",
                                       ["items", "first", "published"],
                                       ["entries", "first", "published"]
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_summary
      assert_maker_atom_text_construct("feed",
                                       ["items", "first", "description"],
                                       ["entries", "first", "summary"],
                                       nil, nil, "maker.item.description"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_content
      assert_maker_atom_content("feed",
                                ["items", "first", "content"],
                                ["entries", "first", "content"],
                                "maker.item.content") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_id
      assert_maker_atom_id("feed",
                           ["items", "first", "source"],
                           ["entries", "first", "source"],
                           "maker.item.source") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_language
      language = "ja"
      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.language = "ja"
      end
      assert_equal(language, feed.dc_language)
    end

    def test_date
      date = Time.parse("2004/11/1 10:10")
      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.items.new_item do |item|
          item.link = "http://example.com/article.html"
          item.title = "sample article"
          item.date = date
        end
      end
      assert_equal(date, feed.items[0].updated.content)
      assert_equal([date], feed.items[0].dc_dates.collect {|_date| _date.value})
    end

    def test_channel_dc_date
      date = Time.parse("2004/11/1 10:10")
      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.updated = nil
        maker.channel.dc_date = date
        setup_dummy_item_atom(maker)
      end
      assert_equal(date, feed.updated.content)
      assert_equal([date], feed.dc_dates.collect {|_date| _date.value})
    end

    def test_item_dc_date
      date = Time.parse("2004/11/1 10:10")
      feed = Maker.make("atom") do |maker|
        setup_dummy_channel_atom(maker)
        maker.items.new_item do |item|
          item.link = "http://example.com/article.html"
          item.title = "sample article"
          item.dc_date = date
        end
      end
      assert_equal(date, feed.items[0].updated.content)
      assert_equal([date], feed.items[0].dc_dates.collect {|_date| _date.value})
    end
  end
end
