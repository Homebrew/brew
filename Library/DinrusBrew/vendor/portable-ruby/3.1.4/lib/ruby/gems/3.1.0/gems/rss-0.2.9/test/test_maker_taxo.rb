# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerTaxonomy < TestCase

    def setup
      @uri = "http://purl.org/rss/1.0/modules/taxonomy/"

      @resources = [
        "http://meerkat.oreillynet.com/?c=cat23",
        "http://meerkat.oreillynet.com/?c=47",
        "http://dmoz.org/Computers/Data_Formats/Markup_Languages/XML/",
      ]

      @topics = [
        {
          :link => "http://meerkat.oreillynet.com/?c=cat23",
          :title => "Data: XML",
          :description => "A Meerkat channel",
         },
        {
          :link => "http://dmoz.org/Computers/Data_Formats/Markup_Languages/XML/",
          :title => "XML",
          :subject => "XML",
          :description => "DMOZ category",
          :topics => [
            "http://meerkat.oreillynet.com/?c=cat23",
            "http://dmoz.org/Computers/Data_Formats/Markup_Languages/SGML/",
            "http://dmoz.org/Computers/Programming/Internet/",
          ]
         },
       ]
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        set_topics(maker.channel)

        setup_dummy_item(maker)
        set_topics(maker.items.last)

        setup_taxo_topic(maker, @topics)
      end
      assert_equal(@resources, rss.channel.taxo_topics.resources)
      assert_equal(@resources, rss.items.last.taxo_topics.resources)
      assert_taxo_topic(@topics, rss)
    end

    def _test_date
      t1 = Time.iso8601("2000-01-01T12:00:05+00:00")
      t2 = Time.iso8601("2005-01-01T12:00:05+00:00")

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.date = t1
        maker.channel.dc_dates.new_date do |date|
          date.value = t2
        end

        setup_dummy_item(maker)
        item = maker.items.last
        item.date = t2
        item.dc_dates.new_date do |date|
          date.value = t1
        end
      end
      assert_equal([t1, t2], rss.channel.dc_dates.collect{|x| x.value})
      assert_equal([t2, t1], rss.items.last.dc_dates.collect{|x| x.value})
    end

    private
    def set_topics(target, resources=@resources)
      resources.each do |value|
        target.taxo_topics << value
      end
    end
  end
end
