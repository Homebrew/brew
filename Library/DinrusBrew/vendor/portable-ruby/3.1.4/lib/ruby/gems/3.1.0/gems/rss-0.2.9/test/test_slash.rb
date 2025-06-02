# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/slash"

module RSS
  class TestSlash < TestCase
    def setup
      @elements = {
        "section" => "articles",
        "department" => "not-an-ocean-unless-there-are-lobsters",
        "comments" => 177,
        "hit_parades" => [177, 155, 105, 33, 6, 3, 0],
      }

      slash_nodes = @elements.collect do |name, value|
        if name == "hit_parades"
          name = "hit_parade"
          value = value.join(",")
        end
        "<slash:#{name}>#{value}</slash:#{name}>"
      end.join("\n")

      slash_ns = {"slash" => "http://purl.org/rss/1.0/modules/slash/"}
      @source = make_RDF(<<-EOR, slash_ns)
#{make_channel}
#{make_image}
#{make_item(slash_nodes)}
#{make_textinput}
EOR
    end

    def test_parser
      rss = RSS::Parser.parse(@source)

      assert_not_nil(rss)

      item = rss.items[0]
      assert_not_nil(item)

      assert_slash_elements(item)
    end

    def test_to_s
      rss = RSS::Parser.parse(@source)
      rss = RSS::Parser.parse(rss.to_s)

      assert_not_nil(rss)

      item = rss.items[0]
      assert_not_nil(item)

      assert_slash_elements(item)
    end

    private
    def assert_slash_elements(target)
      super(@elements, target)
    end
  end
end
