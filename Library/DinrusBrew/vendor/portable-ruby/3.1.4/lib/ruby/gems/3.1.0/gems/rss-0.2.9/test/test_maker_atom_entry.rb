# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerAtomEntry < TestCase
    def test_supported?
      assert(RSS::Maker.supported?("atom:entry"))
      assert(RSS::Maker.supported?("atom1.0:entry"))
      assert(!RSS::Maker.supported?("atom2.0:entry"))
    end

    def test_find_class
      assert_equal(RSS::Maker::Atom::Entry, RSS::Maker["atom:entry"])
      assert_equal(RSS::Maker::Atom::Entry, RSS::Maker["atom1.0:entry"])
    end

    def test_root_element
      entry = Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
      assert_equal(["atom", "1.0", "entry"], entry.feed_info)

      entry = Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.encoding = "EUC-JP"
      end
      assert_equal(["atom", "1.0", "entry"], entry.feed_info)
      assert_equal("EUC-JP", entry.encoding)

      entry = Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.standalone = "yes"
      end
      assert_equal(["atom", "1.0", "entry"], entry.feed_info)
      assert_equal("yes", entry.standalone)

      entry = Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.encoding = "EUC-JP"
        maker.standalone = "yes"
      end
      assert_equal(["atom", "1.0", "entry"], entry.feed_info)
      assert_equal("EUC-JP", entry.encoding)
      assert_equal("yes", entry.standalone)
    end

    def test_invalid_feed
      assert_not_set_error("maker.item", %w(id title author updated)) do
        Maker.make("atom:entry") do |maker|
        end
      end

      assert_not_set_error("maker.item", %w(id title updated)) do
        Maker.make("atom:entry") do |maker|
          maker.channel.author = "foo"
        end
      end

      assert_not_set_error("maker.item", %w(title updated)) do
        Maker.make("atom:entry") do |maker|
          maker.channel.author = "foo"
          maker.channel.id = "http://example.com"
        end
      end

      assert_not_set_error("maker.item", %w(updated)) do
        Maker.make("atom:entry") do |maker|
          maker.channel.author = "foo"
          maker.channel.id = "http://example.com"
          maker.channel.title = "Atom Feed"
        end
      end

      assert_not_set_error("maker.item", %w(author)) do
        Maker.make("atom:entry") do |maker|
          maker.channel.id = "http://example.com"
          maker.channel.title = "Atom Feed"
          maker.channel.updated = Time.now
        end
      end

      entry = Maker.make("atom:entry") do |maker|
        maker.channel.author = "Foo"
        maker.channel.id = "http://example.com"
        maker.channel.title = "Atom Feed"
        maker.channel.updated = Time.now
      end
      assert_not_nil(entry)
    end

    def test_author
      assert_maker_atom_persons("entry",
                                ["channel", "authors"],
                                ["authors"],
                                "maker.channel.author") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_persons("entry",
                                ["items", "first", "authors"],
                                ["authors"],
                                "maker.item.author",
                                "maker.item", ["author"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.authors.clear
        maker.items.first.authors.clear
      end

      assert_maker_atom_persons("entry",
                                ["items", "first", "source", "authors"],
                                ["source", "authors"],
                                "maker.item.source.author") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_category
      assert_maker_atom_categories("entry",
                                   ["channel", "categories"],
                                   ["categories"],
                                   "maker.channel.category") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_categories("entry",
                                   ["items", "first", "categories"],
                                   ["categories"],
                                   "maker.item.category") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_categories("entry",
                                   ["items", "first", "source", "categories"],
                                   ["source", "categories"],
                                   "maker.item.source.category") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_content
      assert_maker_atom_content("entry",
                                ["items", "first", "content"],
                                ["content"],
                                "maker.item.content") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_contributor
      assert_maker_atom_persons("entry",
                                ["channel", "contributors"],
                                ["contributors"],
                                "maker.channel.contributor") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_persons("entry",
                                ["items", "first", "contributors"],
                                ["contributors"],
                                "maker.item.contributor") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_persons("entry",
                                ["items", "first", "source", "contributors"],
                                ["source", "contributors"],
                                "maker.item.source.contributor") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_link
      assert_maker_atom_links("entry",
                              ["channel", "links"],
                              ["links"],
                              "maker.channel.link") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.links.clear
        maker.items.first.links.clear
      end

      assert_maker_atom_links("entry",
                              ["items", "first", "links"],
                              ["links"],
                              "maker.item.link") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.links.clear
        maker.items.first.links.clear
      end

      assert_maker_atom_links("entry",
                              ["items", "first", "source", "links"],
                              ["source", "links"],
                              "maker.item.source.link", true) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_published
      assert_maker_atom_date_construct("entry",
                                       ["items", "first", "published"],
                                       ["published"]
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_rights
      assert_maker_atom_text_construct("entry",
                                       ["channel", "copyright"],
                                       ["rights"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_text_construct("entry",
                                       ["items", "first", "rights"],
                                       ["rights"],
                                       nil, nil, "maker.item.rights"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end

      assert_maker_atom_text_construct("entry",
                                       ["items", "first", "source", "rights"],
                                       ["source", "rights"],
                                       nil, nil, "maker.item.source.rights"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end


    def test_source_generator
      assert_maker_atom_generator("entry",
                                  ["items", "first", "source", "generator"],
                                  ["source", "generator"],
                                  "maker.item.source.generator") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_source_icon
      assert_maker_atom_icon("entry",
                             ["items", "first", "source", "icon"],
                             ["source", "icon"],
                             nil, "maker.item.source.icon") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_source_id
      assert_maker_atom_id("entry",
                           ["items", "first", "source"],
                           ["source"],
                           "maker.item.source") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_source_logo
      assert_maker_atom_logo("entry",
                             ["items", "first", "source", "logo"],
                             ["source", "logo"],
                             nil,
                             "maker.item.source.logo") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_source_subtitle
      assert_maker_atom_text_construct("entry",
                                       ["items", "first", "source", "subtitle"],
                                       ["source", "subtitle"],
                                       nil, nil,
                                       "maker.item.source.subtitle") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_summary
      assert_maker_atom_text_construct("entry",
                                       ["items", "first", "description"],
                                       ["summary"],
                                       nil, nil, "maker.item.description"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_title
      assert_maker_atom_text_construct("entry",
                                       ["channel", "title"], ["title"],
                                       "maker.item", ["title"],
                                       "maker.channel.title") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.title = nil
        maker.items.first.title = nil
      end

      assert_maker_atom_text_construct("entry",
                                       ["items", "first", "title"],
                                       ["title"],
                                       "maker.item", ["title"],
                                       "maker.item.title") do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.title = nil
        maker.items.first.title = nil
      end

      assert_maker_atom_text_construct("entry",
                                       ["items", "first", "source", "title"],
                                       ["source", "title"],
                                       nil, nil, "maker.item.source.title"
                                       ) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_updated
      assert_maker_atom_date_construct("entry",
                                       ["channel", "updated"], ["updated"],
                                       "maker.item", ["updated"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.updated = nil
        maker.items.first.updated = nil
      end

      assert_maker_atom_date_construct("entry",
                                       ["items", "first", "updated"],
                                       ["updated"],
                                       "maker.item", ["updated"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
        maker.channel.updated = nil
        maker.items.first.updated = nil
      end

      assert_maker_atom_date_construct("entry",
                                       ["items", "first", "source", "updated"],
                                       ["source", "updated"]) do |maker|
        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
    end

    def test_date
      date = Time.parse("2004/11/1 10:10")
      feed = Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)
        maker.channel.date = nil
        maker.items.new_item do |item|
          item.link = "http://example.com/article.html"
          item.title = "Sample Article"
          item.date = date
        end
      end
      assert_equal(date, feed.items[0].updated.content)
      assert_equal([date], feed.items[0].dc_dates.collect {|_date| _date.value})
    end
  end
end
