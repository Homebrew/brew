# frozen_string_literal: false
require "cgi"
require "rexml/document"

require_relative "rss-testcase"

require "rss/1.0"
require "rss/dublincore"

module RSS
  class TestDublinCore < TestCase
    def setup
      @rss10_parents = [%w(channel), %w(image), %w(item), %w(textinput)]

      @rss10_source = make_RDF(<<-EOR, {DC_PREFIX =>  DC_URI})
#{make_channel(DC_NODES)}
#{make_image(DC_NODES)}
#{make_item(DC_NODES)}
#{make_textinput(DC_NODES)}
EOR

      @rss20_parents = [%w(channel), %w(items last)]

      @rss20_source = make_rss20(<<-EOR, {DC_PREFIX =>  DC_URI})
#{make_channel20(DC_NODES + make_item20(DC_NODES))}
EOR

      @atom_feed_parents = [[], %w(entries last)]

      @atom_feed_source = make_feed(<<-EOR, {DC_PREFIX =>  DC_URI})
#{DC_NODES}
#{make_entry(DC_NODES)}
EOR

      @atom_entry_parents = [[]]

      @atom_entry_source = make_entry_document(<<-EOR, {DC_PREFIX =>  DC_URI})
#{DC_NODES}
EOR
    end

    def test_parser
      rss10_maker = Proc.new do |content, xmlns|
        make_RDF(<<-EOR, xmlns)
#{make_channel(content)}
#{make_image(content)}
#{make_item(content)}
#{make_textinput(content)}
EOR
      end
      assert_dc_parse(@rss10_source, @rss10_parents, false, &rss10_maker)
      assert_dc_parse(@rss10_source, @rss10_parents, true, &rss10_maker)

      rss20_maker = Proc.new do |content, xmlns|
        make_rss20(<<-EOR, xmlns)
#{make_channel20(content + make_item20(content))}
EOR
      end
      assert_dc_parse(@rss20_source, @rss20_parents, false, &rss20_maker)
      assert_dc_parse(@rss20_source, @rss20_parents, true, &rss20_maker)

      atom_feed_maker = Proc.new do |content, xmlns|
        make_feed(<<-EOR, xmlns)
#{content}
#{make_entry(content)}
EOR
      end
      assert_dc_parse(@atom_feed_source, @atom_feed_parents, false,
                      &atom_feed_maker)
      assert_dc_parse(@atom_feed_source, @atom_feed_parents, true,
                      &atom_feed_maker)

      atom_entry_maker = Proc.new do |content, xmlns|
        make_entry_document(<<-EOR, xmlns)
