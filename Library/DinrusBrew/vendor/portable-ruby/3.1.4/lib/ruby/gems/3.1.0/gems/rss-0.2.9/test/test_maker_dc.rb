# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerDublinCore < TestCase

    def setup
      @uri = "http://purl.org/dc/elements/1.1/"

      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end

      @elements = {
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

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        set_elements(maker.channel)

        setup_dummy_image(maker)
        set_elements(maker.image)

        setup_dummy_item(maker)
        item = maker.items.last
        @elements.each do |name, value|
          item.__send__("#{accessor_name(name)}=", value)
        end

        setup_dummy_textinput(maker)
        set_elements(maker.textinput)
      end
      assert_dublin_core(@elements, rss.channel)
      assert_dublin_core(@elements, rss.image)
      assert_dublin_core(@elements, rss.items.last)
      assert_dublin_core(@elements, rss.textinput)
    end

    def test_rss10_multiple
      assert_multiple_dublin_core_rss10("_list")
      assert_multiple_dublin_core_rss10("es")
    end

    def assert_multiple_dublin_core_rss10(multiple_rights_suffix)
      elems = []
      @elements.each do |name, value|
        plural = name.to_s + (name == :rights ? multiple_rights_suffix : "s")
        values = [value]
        if name == :date
          values << value + 60
        else
          values << value * 2
        end
        elems << [name, values, plural]
      end

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        set_multiple_elements(maker.channel, elems)

        setup_dummy_image(maker)
        set_multiple_elements(maker.image, elems)

        setup_dummy_item(maker)
        item = maker.items.last
        elems.each do |name, values, plural|
          dc_elems = item.__send__("dc_#{plural}")
          values.each do |value|
            elem = dc_elems.__send__("new_#{name}")
            elem.value = value
          end
        end

        setup_dummy_textinput(maker)
        set_multiple_elements(maker.textinput, elems)
      end
      assert_multiple_dublin_core(elems, rss.channel)
      assert_multiple_dublin_core(elems, rss.image)
      assert_multiple_dublin_core(elems, rss.items.last)
      assert_multiple_dublin_core(elems, rss.textinput)
    end

    def test_date
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
    def accessor_name(name)
      "dc_#{name}"
    end

    def set_elements(target, elems=@elements)
      elems.each do |name, value|
        target.__send__("#{accessor_name(name)}=", value)
      end
    end

    def set_multiple_elements(target, elems)
      elems.each do |name, values, plural|
        plural ||= "#{name}s"
        dc_elems = target.__send__("dc_#{plural}")
        values.each do |value|
          dc_elems.__send__("new_#{name}") do |new_dc_elem|
            new_dc_elem.value = value
          end
        end
      end
    end

  end
end
