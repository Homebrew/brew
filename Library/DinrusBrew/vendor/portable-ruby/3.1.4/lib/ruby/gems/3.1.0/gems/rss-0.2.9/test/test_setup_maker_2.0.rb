# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestSetupMaker20 < TestCase

    def test_setup_maker_channel
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      language = "ja"
      copyright = "foo"
      managingEditor = "bar"
      webMaster = "web master"
      rating = '(PICS-1.1 "http://www.rsac.org/ratingsv01.html" l gen true comment "RSACi North America Server" for "http://www.rsac.org" on "1996.04.16T08:15-0500" r (n 0 s 0 v 0 l 0))'
      docs = "http://foo.com/doc"
      skipDays = [
        "Sunday",
        "Monday",
      ]
      skipHours = [
        "0",
        "13",
      ]
      pubDate = Time.now
      lastBuildDate = Time.now
      categories = [
        "Nespapers",
        "misc",
      ]
      generator = "RSS Maker"
      ttl = "60"

      rss = RSS::Maker.make("2.0") do |maker|
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description
        maker.channel.language = language
        maker.channel.copyright = copyright
        maker.channel.managingEditor = managingEditor
        maker.channel.webMaster = webMaster
        maker.channel.rating = rating
        maker.channel.docs = docs
        maker.channel.pubDate = pubDate
        maker.channel.lastBuildDate = lastBuildDate

        skipDays.each do |day|
          maker.channel.skipDays.new_day do |new_day|
            new_day.content = day
          end
        end
        skipHours.each do |hour|
          maker.channel.skipHours.new_hour do |new_hour|
            new_hour.content = hour
          end
        end


        categories.each do |category|
          maker.channel.categories.new_category do |new_category|
            new_category.content = category
          end
        end

        maker.channel.generator = generator
        maker.channel.ttl = ttl
      end

      new_rss = RSS::Maker.make("2.0") do |maker|
        rss.channel.setup_maker(maker)
      end
      channel = new_rss.channel

      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(language, channel.language)
      assert_equal(copyright, channel.copyright)
      assert_equal(managingEditor, channel.managingEditor)
      assert_equal(webMaster, channel.webMaster)
      assert_equal(rating, channel.rating)
      assert_equal(docs, channel.docs)
      assert_equal(pubDate, channel.pubDate)
      assert_equal(lastBuildDate, channel.lastBuildDate)

      skipDays.each_with_index do |day, i|
        assert_equal(day, channel.skipDays.days[i].content)
      end
      skipHours.each_with_index do |hour, i|
        assert_equal(hour.to_i, channel.skipHours.hours[i].content)
      end


      channel.categories.each_with_index do |category, i|
        assert_equal(categories[i], category.content)
      end

      assert_equal(generator, channel.generator)
      assert_equal(ttl.to_i, channel.ttl)


      assert(channel.items.empty?)
      assert_nil(channel.image)
      assert_nil(channel.textInput)
    end

    def test_setup_maker_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"
      width = "144"
      height = "400"
      description = "an image"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        maker.image.title = title
        maker.image.url = url
        maker.image.width = width
        maker.image.height = height
        maker.image.description = description
      end

      new_rss = RSS::Maker.make("2.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.image.setup_maker(maker)
      end

      image = new_rss.image
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)
      assert_equal(width.to_i, image.width)
      assert_equal(height.to_i, image.height)
      assert_equal(description, image.description)
    end

    def test_setup_maker_textinput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end

      new_rss = RSS::Maker.make("2.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.textinput.setup_maker(maker)
      end

      textInput = new_rss.channel.textInput
      assert_equal(title, textInput.title)
      assert_equal(description, textInput.description)
      assert_equal(name, textInput.name)
      assert_equal(link, textInput.link)
    end

    def test_setup_maker_items(for_backward_compatibility=false)
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"
      author = "oprah@oxygen.net"
      comments = "http://www.myblog.org/cgi-local/mt/mt-comments.cgi?entry_id=290"
      pubDate = Time.now

      guid_isPermaLink = "true"
      guid_content = "http://inessential.com/2002/09/01.php#a2"

      enclosure_url = "http://www.scripting.com/mp3s/weatherReportSuite.mp3"
      enclosure_length = "12216320"
      enclosure_type = "audio/mpeg"

      source_url = "http://static.userland.com/tomalak/links2.xml"
      source_content = "Tomalak's Realm"

      category_domain = "http://www.fool.com/cusips"
      category_content = "MSFT"

      item_size = 5

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        item_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{title}#{i}"
            item.link = "#{link}#{i}"
            item.description = "#{description}#{i}"
            item.author = "#{author}#{i}"
            item.comments = "#{comments}#{i}"
            item.date = pubDate

            item.guid.isPermaLink = guid_isPermaLink
            item.guid.content = guid_content

            item.enclosure.url = enclosure_url
            item.enclosure.length = enclosure_length
            item.enclosure.type = enclosure_type

            item.source.url = source_url
            item.source.content = source_content

            category = item.categories.new_category
            category.domain = category_domain
            category.content = category_content
          end
        end
      end

      new_rss = RSS::Maker.make("2.0") do |maker|
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
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
        assert_equal("#{author}#{i}", item.author)
        assert_equal("#{comments}#{i}", item.comments)
        assert_equal(pubDate, item.pubDate)

        assert_equal(guid_isPermaLink == "true", item.guid.isPermaLink)
        assert_equal(guid_content, item.guid.content)

        assert_equal(enclosure_url, item.enclosure.url)
        assert_equal(enclosure_length.to_i, item.enclosure.length)
        assert_equal(enclosure_type, item.enclosure.type)

        assert_equal(source_url, item.source.url)
        assert_equal(source_content, item.source.content)

        assert_equal(1, item.categories.size)
        assert_equal(category_domain, item.category.domain)
        assert_equal(category_content, item.category.content)
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

      rss = RSS::Maker.make("2.0") do |maker|
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
      end

      new_rss = RSS::Maker.make("2.0") do |maker|
        rss.setup_maker(maker)
      end

      assert_equal("2.0", new_rss.rss_version)
      assert_equal(encoding, new_rss.encoding)
      assert_equal(standalone, new_rss.standalone)

      xss = rss.xml_stylesheets.first
      assert_equal(1, rss.xml_stylesheets.size)
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)
    end

  end
end