#{content}
EOR
      end
      assert_dc_parse(@atom_entry_source, @atom_entry_parents, false,
                      &atom_entry_maker)
      assert_dc_parse(@atom_entry_source, @atom_entry_parents, true,
                      &atom_entry_maker)
    end

    def test_singular_accessor
      assert_dc_singular_accessor(@rss10_source, @rss10_parents)
      assert_dc_singular_accessor(@rss20_source, @rss20_parents)
      assert_dc_singular_accessor(@atom_feed_source, @atom_feed_parents)
      assert_dc_singular_accessor(@atom_entry_source, @atom_entry_parents)
    end

    def test_plural_accessor
      assert_dc_plural_accessor(@rss10_source, @rss10_parents, false)
      assert_dc_plural_accessor(@rss10_source, @rss10_parents, true)

      assert_dc_plural_accessor(@rss20_source, @rss20_parents, false)
      assert_dc_plural_accessor(@rss20_source, @rss20_parents, true)

      assert_dc_plural_accessor(@atom_feed_source, @atom_feed_parents, false)
      assert_dc_plural_accessor(@atom_feed_source, @atom_feed_parents, true)

      assert_dc_plural_accessor(@atom_entry_source, @atom_entry_parents, false)
      assert_dc_plural_accessor(@atom_entry_source, @atom_entry_parents, true)
    end

    def test_to_s
      assert_dc_to_s(@rss10_source, @rss10_parents, false)
      assert_dc_to_s(@rss10_source, @rss10_parents, true)

      targets = ["channel", "channel/item[3]"]
      assert_dc_to_s(@rss20_source, @rss20_parents, false, targets)
      assert_dc_to_s(@rss20_source, @rss20_parents, true, targets)

      targets = [".", "entry"]
      assert_dc_to_s(@atom_feed_source, @atom_feed_parents, false, targets)
      assert_dc_to_s(@atom_feed_source, @atom_feed_parents, true, targets)

      targets = ["."]
      assert_dc_to_s(@atom_entry_source, @atom_entry_parents, false, targets)
      assert_dc_to_s(@atom_entry_source, @atom_entry_parents, true, targets)
    end

    private
    def dc_plural_suffix(name, check_backward_compatibility)
      if name == :rights
        if check_backward_compatibility
          "es"
        else
          "_list"
        end
      else
        "s"
      end
    end

    def assert_dc_parse(source, parents, check_backward_compatibility, &maker)
      assert_nothing_raised do
        Parser.parse(source)
      end

      DC_ELEMENTS.each do |name, value|
        parents.each do |parent_readers|
          feed = nil
          assert_nothing_raised do
            tag = "#{DC_PREFIX}:#{name}"
            dc_content = "<#{tag}>#{value}</#{tag}>\n"
            dc_content *= 2
            feed = Parser.parse(maker.call(dc_content, {DC_PREFIX => DC_URI}))
          end
          parent = chain_reader(feed, parent_readers)

          plural_suffix = dc_plural_suffix(name, check_backward_compatibility)
          plural_reader = "dc_#{name}#{plural_suffix}"
          values = parent.__send__(plural_reader).collect(&:value)
          value = CGI.unescapeHTML(value) if value.kind_of?(String)
          assert_equal([value, value], values)
        end
      end
    end

    def assert_dc_singular_accessor(source, parents)
      feed = Parser.parse(source)
      new_value = "hoge"

      parents.each do |parent_readers|
        parent = chain_reader(feed, parent_readers)
        DC_ELEMENTS.each do |name, value|
          parsed_value = parent.__send__("dc_#{name}")
          value = CGI.unescapeHTML(value) if value.kind_of?(String)
          assert_equal(value, parsed_value)
          if name == :date
            t = Time.iso8601("2003-01-01T02:30:23+09:00")
            class << t
              alias_method(:to_s, :iso8601)
            end
            parent.__send__("dc_#{name}=", t.iso8601)
            assert_equal(t, parent.__send__("dc_#{name}"))
            if parent.class.method_defined?(:date_without_dc_date=)
              assert_nil(parent.date)
            else
              assert_equal(t, parent.date)
            end

            parent.date = value
            assert_equal(value, parent.date)
            assert_equal(value, parent.__send__("dc_#{name}"))
          else
            parent.__send__("dc_#{name}=", new_value)
            assert_equal(new_value, parent.__send__("dc_#{name}"))
          end
        end
      end
    end

    def assert_dc_plural_accessor(source, parents, check_backward_compatibility)
      feed = Parser.parse(source)
      new_value = "hoge"

      DC_ELEMENTS.each do |name, value|
        parents.each do |parent_readers|
          parent = chain_reader(feed, parent_readers)
          parsed_value = parent.__send__("dc_#{name}")
          value = CGI.unescapeHTML(value) if value.kind_of?(String)
          assert_equal(value, parsed_value)

          plural_suffix = dc_plural_suffix(name, check_backward_compatibility)
          plural_reader = "dc_#{name}#{plural_suffix}"
          klass_name = "DublinCore#{Utils.to_class_name(name.to_s)}"
          klass = DublinCoreModel.const_get(klass_name)
          if name == :date
            t = Time.iso8601("2003-01-01T02:30:23+09:00")
            class << t
              alias_method(:to_s, :iso8601)
            end
            elems = parent.__send__(plural_reader)
            elems << klass.new(t.iso8601)
            new_elems = parent.__send__(plural_reader)
            values = new_elems.collect{|x| x.value}
            assert_equal([parent.__send__("dc_#{name}"), t], values)
          else
            elems = parent.__send__(plural_reader)
            elems << klass.new(new_value)
            new_elems = parent.__send__(plural_reader)
            values = new_elems.collect{|x| x.value}
            assert_equal([parent.__send__("dc_#{name}"), new_value],
                         values)
          end
        end
      end
    end

    def assert_dc_to_s(source, parents, check_backward_compatibility,
                       targets=nil)
      feed = Parser.parse(source)

      DC_ELEMENTS.each do |name, value|
        excepted = "<#{DC_PREFIX}:#{name}>#{value}</#{DC_PREFIX}:#{name}>"
        parents.each do |parent_readers|
          parent = chain_reader(feed, parent_readers)
          assert_equal(excepted, parent.__send__("dc_#{name}_elements"))
        end

        plural_suffix = dc_plural_suffix(name, check_backward_compatibility)
        reader = "dc_#{name}#{plural_suffix}"
        excepted = Array.new(2, excepted).join("\n")
        parents.each do |parent_readers|
          parent = chain_reader(feed, parent_readers)
          elems = parent.__send__(reader)
          klass_name = "DublinCore#{Utils.to_class_name(name.to_s)}"
          klass = DublinCoreModel.const_get(klass_name)
          elems << klass.new(parent.__send__("dc_#{name}"))
          assert_equal(excepted, parent.__send__("dc_#{name}_elements"))
        end
      end

      targets ||= parents.collect do |parent_readers|
        parent_readers.first
      end
      feed_root = REXML::Document.new(source).root
      targets.each do |target_xpath|
        parent = feed_root.elements[target_xpath]
        parent.each_element do |elem|
          if elem.namespace == DC_URI
            assert_equal(elem.text,
                         CGI.unescapeHTML(DC_ELEMENTS[elem.name.intern].to_s))
          end
        end
      end
    end
  end
end
