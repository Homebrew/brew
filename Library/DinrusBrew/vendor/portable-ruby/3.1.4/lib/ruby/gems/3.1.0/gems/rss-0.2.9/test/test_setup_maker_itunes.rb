# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestSetupMakerITunes < TestCase
    def test_setup_maker_simple
      author = "John Doe"
      block = true
      categories = ["Audio Blogs"]
      image = "http://example.com/podcasts/everything/AllAboutEverything.jpg"
      duration = "4:05"
      duration_components = [0, 4, 5]
      explicit = true
      keywords = ["salt", "pepper", "shaker", "exciting"]
      owner = {:name => "John Doe", :email => "john.doe@example.com"}
      subtitle = "A show about everything"
      summary = "All About Everything is a show about " +
        "everything. Each week we dive into any " +
        "subject known to man and talk about it " +
        "as much as we can. Look for our Podcast " +
        "in the iTunes Music Store"

      feed = RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        channel = maker.channel
        channel.itunes_author = author
        channel.itunes_block = block
        categories.each do |category|
          channel.itunes_categories.new_category.text = category
        end
        channel.itunes_image = image
        channel.itunes_explicit = explicit
        channel.itunes_keywords = keywords
        channel.itunes_owner.itunes_name = owner[:name]
        channel.itunes_owner.itunes_email = owner[:email]
        channel.itunes_subtitle = subtitle
        channel.itunes_summary = summary

        item = maker.items.last
        item.itunes_image = image
        item.itunes_author = author
        item.itunes_block = block
        item.itunes_duration = duration
        item.itunes_explicit = explicit
        item.itunes_keywords = keywords
        item.itunes_subtitle = subtitle
        item.itunes_summary = summary
      end
      assert_not_nil(feed)

      new_feed = RSS::Maker.make("rss2.0") do |maker|
        feed.setup_maker(maker)
      end
      assert_not_nil(new_feed)

      channel = new_feed.channel
      item = new_feed.items.last

      assert_equal(author, channel.itunes_author)
      assert_equal(author, item.itunes_author)

      assert_equal(block, channel.itunes_block?)
      assert_equal(block, item.itunes_block?)

      assert_equal(categories,
                   collect_itunes_categories(channel.itunes_categories))

      assert_equal(image, channel.itunes_image.href)
      assert_equal(image, item.itunes_image.href)

      assert_equal(duration_components,
                   [item.itunes_duration.hour,
                    item.itunes_duration.minute,
                    item.itunes_duration.second])

      assert_equal(explicit, channel.itunes_explicit?)
      assert_equal(explicit, item.itunes_explicit?)

      assert_equal(keywords, channel.itunes_keywords)
      assert_equal(keywords, item.itunes_keywords)

      assert_equal(owner,
                   {
                     :name => channel.itunes_owner.itunes_name,
                     :email => channel.itunes_owner.itunes_email
                   })

      assert_equal(subtitle, channel.itunes_subtitle)
      assert_equal(subtitle, item.itunes_subtitle)

      assert_equal(summary, channel.itunes_summary)
      assert_equal(summary, item.itunes_summary)
    end

    def test_setup_maker_with_nested_categories
      categories = [["Arts & Entertainment", "Games"],
                    ["Technology", "Computers"],
                    "Audio Blogs"]

      feed = RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        channel = maker.channel
        categories.each do |category|
          target = channel.itunes_categories
          if category.is_a?(Array)
            category.each do |sub_category|
              target = target.new_category
              target.text = sub_category
            end
          else
            target.new_category.text = category
          end
        end
      end
      assert_not_nil(feed)

      new_feed = RSS::Maker.make("rss2.0") do |maker|
        feed.setup_maker(maker)
      end
      assert_not_nil(new_feed)

      channel = new_feed.channel

      assert_equal(categories,
                   collect_itunes_categories(channel.itunes_categories))
    end

    private
    def collect_itunes_categories(categories)
      categories.collect do |c|
        rest = collect_itunes_categories(c.itunes_categories)
        if rest.empty?
          c.text
        else
          [c.text, *rest]
        end
      end
    end
  end
end
