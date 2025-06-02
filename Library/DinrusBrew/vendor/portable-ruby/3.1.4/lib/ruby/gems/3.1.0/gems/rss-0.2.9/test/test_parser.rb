# frozen_string_literal: false
require "tempfile"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/dublincore"

module RSS
  class TestParser < TestCase
    def setup
      @_default_parser = Parser.default_parser
      @rss10 = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
EOR
      @rss_tmp = Tempfile.new(%w"rss10- .rdf")
      @rss_tmp.print(@rss10)
      @rss_tmp.close
      @rss_file = @rss_tmp.path
      @rss_file.untaint if RUBY_VERSION < '2.7'
    end

    def teardown
      Parser.default_parser = @_default_parser
      @rss_tmp.close(true)
    end

    def test_default_parser
      assert_nothing_raised do
        Parser.default_parser = RSS::AVAILABLE_PARSERS.first
      end

      assert_raise(RSS::NotValidXMLParser) do
        Parser.default_parser = RSS::Parser
      end
    end

    def test_parse
      assert_not_nil(RSS::Parser.parse(@rss_file))

      garbage_rss_file = @rss_file + "-garbage"
      if RSS::Parser.default_parser.name == "RSS::XMLParserParser"
        assert_raise(RSS::NotWellFormedError) do
          RSS::Parser.parse(garbage_rss_file)
        end
      else
        assert_nil(RSS::Parser.parse(garbage_rss_file))
      end
    end

    def test_parse_tag_includes_hyphen
      assert_nothing_raised do
        RSS::Parser.parse(make_RDF(<<-EOR))
<xCal:x-calconnect-venue xmlns:xCal="urn:ietf:params:xml:ns:xcal" />
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
EOR
      end
    end

    def test_parse_option_validate_nil
      assert_raise(RSS::MissingTagError) do
        RSS::Parser.parse(make_RDF(<<-RDF), :validate => nil)
        RDF
      end
    end

    def test_parse_option_validate_true
      assert_raise(RSS::MissingTagError) do
        RSS::Parser.parse(make_RDF(<<-RDF), :validate => true)
        RDF
      end
    end

    def test_parse_option_validate_false
      rdf = RSS::Parser.parse(make_RDF(<<-RDF), :validate => false)
      RDF
      assert_nil(rdf.channel)
    end

    def test_parse_option_ignore_unknown_element_nil
      assert_nothing_raised do
        RSS::Parser.parse(make_RDF(<<-RDF), :ignore_unknown_element => nil)
<unknown/>
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
        RDF
      end
    end

    def test_parse_option_ignore_unknown_element_true
      assert_nothing_raised do
        RSS::Parser.parse(make_RDF(<<-RDF), :ignore_unknown_element => true)
<unknown/>
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
        RDF
      end
    end

    def test_parse_option_ignore_unknown_element_false
      assert_raise(RSS::NotExpectedTagError) do
        RSS::Parser.parse(make_RDF(<<-RDF), :ignore_unknown_element => false)
<unknown/>
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
        RDF
      end
    end
  end
end
