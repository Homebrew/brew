# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/maker"

module RSS
  class TestMaker20 < TestCase
    def test_supported?
      assert(RSS::Maker.supported?("2.0"))
      assert(RSS::Maker.supported?("rss2.0"))
      assert(!RSS::Maker.supported?("2.2"))
      assert(!RSS::Maker.supported?("rss2.2"))
    end

    def test_find_class
      assert_equal(RSS::Maker::RSS20, RSS::Maker["2.0"])
      assert_equal(RSS::Maker::RSS20, RSS::Maker["rss2.0"])
    end

    def test_rss
      assert_raise(LocalJumpError) do
        RSS::Maker.make("2.0")
      end

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
      end
      assert_equal("2.0", rss.rss_version)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.encoding = "EUC-JP"
      end
      assert_equal("2.0", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.standalone = "yes"
      end
      assert_equal("2.0", rss.rss_version)
      assert_equal("yes", rss.standalone)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.encoding = "EUC-JP"
        maker.standalone = "yes"
      end
      assert_equal("2.0", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)
      assert_equal("yes", rss.standalone)
    end

    def test_channel
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
      channel = rss.channel

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
      assert_equal(pubDate, channel.date)
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

    def test_not_valid_channel
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      language = "ja"

      assert_not_set_error("maker.channel", %w(title)) do
        RSS::Maker.make("2.0") do |maker|
          # maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
          maker.channel.language = language
        end
      end

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("2.0") do |maker|
          maker.channel.title = title
          # maker.channel.link = link
          maker.channel.description = description
          maker.channel.language = language
        end
      end

      assert_not_set_error("maker.channel", %w(description)) do
        RSS::Maker.make("2.0") do |maker|
          maker.channel.title = title
          maker.channel.link = link
          # maker.channel.description = description
          maker.channel.language = language
        end
      end

      rss = RSS::Maker.make("2.0") do |maker|
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description
        # maker.channel.language = language
      end
      assert_not_nil(rss)
    end


    def test_cloud
      domain = "rpc.sys.com"
      port = "80"
      path = "/RPC2"
      registerProcedure = "myCloud.rssPleaseNotify"
      protocol = "xml-rpc"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.channel.cloud.domain = domain
        maker.channel.cloud.port = port
        maker.channel.cloud.path = path
        maker.channel.cloud.registerProcedure = registerProcedure
        maker.channel.cloud.protocol = protocol
      end
      cloud = rss.channel.cloud
      assert_equal(domain, cloud.domain)
      assert_equal(port.to_i, cloud.port)
      assert_equal(path, cloud.path)
      assert_equal(registerProcedure, cloud.registerProcedure)
      assert_equal(protocol, cloud.protocol)
    end

    def test_not_valid_cloud
      domain = "rpc.sys.com"
      port = "80"
      path = "/RPC2"
      registerProcedure = "myCloud.rssPleaseNotify"
      protocol = "xml-rpc"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        # maker.channel.cloud.domain = domain
        maker.channel.cloud.port = port
        maker.channel.cloud.path = path
        maker.channel.cloud.registerProcedure = registerProcedure
        maker.channel.cloud.protocol = protocol
      end
      assert_nil(rss.channel.cloud)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.channel.cloud.domain = domain
        # maker.channel.cloud.port = port
        maker.channel.cloud.path = path
        maker.channel.cloud.registerProcedure = registerProcedure
        maker.channel.cloud.protocol = protocol
      end
      assert_nil(rss.channel.cloud)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.channel.cloud.domain = domain
        maker.channel.cloud.port = port
        # maker.channel.cloud.path = path
        maker.channel.cloud.registerProcedure = registerProcedure
        maker.channel.cloud.protocol = protocol
      end
      assert_nil(rss.channel.cloud)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.channel.cloud.domain = domain
        maker.channel.cloud.port = port
        maker.channel.cloud.path = path
        # maker.channel.cloud.registerProcedure = registerProcedure
        maker.channel.cloud.protocol = protocol
      end
      assert_nil(rss.channel.cloud)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.channel.cloud.domain = domain
        maker.channel.cloud.port = port
        maker.channel.cloud.path = path
        maker.channel.cloud.registerProcedure = registerProcedure
        # maker.channel.cloud.protocol = protocol
      end
      assert_nil(rss.channel.cloud)
    end


    def test_image
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
      image = rss.image
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)
      assert_equal(width.to_i, image.width)
      assert_equal(height.to_i, image.height)
      assert_equal(description, image.description)

      assert_not_set_error("maker.channel", %w(title description)) do
        RSS::Maker.make("2.0") do |maker|
          # setup_dummy_channel(maker)
          maker.channel.link = link

          maker.image.title = title
          maker.image.url = url
          maker.image.width = width
          maker.image.height = height
          maker.image.description = description
        end
      end
    end

    def test_not_valid_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"
      width = "144"
      height = "400"
      description = "an image"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        # maker.image.title = title
        maker.image.url = url
        maker.image.width = width
        maker.image.height = height
        maker.image.description = description
      end
      assert_nil(rss.image)

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("2.0") do |maker|
          setup_dummy_channel(maker)
          # maker.channel.link = link
          maker.channel.link = nil

          maker.image.title = title
          maker.image.url = url
          maker.image.width = width
          maker.image.height = height
          maker.image.description = description
        end
      end

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link

        maker.image.title = title
        # maker.image.url = url
        maker.image.width = width
        maker.image.height = height
        maker.image.description = description
      end
      assert_nil(rss.image)
    end

    def test_items(with_convenience_way=true)
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"
      author = "oprah@oxygen.net"
      comments = "http://www.myblog.org/cgi-local/mt/mt-comments.cgi?entry_id=290"
      pubDate = Time.now

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
      end
      assert(rss.channel.items.empty?)

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
            item.date = pubDate - i
          end
        end
        maker.items.do_sort = true
      end
      assert_equal(item_size, rss.items.size)
      rss.channel.items.each_with_index do |item, i|
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
        assert_equal("#{author}#{i}", item.author)
        assert_equal("#{comments}#{i}", item.comments)
        assert_equal(pubDate - i, item.pubDate)
        assert_equal(pubDate - i, item.date)
      end

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
          end
        end
        maker.items.do_sort = Proc.new do |x, y|
          if with_convenience_way
            y.title[-1] <=> x.title[-1]
          else
            y.title {|t| t.content[-1]} <=> x.title {|t| t.content[-1]}
          end
        end
      end
      assert_equal(item_size, rss.items.size)
      rss.channel.items.reverse.each_with_index do |item, i|
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
        assert_equal("#{author}#{i}", item.author)
        assert_equal("#{comments}#{i}", item.comments)
        assert_equal(pubDate, item.pubDate)
        assert_equal(pubDate, item.date)
      end
    end

    def test_items_with_new_api_since_018
      test_items(false)
    end

    def test_pubDate_without_description
      title = "TITLE"
      link = "http://hoge.com/"
      # description = "text hoge fuga"
      author = "oprah@oxygen.net"
      pubDate = Time.now

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.items.new_item do |item|
          item.title = title
          item.link = link
          # item.description = description
          item.author = author
          item.pubDate = pubDate
        end
      end
      assert_equal(1, rss.items.size)
      rss.channel.items.each_with_index do |item, i|
        assert_equal(title, item.title)
        assert_equal(link, item.link)
        # assert_equal(description, item.description)
        assert_equal(author, item.author)
        assert_equal(pubDate, item.pubDate)
        assert_equal(pubDate, item.date)
      end
    end

    def test_guid
      isPermaLink = "true"
      content = "http://inessential.com/2002/09/01.php#a2"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        guid = maker.items.last.guid
        guid.isPermaLink = isPermaLink
        guid.content = content
      end
      guid = rss.channel.items.last.guid
      assert_equal(isPermaLink == "true", guid.isPermaLink)
      assert_equal(content, guid.content)
    end

    def test_guid_permanent_link
      content = "http://inessential.com/2002/09/01.php#a2"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        guid = maker.items.last.guid
        assert_equal(nil, guid.permanent_link?)
        assert_equal(guid.isPermaLink, guid.permanent_link?)
        guid.permanent_link = true
        assert_equal(true, guid.permanent_link?)
        assert_equal(guid.isPermaLink, guid.permanent_link?)
        guid.content = content
      end
      guid = rss.channel.items.last.guid
      assert_equal(true, guid.isPermaLink)
      assert_equal(content, guid.content)
    end

    def test_guid_permanent_link_false
      content = "http://inessential.com/2002/09/01.php#a2"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        guid = maker.items.last.guid
        assert_equal(nil, guid.permanent_link?)
        assert_equal(guid.isPermaLink, guid.permanent_link?)
        guid.permanent_link = false
        assert_equal(false, guid.permanent_link?)
        assert_equal(guid.isPermaLink, guid.permanent_link?)
        guid.content = content
      end
      guid = rss.channel.items.last.guid
      assert_equal(false, guid.isPermaLink)
      assert_equal(content, guid.content)
    end

    def test_not_valid_guid
      # content = "http://inessential.com/2002/09/01.php#a2"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        # guid = maker.items.last.guid
        # guid.content = content
      end
      assert_nil(rss.channel.items.last.guid)
    end

    def test_enclosure
      url = "http://www.scripting.com/mp3s/weatherReportSuite.mp3"
      length = "12216320"
      type = "audio/mpeg"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        enclosure = maker.items.last.enclosure
        enclosure.url = url
        enclosure.length = length
        enclosure.type = type
      end
      enclosure = rss.channel.items.last.enclosure
      assert_equal(url, enclosure.url)
      assert_equal(length.to_i, enclosure.length)
      assert_equal(type, enclosure.type)
    end

    def test_not_valid_enclosure
      url = "http://www.scripting.com/mp3s/weatherReportSuite.mp3"
      length = "12216320"
      type = "audio/mpeg"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        enclosure = maker.items.last.enclosure
        # enclosure.url = url
        enclosure.length = length
        enclosure.type = type
      end
      assert_nil(rss.channel.items.last.enclosure)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        enclosure = maker.items.last.enclosure
        enclosure.url = url
        # enclosure.length = length
        enclosure.type = type
      end
      assert_nil(rss.channel.items.last.enclosure)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        enclosure = maker.items.last.enclosure
        enclosure.url = url
        enclosure.length = length
        # enclosure.type = type
      end
      assert_nil(rss.channel.items.last.enclosure)
    end


    def test_source
      url = "http://static.userland.com/tomalak/links2.xml"
      content = "Tomalak's Realm"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        source = maker.items.last.source
        source.url = url
        source.content = content
      end
      source = rss.channel.items.last.source
      assert_equal(url, source.url)
      assert_equal(content, source.content)
    end

    def test_not_valid_source
      url = "http://static.userland.com/tomalak/links2.xml"
      content = "Tomalak's Realm"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        source = maker.items.last.source
        # source.url = url
        source.content = content
      end
      assert_nil(rss.channel.items.last.source)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        source = maker.items.last.source
        source.url = url
        # source.content = content
      end
      assert_nil(rss.channel.items.last.source)
    end

    def test_category
      domain = "http://www.fool.com/cusips"
      content = "MSFT"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        maker.items.last.categories.new_category do |category|
          category.domain = domain
          category.content = content
        end
      end
      category = rss.channel.items.last.categories.last
      assert_equal(domain, category.domain)
      assert_equal(content, category.content)
    end

    def test_not_valid_category
      # content = "Grateful Dead"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)
        setup_dummy_item(maker)

        maker.items.last.categories.new_category do |category|
          # category.content = content
        end
      end
      assert(rss.channel.items.last.categories.empty?)
    end

    def test_textInput
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
      textInput = rss.channel.textInput
      assert_equal(title, textInput.title)
      assert_equal(description, textInput.description)
      assert_equal(name, textInput.name)
      assert_equal(link, textInput.link)

      assert_not_set_error("maker.channel", %w(link description title)) do
        RSS::Maker.make("2.0") do |maker|
          # setup_dummy_channel(maker)

          maker.textinput.title = title
          maker.textinput.description = description
          maker.textinput.name = name
          maker.textinput.link = link
        end
      end
    end

    def test_not_valid_textInput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        # maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.title = title
        # maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.title = title
        maker.textinput.description = description
        # maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)

      rss = RSS::Maker.make("2.0") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        # maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)
    end
  end
end
