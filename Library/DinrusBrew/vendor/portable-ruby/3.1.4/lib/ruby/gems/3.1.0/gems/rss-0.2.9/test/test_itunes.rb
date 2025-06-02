# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/2.0"
require "rss/itunes"

module RSS
  class TestITunes < TestCase
    def test_author
      assert_itunes_author(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end

      assert_itunes_author(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_block
      assert_itunes_block(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_category
      assert_itunes_category(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end
    end

    def test_image
      assert_itunes_image(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end

      assert_itunes_image(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_duration
      assert_itunes_duration(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_explicit
      assert_itunes_explicit(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end

      assert_itunes_explicit(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_keywords
      assert_itunes_keywords(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end

      assert_itunes_keywords(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_new_feed_url
      assert_itunes_new_feed_url(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end
    end

    def test_owner
      assert_itunes_owner(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end
    end

    def test_subtitle
      assert_itunes_subtitle(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end

      assert_itunes_subtitle(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    def test_summary
      assert_itunes_summary(%w(channel)) do |content, xmlns|
        make_rss20(make_channel20(content), xmlns)
      end

      assert_itunes_summary(%w(items last)) do |content, xmlns|
        make_rss20(make_channel20(make_item20(content)), xmlns)
      end
    end

    private
    def itunes_rss20_parse(content, &maker)
      xmlns = {"itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd"}
      rss20_xml = maker.call(content, xmlns)
      ::RSS::Parser.parse(rss20_xml)
    end

    def assert_itunes_author(readers, &rss20_maker)
      _wrap_assertion do
        author = "John Lennon"
        rss20 = itunes_rss20_parse(tag("itunes:author", author), &rss20_maker)
        target = chain_reader(rss20, readers)
        assert_equal(author, target.itunes_author)
      end
    end

    def _assert_itunes_block(value, boolean_value, readers, &rss20_maker)
      rss20 = itunes_rss20_parse(tag("itunes:block", value), &rss20_maker)
      target = chain_reader(rss20, readers)
      assert_equal(value, target.itunes_block)
      assert_equal(boolean_value, target.itunes_block?)
    end

    def assert_itunes_block(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_block("yes", true, readers, &rss20_maker)
        _assert_itunes_block("Yes", true, readers, &rss20_maker)
        _assert_itunes_block("no", false, readers, &rss20_maker)
        _assert_itunes_block("", false, readers, &rss20_maker)
      end
    end

    def _assert_itunes_category(categories, readers, &rss20_maker)
      cats = categories.collect do |category|
        if category.is_a?(Array)
          category, sub_category = category
          tag("itunes:category",
              tag("itunes:category", nil, {"text" => sub_category}),
              {"text" => category})
        else
          tag("itunes:category", nil, {"text" => category})
        end
      end.join
      rss20 = itunes_rss20_parse(cats, &rss20_maker)
      target = chain_reader(rss20, readers)
      actual_categories = target.itunes_categories.collect do |category|
        cat = category.text
        if category.itunes_categories.empty?
          cat
        else
          [cat, *category.itunes_categories.collect {|c| c.text}]
        end
      end
      assert_equal(categories, actual_categories)
    end

    def assert_itunes_category(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_category(["Audio Blogs"], readers, &rss20_maker)
        _assert_itunes_category([["Arts & Entertainment", "Games"]],
                                readers, &rss20_maker)
        _assert_itunes_category([["Arts & Entertainment", "Games"],
                                 ["Technology", "Computers"],
                                 "Audio Blogs"],
                                readers, &rss20_maker)
      end
    end

    def assert_itunes_image(readers, &rss20_maker)
      _wrap_assertion do
        url = "http://example.com/podcasts/everything/AllAboutEverything.jpg"
        content = tag("itunes:image", nil, {"href" => url})
        rss20 = itunes_rss20_parse(content, &rss20_maker)
        target = chain_reader(rss20, readers)
        assert_not_nil(target.itunes_image)
        assert_equal(url, target.itunes_image.href)

        assert_missing_attribute("image", "href") do
          content = tag("itunes:image")
          itunes_rss20_parse(content, &rss20_maker)
        end
      end
    end

    def _assert_itunes_duration(hour, minute, second, value,
                                readers, &rss20_maker)
      content = tag("itunes:duration", value)
      rss20 = itunes_rss20_parse(content, &rss20_maker)
      duration = chain_reader(rss20, readers).itunes_duration
      assert_equal(value, duration.content)
      assert_equal(hour, duration.hour)
      assert_equal(minute, duration.minute)
      assert_equal(second, duration.second)
    end

    def _assert_itunes_duration_not_available_value(value, &rss20_maker)
      assert_not_available_value("duration", value) do
        content = tag("itunes:duration", value)
        itunes_rss20_parse(content, &rss20_maker)
      end
    end

    def assert_itunes_duration(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_duration(7, 14, 5, "07:14:05", readers, &rss20_maker)
        _assert_itunes_duration(7, 14, 5, "7:14:05", readers, &rss20_maker)
        _assert_itunes_duration(0, 4, 55, "04:55", readers, &rss20_maker)
        _assert_itunes_duration(0, 4, 5, "4:05", readers, &rss20_maker)
        _assert_itunes_duration(0, 0, 5, "5", readers, &rss20_maker)
        _assert_itunes_duration(0, 3, 15, "195", readers, &rss20_maker)
        _assert_itunes_duration(1, 0, 1, "3601", readers, &rss20_maker)

        _assert_itunes_duration_not_available_value("09:07:14:05", &rss20_maker)
        _assert_itunes_duration_not_available_value("10:5", &rss20_maker)
        _assert_itunes_duration_not_available_value("10:03:5", &rss20_maker)
        _assert_itunes_duration_not_available_value("10:3:05", &rss20_maker)

        _assert_itunes_duration_not_available_value("xx:xx:xx", &rss20_maker)

        _assert_itunes_duration_not_available_value("", &rss20_maker)
      end
    end

    def _assert_itunes_explicit(explicit, value, readers, &rss20_maker)
      content = tag("itunes:explicit", value)
      rss20 = itunes_rss20_parse(content, &rss20_maker)
      target = chain_reader(rss20, readers)
      assert_equal(value, target.itunes_explicit)
      assert_equal(explicit, target.itunes_explicit?)
    end

    def assert_itunes_explicit(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_explicit(true, "explicit", readers, &rss20_maker)
        _assert_itunes_explicit(true, "yes", readers, &rss20_maker)
        _assert_itunes_explicit(true, "true", readers, &rss20_maker)
        _assert_itunes_explicit(false, "clean", readers, &rss20_maker)
        _assert_itunes_explicit(false, "no", readers, &rss20_maker)
        _assert_itunes_explicit(false, "false", readers, &rss20_maker)
        _assert_itunes_explicit(nil, "invalid", readers, &rss20_maker)
      end
    end

    def _assert_itunes_keywords(keywords, value, readers, &rss20_maker)
      content = tag("itunes:keywords", value)
      rss20 = itunes_rss20_parse(content, &rss20_maker)
      target = chain_reader(rss20, readers)
      assert_equal(keywords, target.itunes_keywords)
    end

    def assert_itunes_keywords(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_keywords(["salt"], "salt", readers, &rss20_maker)
        _assert_itunes_keywords(["salt"], " salt ", readers, &rss20_maker)
        _assert_itunes_keywords(["salt", "pepper", "shaker", "exciting"],
                                "salt, pepper, shaker, exciting",
                                readers, &rss20_maker)
        _assert_itunes_keywords(["metric", "socket", "wrenches", "toolsalt"],
                                "metric, socket, wrenches, toolsalt",
                                readers, &rss20_maker)
        _assert_itunes_keywords(["olitics", "red", "blue", "state"],
                                "olitics, red, blue, state",
                                readers, &rss20_maker)
      end
    end

    def assert_itunes_new_feed_url(readers, &rss20_maker)
      _wrap_assertion do
        url = "http://newlocation.com/example.rss"
        content = tag("itunes:new-feed-url", url)
        rss20 = itunes_rss20_parse(content, &rss20_maker)
        target = chain_reader(rss20, readers)
        assert_equal(url, target.itunes_new_feed_url)
      end
    end

    def _assert_itunes_owner(name, email, readers, &rss20_maker)
      content = tag("itunes:owner",
                    tag("itunes:name", name) + tag("itunes:email", email))
      rss20 = itunes_rss20_parse(content, &rss20_maker)
      owner = chain_reader(rss20, readers).itunes_owner
      assert_equal(name, owner.itunes_name)
      assert_equal(email, owner.itunes_email)
    end

    def assert_itunes_owner(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_owner("John Doe", "john.doe@example.com",
                             readers, &rss20_maker)

        assert_missing_tag("name", "owner")  do
          content = tag("itunes:owner")
          itunes_rss20_parse(content, &rss20_maker)
        end

        assert_missing_tag("name", "owner")  do
          content = tag("itunes:owner",
                        tag("itunes:email", "john.doe@example.com"))
          itunes_rss20_parse(content, &rss20_maker)
        end

        assert_missing_tag("email", "owner")  do
          content = tag("itunes:owner", tag("itunes:name", "John Doe"))
          itunes_rss20_parse(content, &rss20_maker)
        end
      end
    end

    def _assert_itunes_subtitle(value, readers, &rss20_maker)
      content = tag("itunes:subtitle", value)
      rss20 = itunes_rss20_parse(content, &rss20_maker)
      target = chain_reader(rss20, readers)
      assert_equal(value, target.itunes_subtitle)
    end

    def assert_itunes_subtitle(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_subtitle("A show about everything", readers, &rss20_maker)
        _assert_itunes_subtitle("A short primer on table spices",
                                readers, &rss20_maker)
        _assert_itunes_subtitle("Comparing socket wrenches is fun!",
                                readers, &rss20_maker)
        _assert_itunes_subtitle("Red + Blue != Purple", readers, &rss20_maker)
      end
    end

    def _assert_itunes_summary(value, readers, &rss20_maker)
      content = tag("itunes:summary", value)
      rss20 = itunes_rss20_parse(content, &rss20_maker)
      target = chain_reader(rss20, readers)
      assert_equal(value, target.itunes_summary)
    end

    def assert_itunes_summary(readers, &rss20_maker)
      _wrap_assertion do
        _assert_itunes_summary("All About Everything is a show about " +
                               "everything. Each week we dive into any " +
                               "subject known to man and talk about it as " +
                               "much as we can. Look for our Podcast in " +
                               "the iTunes Music Store",
                               readers, &rss20_maker)
        _assert_itunes_summary("This week we talk about salt and pepper " +
                               "shakers, comparing and contrasting pour " +
                               "rates, construction materials, and overall " +
                               "aesthetics. Come and join the party!",
                               readers, &rss20_maker)
        _assert_itunes_summary("This week we talk about metric vs. old " +
                               "english socket wrenches. Which one is " +
                               "better? Do you really need both? Get all " +
                               "of your answers here.",
                               readers, &rss20_maker)
        _assert_itunes_summary("This week we talk about surviving in a " +
                               "Red state if you're a Blue person. Or " +
                               "vice versa.",
                               readers, &rss20_maker)
      end
    end
  end
end
