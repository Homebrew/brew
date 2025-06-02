# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestSetupMakerAtomEntry < TestCase
    def setup
      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end

      @dc_elems = {
        :title => "hoge",
        :description =>
          " XML is placing increasingly heavy loads on
          the existing technical infrastructure of the Internet.",
        :creator => "Rael Dornfest (mailto:rael@oreilly.com)",
        :subject => "XML",
        :publisher => "The O'Reilly Network",
        :contributor => "hogehoge",
        :type => "fugafuga",
        :format => "hohoho",
        :identifier => "fufufu",
        :source => "barbar",
        :language => "ja",
        :relation => "cococo",
        :rights => "Copyright (c) 2000 O'Reilly &amp; Associates, Inc.",
        :date => t,
      }
    end

    def test_setup_maker_entry(with_dc=true)
      authors = [
                 {
                   :name => "Bob",
                   :uri => "http://example.com/~bob/",
                   :email => "bob@example.com",
                 },
                 {
                   :name => "Alice",
                   :uri => "http://example.com/~alice/",
                   :email => "alice@example.com",
                 },
                ]
      categories = [
                    {
                      :term => "music",
                      :label => "Music",
                    },
                    {
                      :term => "book",
                      :scheme => "http://example.com/category/book/",
                      :label => "Book",
                    },
                   ]
      contributors = [
                      {
                        :name => "Chris",
                        :email => "chris@example.com",
                      },
                      {
                        :name => "Eva",
                        :uri => "http://example.com/~eva/",
                      },
                     ]
      id = "urn:uuid:8b105336-7e20-45fc-bb78-37fb3e1db25a"
      link = "http://hoge.com"
      published = Time.now - 60 * 3600
      rights = "Copyrights (c) 2007 Alice and Bob"
      description = "fugafugafugafuga"
      title = "fugafuga"
      updated = Time.now

      feed = RSS::Maker.make("atom:entry") do |maker|
        maker.items.new_item do |item|
          authors.each do |author_info|
            item.authors.new_author do |author|
              author_info.each do |key, value|
                author.__send__("#{key}=", value)
              end
            end
          end

          categories.each do |category_info|
            item.categories.new_category do |category|
              category_info.each do |key, value|
                category.__send__("#{key}=", value)
              end
            end
          end

          contributors.each do |contributor_info|
            item.contributors.new_contributor do |contributor|
              contributor_info.each do |key, value|
                contributor.__send__("#{key}=", value)
              end
            end
          end

          item.id = id
          item.link = link
          item.published = published
          item.rights = rights
          item.description = description
          item.title = title
          item.updated = updated

          if with_dc
            @dc_elems.each do |var, value|
              if var == :date
                item.new_dc_date(value)
              else
                item.__send__("dc_#{var}=", value)
              end
            end
          end
        end
      end
      assert_not_nil(feed)

      new_feed = RSS::Maker.make("atom:entry") do |maker|
        feed.setup_maker(maker)
      end
      assert_not_nil(new_feed)

      new_authors = new_feed.authors.collect do |author|
        {
          :name => author.name.content,
          :uri => author.uri.content,
          :email => author.email.content,
        }
      end
      assert_equal(authors, new_authors)

      new_categories = new_feed.categories.collect do |category|
        {
          :term => category.term,
          :scheme => category.scheme,
          :label => category.label,
        }.reject {|key, value| value.nil?}
      end
      assert_equal(categories, new_categories)

      new_contributors = new_feed.contributors.collect do |contributor|
        info = {}
        info[:name] = contributor.name.content
        info[:uri] = contributor.uri.content if contributor.uri
        info[:email] = contributor.email.content if contributor.email
        info
      end
      assert_equal(contributors, new_contributors)

      assert_equal(id, new_feed.id.content)
      assert_equal(link, new_feed.link.href)
      assert_equal(published, new_feed.published.content)
      assert_equal(rights, new_feed.rights.content)
      assert_equal(description, new_feed.summary.content)
      assert_equal(title, new_feed.title.content)
      assert_equal(updated, new_feed.updated.content)

      if with_dc
        @dc_elems.each do |var, value|
          if var == :date
            assert_equal([updated, value],
                         new_feed.dc_dates.collect {|date| date.value})
          else
            assert_equal(value, new_feed.__send__("dc_#{var}"))
          end
        end
      end

      assert_equal(1, new_feed.items.size)
    end

    def test_setup_maker_entry_without_dc
      test_setup_maker_entry(false)
    end

    def test_setup_maker_items(for_backward_compatibility=false)
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"
      updated = Time.now

      item_size = 5
      feed = RSS::Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)

        item_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{title}#{i}"
            item.link = "#{link}#{i}"
            item.description = "#{description}#{i}"
            item.updated = updated + i * 60
          end
        end
      end

      new_feed = RSS::Maker.make("atom:entry") do |maker|
        feed.items.each do |item|
          if for_backward_compatibility
            item.setup_maker(maker)
          else
            item.setup_maker(maker.items)
          end
        end

        feed.items.clear
        feed.setup_maker(maker)
      end

      assert_equal(1, new_feed.items.size)
      new_feed.items[0..1].each_with_index do |item, i|
        assert_equal("#{title}#{i}", item.title.content)
        assert_equal("#{link}#{i}", item.link.href)
        assert_equal("#{description}#{i}", item.summary.content)
        assert_equal(updated + i * 60, item.updated.content)
      end
    end

    def test_setup_maker_items_sort
      title = "TITLE"
      link = "http://hoge.com/"
      summary = "text hoge fuga"
      updated = Time.now

      feed_size = 5
      feed = RSS::Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)

        feed_size.times do |i|
          entry_class = RSS::Atom::Entry
          entry = entry_class.new
          entry.title = entry_class::Title.new(:content => "#{title}#{i}")
          entry.links << entry_class::Link.new(:href => "#{link}#{i}")
          entry.summary = entry_class::Summary.new(:content => "#{summary}#{i}")
          entry.updated = entry_class::Updated.new(:content => updated + i * 60)
          entry.setup_maker(maker.items)
        end
        maker.items.do_sort = false
      end
      assert_equal(1, feed.items.size)

      assert_equal("#{title}0", feed.title.content)
      assert_equal("#{link}0", feed.link.href)
      assert_equal("#{summary}0", feed.summary.content)


      feed = RSS::Maker.make("atom:entry") do |maker|
        setup_dummy_channel_atom(maker)

        feed_size.times do |i|
          entry_class = RSS::Atom::Entry
          entry = entry_class.new
          entry.title = entry_class::Title.new(:content => "#{title}#{i}")
          entry.links << entry_class::Link.new(:href => "#{link}#{i}")
          entry.summary = entry_class::Summary.new(:content => "#{summary}#{i}")
          entry.updated = entry_class::Updated.new(:content => updated + i * 60)
          entry.setup_maker(maker.items)
        end
        maker.items.do_sort = true
      end
      assert_equal(1, feed.items.size)

      assert_equal("#{title}#{feed_size - 1}", feed.title.content)
      assert_equal("#{link}#{feed_size - 1}", feed.link.href)
      assert_equal("#{summary}#{feed_size - 1}", feed.summary.content)
    end

    def test_setup_maker_items_backward_compatibility
      test_setup_maker_items(true)
    end

    def test_setup_maker
      encoding = "EUC-JP"
      standalone = true

      href = 'a.xsl'
      type = 'text/xsl'
      title = 'sample'
      media = 'printer'
      charset = 'UTF-8'
      alternate = 'yes'

      feed = RSS::Maker.make("atom:entry") do |maker|
        maker.encoding = encoding
        maker.standalone = standalone

        maker.xml_stylesheets.new_xml_stylesheet do |xss|
          xss.href = href
          xss.type = type
          xss.title = title
          xss.media = media
          xss.charset = charset
          xss.alternate = alternate
        end

        setup_dummy_channel_atom(maker)
        setup_dummy_item_atom(maker)
      end
      assert_not_nil(feed)

      new_feed = RSS::Maker.make("atom:entry") do |maker|
        feed.setup_maker(maker)
      end

      assert_equal(["atom", "1.0", "entry"], new_feed.feed_info)
      assert_equal(encoding, new_feed.encoding)
      assert_equal(standalone, new_feed.standalone)

      xss = new_feed.xml_stylesheets.first
      assert_equal(1, new_feed.xml_stylesheets.size)
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)
    end

    def test_setup_maker_full
      encoding = "EUC-JP"
      standalone = true

      href = 'a.xsl'
      type = 'text/xsl'
      title = 'sample'
      media = 'printer'
      charset = 'UTF-8'
      alternate = 'yes'

      channel_about = "http://hoge.com"
      channel_title = "fugafuga"
      channel_link = "http://hoge.com"
      channel_description = "fugafugafugafuga"
      channel_author = "Bob"

      image_url = "http://hoge.com/hoge.png"

      item_title = "TITLE"
      item_link = "http://hoge.com/"
      item_description = "text hoge fuga"

      entry_size = 5
      feed = RSS::Maker.make("atom:entry") do |maker|
        maker.encoding = encoding
        maker.standalone = standalone

        maker.xml_stylesheets.new_xml_stylesheet do |xss|
          xss.href = href
          xss.type = type
          xss.title = title
          xss.media = media
          xss.charset = charset
          xss.alternate = alternate
        end

        maker.channel.about = channel_about
        maker.channel.title = channel_title
        maker.channel.link = channel_link
        maker.channel.description = channel_description
        maker.channel.author = channel_author
        @dc_elems.each do |var, value|
          maker.channel.__send__("dc_#{var}=", value)
        end

        maker.image.url = image_url

        entry_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{item_title}#{i}"
            item.link = "#{item_link}#{i}"
            item.description = "#{item_description}#{i}"

            @dc_elems.each do |var, value|
              item.__send__("dc_#{var}=", value)
            end
          end
        end
      end

      new_feed = RSS::Maker.make("atom:entry") do |maker|
        feed.setup_maker(maker)
      end

      assert_equal(["atom", "1.0", "entry"], new_feed.feed_info)
      assert_equal(encoding, new_feed.encoding)
      assert_equal(standalone, new_feed.standalone)

      xss = new_feed.xml_stylesheets.first
      assert_equal(1, new_feed.xml_stylesheets.size)
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)

      assert_equal("#{item_title}0", new_feed.title.content)
      assert_equal("#{item_link}0", new_feed.link.href)
      assert_equal("#{item_description}0", new_feed.summary.content)
      @dc_elems.each do |var, value|
        assert_equal(value, new_feed.__send__("dc_#{var}"))
      end
      assert_equal(1, new_feed.items.size)
    end
  end
end
