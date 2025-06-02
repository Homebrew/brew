# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/2.0"

module RSS
  class TestParser20 < TestCase
    def test_rss20
      assert_parse(make_rss20(<<-EOR), :missing_tag, "channel", "rss")
EOR

      assert_parse(make_rss20(<<-EOR), :nothing_raised)
#{make_channel20("")}
EOR
    end

    def test_cloud20
      attrs = [
        ["domain", CLOUD_DOMAIN],
        ["port", CLOUD_PORT],
        ["path", CLOUD_PATH],
        ["registerProcedure", CLOUD_REGISTER_PROCEDURE],
        ["protocol", CLOUD_PROTOCOL],
      ]

      (attrs.size + 1).times do |i|
        missing_attr = attrs[i]
        if missing_attr
          meth = :missing_attribute
          args = ["cloud", missing_attr[0]]
        else
          meth = :nothing_raised
          args = []
        end

        cloud_attrs = []
        attrs.each_with_index do |attr, j|
          unless i == j
            cloud_attrs << %Q[#{attr[0]}="#{attr[1]}"]
          end
        end

        assert_parse(make_rss20(<<-EOR), meth, *args)
#{make_channel20(%Q[<cloud #{cloud_attrs.join("\n")}/>])}
EOR
      end
    end

    def test_source20
        assert_parse(make_rss20(<<-EOR), :missing_attribute, "source", "url")
#{make_channel20(make_item20(%Q[<source>Example</source>]))}
EOR

        assert_parse(make_rss20(<<-EOR), :nothing_raised)
#{make_channel20(make_item20(%Q[<source url="http://example.com/" />]))}
EOR

        assert_parse(make_rss20(<<-EOR), :nothing_raised)
#{make_channel20(make_item20(%Q[<source url="http://example.com/">Example</source>]))}
EOR
    end

    def test_enclosure20
      attrs = [
        ["url", ENCLOSURE_URL],
        ["length", ENCLOSURE_LENGTH],
        ["type", ENCLOSURE_TYPE],
      ]

      (attrs.size + 1).times do |i|
        missing_attr = attrs[i]
        if missing_attr
          meth = :missing_attribute
          args = ["enclosure", missing_attr[0]]
        else
          meth = :nothing_raised
          args = []
        end

        enclosure_attrs = []
        attrs.each_with_index do |attr, j|
          unless i == j
            enclosure_attrs << %Q[#{attr[0]}="#{attr[1]}"]
          end
        end

        assert_parse(make_rss20(<<-EOR), meth, *args)
#{make_channel20(%Q[
#{make_item20(%Q[
<enclosure
  #{enclosure_attrs.join("\n")} />
    ])}
  ])}
EOR
      end
    end

    def test_category20
      values = [nil, CATEGORY_DOMAIN]
      values.each do |value|
        domain = ""
        domain << %Q[domain="#{value}"] if value

        ["", "Example Text"].each do |text|
          rss_src = make_rss20(<<-EOR)
#{make_channel20(%Q[
#{make_item20(%Q[
<category #{domain}>#{text}</category>
    ])}
  ])}
EOR
          assert_parse(rss_src, :nothing_raised)

          rss = RSS::Parser.parse(rss_src)
          category = rss.items.last.categories.first
          assert_equal(value, category.domain)
          assert_equal(text, category.content)
        end
      end
    end
  end
end

