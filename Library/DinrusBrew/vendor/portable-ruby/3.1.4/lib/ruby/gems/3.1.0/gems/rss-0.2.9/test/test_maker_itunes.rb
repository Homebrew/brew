# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerITunes < TestCase
    def test_author
      assert_maker_itunes_author(%w(channel))
      assert_maker_itunes_author(%w(items last))
    end

    def test_block
      assert_maker_itunes_block(%w(channel))
      assert_maker_itunes_block(%w(items last))
    end

    def test_category
      assert_maker_itunes_category(%w(channel))
    end

    def test_image
      assert_maker_itunes_image(%w(channel))
      assert_maker_itunes_image(%w(items last))
    end

    def test_duration
      assert_maker_itunes_duration(%w(items last))
    end

    def test_explicit
      assert_maker_itunes_explicit(%w(channel))
      assert_maker_itunes_explicit(%w(items last))
    end

    def test_keywords
      assert_maker_itunes_keywords(%w(channel))
      assert_maker_itunes_keywords(%w(items last))
    end

    def test_new_feed_url
      assert_maker_itunes_new_feed_url(%w(channel))
    end

    def test_owner
      assert_maker_itunes_owner(%w(channel))
    end

    def test_subtitle
      assert_maker_itunes_subtitle(%w(channel))
      assert_maker_itunes_subtitle(%w(items last))
    end

    def test_summary
      assert_maker_itunes_summary(%w(channel))
      assert_maker_itunes_summary(%w(items last))
    end

    private

    def assert_maker_itunes_author(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        author = "John Doe"
        rss20 = ::RSS::Maker.make("rss2.0") do |maker|
          setup_dummy_channel(maker)
          setup_dummy_item(maker)

          target = chain_reader(maker, maker_readers)
          target.itunes_author = author
        end
        target = chain_reader(rss20, feed_readers)
        assert_equal(author, target.itunes_author)
      end
    end

    def _assert_maker_itunes_block(value, boolean_value, maker_readers,
                                   feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        target.itunes_block = value
        assert_equal(value, target.itunes_block)
        assert_equal(boolean_value, target.itunes_block?)
      end
      target = chain_reader(rss20, feed_readers)
      if [true, false].include?(value)
        value = value ? "yes" : "no"
      end
      assert_equal(value, target.itunes_block)
      assert_equal(boolean_value, target.itunes_block?)
    end

    def assert_maker_itunes_block(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_block("yes", true, maker_readers, feed_readers)
        _assert_maker_itunes_block("Yes", true, maker_readers, feed_readers)
        _assert_maker_itunes_block("no", false, maker_readers, feed_readers)
        _assert_maker_itunes_block("", false, maker_readers, feed_readers)
        _assert_maker_itunes_block(true, true, maker_readers, feed_readers)
        _assert_maker_itunes_block(false, false, maker_readers, feed_readers)
        _assert_maker_itunes_block(nil, false, maker_readers, feed_readers)
      end
    end

    def _assert_maker_itunes_category(categories, maker_readers, feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        categories.each do |category|
          sub_target = target.itunes_categories
          if category.is_a?(Array)
            category.each do |sub_category|
              sub_target = sub_target.new_category
              sub_target.text = sub_category
            end
          else
            sub_target.new_category.text = category
          end
        end
      end

      target = chain_reader(rss20, feed_readers)
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

    def assert_maker_itunes_category(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_category(["Audio Blogs"],
                                      maker_readers, feed_readers)
        _assert_maker_itunes_category([["Arts & Entertainment", "Games"]],
                                      maker_readers, feed_readers)
        _assert_maker_itunes_category([["Arts & Entertainment", "Games"],
                                       ["Technology", "Computers"],
                                       "Audio Blogs"],
                                      maker_readers, feed_readers)
      end
    end

    def assert_maker_itunes_image(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        url = "http://example.com/podcasts/everything/AllAboutEverything.jpg"

        rss20 = ::RSS::Maker.make("rss2.0") do |maker|
          setup_dummy_channel(maker)
          setup_dummy_item(maker)

          target = chain_reader(maker, maker_readers)
          target.itunes_image = url
        end

        target = chain_reader(rss20, feed_readers)
        assert_not_nil(target.itunes_image)
        assert_equal(url, target.itunes_image.href)
      end
    end

    def _assert_maker_itunes_duration(hour, minute, second, value,
                                      maker_readers, feed_readers)
      _assert_maker_itunes_duration_by_value(hour, minute, second, value,
                                             maker_readers, feed_readers)
      _assert_maker_itunes_duration_by_hour_minute_second(hour, minute, second,
                                                          value,
                                                          maker_readers,
                                                          feed_readers)
    end

    def _assert_maker_itunes_duration_by(hour, minute, second, value,
                                         maker_readers, feed_readers)
      expected_value = nil
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        expected_value = yield(target)
        assert_equal(expected_value, target.itunes_duration)
        target.itunes_duration do |duration|
          assert_equal([hour, minute, second, expected_value],
                       [duration.hour, duration.minute,
                        duration.second, duration.content])
        end
      end
      target = chain_reader(rss20, feed_readers)
      duration = target.itunes_duration
      assert_not_nil(duration)
      assert_equal([hour, minute, second, expected_value],
                   [duration.hour, duration.minute,
                    duration.second, duration.content])
    end

    def _assert_maker_itunes_duration_by_value(hour, minute, second, value,
                                               maker_readers, feed_readers)
      _assert_maker_itunes_duration_by(hour, minute, second, value,
                                       maker_readers, feed_readers) do |target|
        target.itunes_duration = value
        value
      end
    end

    def _assert_maker_itunes_duration_by_hour_minute_second(hour, minute, second,
                                                            value,
                                                            maker_readers,
                                                            feed_readers)
      _assert_maker_itunes_duration_by(hour, minute, second, value,
                                       maker_readers, feed_readers) do |target|
        target.itunes_duration do |duration|
          duration.hour = hour
          duration.minute = minute
          duration.second = second
        end
        value.split(":").collect {|v| "%02d" % v.to_i}.join(":")
      end
    end

    def _assert_maker_itunes_duration_invalid_value(value, maker_readers)
      assert_raise(ArgumentError) do
        ::RSS::Maker.make("rss2.0") do |maker|
          setup_dummy_channel(maker)
          setup_dummy_item(maker)

          target = chain_reader(maker, maker_readers)
          target.itunes_duration = value
        end
      end
    end

    def assert_maker_itunes_duration(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_duration(7, 14, 5, "07:14:05", maker_readers,
                                      feed_readers)
        _assert_maker_itunes_duration(7, 14, 5, "7:14:05", maker_readers,
                                      feed_readers)
        _assert_maker_itunes_duration(0, 4, 55, "04:55", maker_readers,
                                      feed_readers)
        _assert_maker_itunes_duration(0, 4, 5, "4:05", maker_readers,
                                      feed_readers)
        _assert_maker_itunes_duration(0, 0, 5, "0:05", maker_readers,
                                      feed_readers)
        _assert_maker_itunes_duration_by_value(0, 5, 15, "315", maker_readers,
                                               feed_readers)
        _assert_maker_itunes_duration_by_value(1, 0, 1, "3601", maker_readers,
                                               feed_readers)

        _assert_maker_itunes_duration_invalid_value("09:07:14:05", maker_readers)
        _assert_maker_itunes_duration_invalid_value("10:5", maker_readers)
        _assert_maker_itunes_duration_invalid_value("10:03:5", maker_readers)
        _assert_maker_itunes_duration_invalid_value("10:3:05", maker_readers)

        _assert_maker_itunes_duration_invalid_value("xx:xx:xx", maker_readers)

        _assert_maker_itunes_duration_invalid_value("", maker_readers)
      end
    end

    def _assert_maker_itunes_explicit(explicit, value,
                                      maker_readers, feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        target.itunes_explicit = value
        assert_equal(explicit, target.itunes_explicit?)
      end
      target = chain_reader(rss20, feed_readers)
      assert_equal(value, target.itunes_explicit)
      assert_equal(explicit, target.itunes_explicit?)
    end

    def assert_maker_itunes_explicit(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_explicit(true, "explicit",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_explicit(true, "yes",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_explicit(true, "true",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_explicit(false, "clean",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_explicit(false, "no",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_explicit(false, "false",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_explicit(nil, "invalid",
                                      maker_readers, feed_readers)
      end
    end

    def _assert_maker_itunes_keywords(keywords, value,
                                      maker_readers, feed_readers)
      _assert_maker_itunes_keywords_by_value(keywords, value,
                                             maker_readers, feed_readers)
      _assert_maker_itunes_keywords_by_keywords(keywords, maker_readers,
                                                feed_readers)
    end

    def _assert_maker_itunes_keywords_by(keywords, maker_readers, feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        yield(target)
      end
      assert_nothing_raised do
        rss20 = ::RSS::Parser.parse(rss20.to_s)
      end
      target = chain_reader(rss20, feed_readers)
      assert_equal(keywords, target.itunes_keywords)
    end

    def _assert_maker_itunes_keywords_by_value(keywords, value,
                                               maker_readers, feed_readers)
      _assert_maker_itunes_keywords_by(keywords, maker_readers,
                                       feed_readers) do |target|
        target.itunes_keywords = value
      end
    end

    def _assert_maker_itunes_keywords_by_keywords(keywords,
                                                  maker_readers, feed_readers)
      _assert_maker_itunes_keywords_by(keywords, maker_readers,
                                       feed_readers) do |target|
        target.itunes_keywords = keywords
      end
    end

    def assert_maker_itunes_keywords(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_keywords(["salt"], "salt",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_keywords(["salt"], " salt ",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_keywords(["salt", "pepper", "shaker", "exciting"],
                                      "salt, pepper, shaker, exciting",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_keywords(["metric", "socket", "wrenches",
                                       "toolsalt"],
                                      "metric, socket, wrenches, toolsalt",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_keywords(["olitics", "red", "blue", "state"],
                                      "olitics, red, blue, state",
                                      maker_readers, feed_readers)
      end
    end

    def assert_maker_itunes_new_feed_url(maker_readers, feed_readers=nil)
      feed_readers ||= maker_readers
      url = "http://newlocation.com/example.rss"

      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        target.itunes_new_feed_url = url
      end
      target = chain_reader(rss20, feed_readers)
      assert_equal(url, target.itunes_new_feed_url)
    end

    def _assert_maker_itunes_owner(name, email, maker_readers, feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        owner = target.itunes_owner
        owner.itunes_name = name
        owner.itunes_email = email
      end
      owner = chain_reader(rss20, feed_readers).itunes_owner
      if name.nil? and email.nil?
        assert_nil(owner)
      else
        assert_not_nil(owner)
        assert_equal(name, owner.itunes_name)
        assert_equal(email, owner.itunes_email)
      end
    end

    def assert_maker_itunes_owner(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_owner("John Doe", "john.doe@example.com",
                                   maker_readers, feed_readers)

        not_set_name = (["maker"] + maker_readers + ["itunes_owner"]).join(".")
        assert_not_set_error(not_set_name, ["itunes_name"]) do
          _assert_maker_itunes_owner(nil, "john.doe@example.com",
                                     maker_readers, feed_readers)
        end
        assert_not_set_error(not_set_name, ["itunes_email"]) do
          _assert_maker_itunes_owner("John Doe", nil,
                                     maker_readers, feed_readers)
        end

        _assert_maker_itunes_owner(nil, nil, maker_readers, feed_readers)
      end
    end

    def _assert_maker_itunes_subtitle(subtitle, maker_readers, feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        target.itunes_subtitle = subtitle
      end

      target = chain_reader(rss20, feed_readers)
      assert_equal(subtitle, target.itunes_subtitle)
    end

    def assert_maker_itunes_subtitle(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_subtitle("A show about everything",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_subtitle("A short primer on table spices",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_subtitle("Comparing socket wrenches is fun!",
                                      maker_readers, feed_readers)
        _assert_maker_itunes_subtitle("Red + Blue != Purple",
                                      maker_readers, feed_readers)
      end
    end

    def _assert_maker_itunes_summary(summary, maker_readers, feed_readers)
      rss20 = ::RSS::Maker.make("rss2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        target = chain_reader(maker, maker_readers)
        target.itunes_summary = summary
      end

      target = chain_reader(rss20, feed_readers)
      assert_equal(summary, target.itunes_summary)
    end

    def assert_maker_itunes_summary(maker_readers, feed_readers=nil)
      _wrap_assertion do
        feed_readers ||= maker_readers
        _assert_maker_itunes_summary("All About Everything is a show about " +
                                     "everything. Each week we dive into any " +
                                     "subject known to man and talk about it " +
                                     "as much as we can. Look for our Podcast " +
                                     "in the iTunes Music Store",
                                     maker_readers, feed_readers)
        _assert_maker_itunes_summary("This week we talk about salt and pepper " +
                                     "shakers, comparing and contrasting pour " +
                                     "rates, construction materials, and " +
                                     "overall aesthetics. Come and join the " +
                                     "party!",
                                     maker_readers, feed_readers)
        _assert_maker_itunes_summary("This week we talk about metric vs. old " +
                                     "english socket wrenches. Which one is " +
                                     "better? Do you really need both? Get " +
                                     "all of your answers here.",
                                     maker_readers, feed_readers)
        _assert_maker_itunes_summary("This week we talk about surviving in a " +
                                     "Red state if you're a Blue person. Or " +
                                     "vice versa.",
                                     maker_readers, feed_readers)
      end
    end
  end
end
