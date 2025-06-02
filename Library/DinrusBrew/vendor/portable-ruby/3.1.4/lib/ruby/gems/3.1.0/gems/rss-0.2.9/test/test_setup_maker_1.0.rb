# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestSetupMaker10 < TestCase

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

      @sy_elems = {
        :updatePeriod => "hourly",
        :updateFrequency => "2",
        :updateBase => t,
      }

      @content_elems = {
        :encoded => "<em>ATTENTION</em>",
      }

      @trackback_elems = {
        :ping => "http://bar.com/tb.cgi?tb_id=rssplustrackback",
        :about => [
          "http://foo.com/trackback/tb.cgi?tb_id=20020923",
          "http://foo.com/trackback/tb.cgi?tb_id=20021010",
        ],
      }

      @taxo_topic_elems = [
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

    def test_setup_maker_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"

      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description

        @dc_elems.each do |var, value|
          maker.channel.__send__("dc_#{var}=", value)
        end

        @sy_elems.each do |var, value|
          maker.channel.__send__("sy_#{var}=", value)
        end

        setup_dummy_item(maker)
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.items.each do |item|
          item.setup_maker(maker)
        end
      end
      channel = new_rss.channel

      assert_equal(about, channel.about)
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(1, channel.items.Seq.lis.size)
      assert_nil(channel.image)
      assert_nil(channel.textinput)

      @dc_elems.each do |var, value|
        assert_equal(value, channel.__send__("dc_#{var}"))
      end

      @sy_elems.each do |var, value|
        value = value.to_i if var == :updateFrequency
        assert_equal(value, channel.__send__("sy_#{var}"))
      end

    end

    def test_setup_maker_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        maker.image.title = title
        maker.image.url = url

        @dc_elems.each do |var, value|
          maker.image.__send__("dc_#{var}=", value)
        end

        setup_dummy_item(maker)
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.image.setup_maker(maker)
        rss.items.each do |item|
          item.setup_maker(maker)
        end
      end

      image = new_rss.image
      assert_equal(url, image.about)
      assert_equal(url, new_rss.channel.image.resource)
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)

      @dc_elems.each do |var, value|
        assert_equal(image.__send__("dc_#{var}"), value)
      end
    end

    def test_setup_maker_textinput
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

        @dc_elems.each do |var, value|
          maker.textinput.__send__("dc_#{var}=", value)
        end

        setup_dummy_item(maker)
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.textinput.setup_maker(maker)
        rss.items.each do |item|
          item.setup_maker(maker)
        end
      end

      textinput = new_rss.textinput
      assert_equal(link, textinput.about)
      assert_equal(link, new_rss.channel.textinput.resource)
      assert_equal(title, textinput.title)
      assert_equal(name, textinput.name)
      assert_equal(description, textinput.description)
      assert_equal(link, textinput.link)

      @dc_elems.each do |var, value|
        assert_equal(textinput.__send__("dc_#{var}"), value)
      end
    end

    def test_setup_maker_items(for_backward_compatibility=false)
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"

      item_size = 5

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{title}#{i}"
            item.link = "#{link}#{i}"
            item.description = "#{description}#{i}"

            @dc_elems.each do |var, value|
              item.__send__("dc_#{var}=", value)
            end

            @content_elems.each do |var, value|
              item.__send__("content_#{var}=", value)
            end

            item.trackback_ping = @trackback_elems[:ping]
            @trackback_elems[:about].each do |value|
              item.trackback_abouts.new_about do |new_about|
                new_about.value = value
              end
            end
          end
        end
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)

        rss.items.each do |item|
          if for_backward_compatibility
            item.setup_maker(maker)
          else
            item.setup_maker(maker.items)
          end
        end
      end

      assert_equal(item_size, new_rss.items.size)
      new_rss.items.each_with_index do |item, i|
        assert_equal("#{link}#{i}", item.about)
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)

        @dc_elems.each do |var, value|
          assert_equal(item.__send__("dc_#{var}"), value)
        end

        @content_elems.each do |var, value|
          assert_equal(item.__send__("content_#{var}"), value)
        end

        assert_equal(@trackback_elems[:ping], item.trackback_ping)
        assert_equal(@trackback_elems[:about].size, item.trackback_abouts.size)
        item.trackback_abouts.each_with_index do |about, j|
          assert_equal(@trackback_elems[:about][j], about.value)
        end
      end
    end

    def test_setup_maker_items_sort
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"

      item_size = 5

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          item = RSS::RDF::Item.new("#{link}#{i}")
          item.title = "#{title}#{i}"
          item.link = "#{link}#{i}"
          item.description = "#{description}#{i}"
          item.dc_date = Time.now + i * 60
          item.setup_maker(maker.items)
        end
        maker.items.do_sort = false
      end
      assert_equal(item_size, rss.items.size)
      rss.items.each_with_index do |item, i|
        assert_equal("#{link}#{i}", item.about)
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
      end


      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          item = RSS::RDF::Item.new("#{link}#{i}")
          item.title = "#{title}#{i}"
          item.link = "#{link}#{i}"
          item.description = "#{description}#{i}"
          item.dc_date = Time.now + i * 60
          item.setup_maker(maker.items)
        end
        maker.items.do_sort = true
      end
      assert_equal(item_size, rss.items.size)
      rss.items.reverse.each_with_index do |item, i|
        assert_equal("#{link}#{i}", item.about)
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
      end
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

      rss = RSS::Maker.make("1.0") do |maker|
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

        setup_dummy_channel(maker)
        setup_dummy_item(maker)
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.setup_maker(maker)
      end

      assert_equal("1.0", new_rss.rss_version)
      assert_equal(encoding, new_rss.encoding)
      assert_equal(standalone, new_rss.standalone)

      xss = new_rss.xml_stylesheets.first
      assert_equal(1, new_rss.xml_stylesheets.size)
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

      image_title = "fugafuga"
      image_url = "http://hoge.com/hoge.png"

      textinput_title = "fugafuga"
      textinput_description = "text hoge fuga"
      textinput_name = "hoge"
      textinput_link = "http://hoge.com"

      item_title = "TITLE"
      item_link = "http://hoge.com/"
      item_description = "text hoge fuga"

      item_size = 5

      rss = RSS::Maker.make("1.0") do |maker|
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
        @dc_elems.each do |var, value|
          maker.channel.__send__("dc_#{var}=", value)
        end
        @sy_elems.each do |var, value|
          maker.channel.__send__("sy_#{var}=", value)
        end

        maker.image.title = image_title
        maker.image.url = image_url
        @dc_elems.each do |var, value|
          maker.image.__send__("dc_#{var}=", value)
        end

        maker.textinput.link = textinput_link
        maker.textinput.title = textinput_title
        maker.textinput.description = textinput_description
        maker.textinput.name = textinput_name
        @dc_elems.each do |var, value|
          maker.textinput.__send__("dc_#{var}=", value)
        end

        item_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{item_title}#{i}"
            item.link = "#{item_link}#{i}"
            item.description = "#{item_description}#{i}"

            @dc_elems.each do |var, value|
              item.__send__("dc_#{var}=", value)
            end

            @content_elems.each do |var, value|
              item.__send__("content_#{var}=", value)
            end

            item.trackback_ping = @trackback_elems[:ping]
            @trackback_elems[:about].each do |value|
              item.trackback_abouts.new_about do |new_about|
                new_about.value = value
              end
            end
          end
        end

        setup_taxo_topic(maker, @taxo_topic_elems)
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.setup_maker(maker)
      end

      assert_equal("1.0", new_rss.rss_version)
      assert_equal(encoding, new_rss.encoding)
      assert_equal(standalone, new_rss.standalone)

      xss = new_rss.xml_stylesheets.first
      assert_equal(1, new_rss.xml_stylesheets.size)
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)

      channel = new_rss.channel
      assert_equal(channel_about, channel.about)
      assert_equal(channel_title, channel.title)
      assert_equal(channel_link, channel.link)
      assert_equal(channel_description, channel.description)
      item_resources = []
      item_size.times do |i|
        item_resources << "#{item_link}#{i}"
      end
      assert_equal(item_resources, channel.items.resources)
      assert_equal(image_url, channel.image.resource)
      assert_equal(textinput_link, channel.textinput.resource)
      @dc_elems.each do |var, value|
        assert_equal(value, channel.__send__("dc_#{var}"))
      end
      @sy_elems.each do |var, value|
        value = value.to_i if var == :updateFrequency
        assert_equal(value, channel.__send__("sy_#{var}"))
      end

      image = new_rss.image
      assert_equal(image_url, image.about)
      assert_equal(image_url, new_rss.channel.image.resource)
      assert_equal(image_title, image.title)
      assert_equal(channel_link, image.link)
      assert_equal(image_url, image.url)
      @dc_elems.each do |var, value|
        assert_equal(image.__send__("dc_#{var}"), value)
      end

      textinput = new_rss.textinput
      assert_equal(textinput_link, textinput.about)
      assert_equal(textinput_link, new_rss.channel.textinput.resource)
      assert_equal(textinput_title, textinput.title)
      assert_equal(textinput_name, textinput.name)
      assert_equal(textinput_description, textinput.description)
      assert_equal(textinput_link, textinput.link)
      @dc_elems.each do |var, value|
        assert_equal(textinput.__send__("dc_#{var}"), value)
      end

      assert_equal(item_size, new_rss.items.size)
      new_rss.items.each_with_index do |item, i|
        assert_equal("#{item_link}#{i}", item.about)
        assert_equal("#{item_title}#{i}", item.title)
        assert_equal("#{item_link}#{i}", item.link)
        assert_equal("#{item_description}#{i}", item.description)

        @dc_elems.each do |var, value|
          assert_equal(item.__send__("dc_#{var}"), value)
        end

        @content_elems.each do |var, value|
          assert_equal(item.__send__("content_#{var}"), value)
        end

        assert_equal(@trackback_elems[:ping], item.trackback_ping)
        assert_equal(@trackback_elems[:about].size, item.trackback_abouts.size)
        item.trackback_abouts.each_with_index do |about, j|
          assert_equal(@trackback_elems[:about][j], about.value)
        end
      end

      assert_taxo_topic(@taxo_topic_elems, new_rss)
    end

  end
end
