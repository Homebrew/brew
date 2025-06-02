# frozen_string_literal: false
require 'erb'

module RSS
  module Assertions
    def assert_parse(rss, assert_method, *args)
      __send__("assert_#{assert_method}", *args) do
        ::RSS::Parser.parse(rss)
      end
      __send__("assert_#{assert_method}", *args) do
        ::RSS::Parser.parse(rss, false).validate
      end
    end

    def assert_ns(prefix, uri)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NSError")
        rescue ::RSS::NSError => e
          assert_equal(prefix, e.prefix)
          assert_equal(uri, e.uri)
        end
      end
    end

    def assert_missing_tag(tag, parent)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise MissingTagError")
        rescue ::RSS::MissingTagError => e
          assert_equal(tag, e.tag)
          assert_equal(parent, e.parent)
        end
      end
    end

    def assert_too_much_tag(tag, parent)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise TooMuchTagError")
        rescue ::RSS::TooMuchTagError => e
          assert_equal(tag, e.tag)
          assert_equal(parent, e.parent)
        end
      end
    end

    def assert_missing_attribute(tag, attrname)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise MissingAttributeError")
        rescue ::RSS::MissingAttributeError => e
          assert_equal(tag, e.tag)
          assert_equal(attrname, e.attribute)
        end
      end
    end

    def assert_not_expected_tag(tag, uri, parent)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NotExpectedTagError")
        rescue ::RSS::NotExpectedTagError => e
          assert_equal(tag, e.tag)
          assert_equal(uri, e.uri)
          assert_equal(parent, e.parent)
        end
      end
    end

    def assert_not_available_value(tag, value, attribute=nil)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NotAvailableValueError")
        rescue ::RSS::NotAvailableValueError => e
          assert_equal(tag, e.tag)
          assert_equal(value, e.value)
          assert_equal(attribute, e.attribute)
        end
      end
    end

    def assert_not_set_error(name, variables)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NotSetError")
        rescue ::RSS::NotSetError => e
          assert_equal(name, e.name)
          assert_kind_of(Array, variables)
          assert_equal(variables.sort, e.variables.sort)
        end
      end
    end

    def assert_xml_declaration(version, encoding, standalone, rss)
      _wrap_assertion do
        assert_equal(version, rss.version)
        assert_equal(encoding, rss.encoding)
        assert_equal(standalone, rss.standalone)
      end
    end

    def assert_xml_stylesheet_attrs(attrs, xsl)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        ::RSS::XMLStyleSheet::ATTRIBUTES.each do |name|
          assert_equal(n_attrs[name], xsl.__send__(name))
        end
      end
    end

    def assert_xml_stylesheet(target, attrs, xsl)
      _wrap_assertion do
        if attrs.has_key?(:href)
          if !attrs.has_key?(:type) and attrs.has_key?(:guess_type)
            attrs[:type] = attrs[:guess_type]
          end
          assert_equal("xml-stylesheet", target)
          assert_xml_stylesheet_attrs(attrs, xsl)
        else
          assert_nil(target)
          assert_equal("", xsl.to_s)
        end
      end
    end

    def assert_xml_stylesheet_pis(attrs_ary, rss=nil)
      _wrap_assertion do
        if rss.nil?
          rss = ::RSS::RDF.new
          setup_rss10(rss)
        end
        xss_strs = []
        attrs_ary.each do |attrs|
          xss = ::RSS::XMLStyleSheet.new(attrs)
          xss_strs.push(xss.to_s)
          rss.xml_stylesheets.push(xss)
        end
        pi_str = rss.to_s.gsub(/<\?xml .*\n/, "").gsub(/\s*<[^\?].*\z/m, "")
        assert_equal(xss_strs.join("\n"), pi_str)
      end
    end

    def assert_xml_stylesheets(attrs, xss)
      _wrap_assertion do
        xss.each_with_index do |xs, i|
          assert_xml_stylesheet_attrs(attrs[i], xs)
        end
      end
    end


    def assert_atom_person(tag_name, generator)
      _wrap_assertion do
        name = "Mark Pilgrim"
        uri = "http://example.org/"
        email = "f8dy@example.com"

        assert_parse(generator.call(<<-EOA), :missing_tag, "name", tag_name)
  <#{tag_name}/>
EOA

        assert_parse(generator.call(<<-EOA), :missing_tag, "name", tag_name)
  <#{tag_name}>
    <uri>#{uri}</uri>
    <email>#{email}</email>
  </#{tag_name}>
EOA

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <#{tag_name}>
    <name>#{name}</name>
  </#{tag_name}>
EOA

        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <#{tag_name}>
    <name>#{name}</name>
    <uri>#{uri}</uri>
    <email>#{email}</email>
  </#{tag_name}>
EOA

        person = yield(feed)
        assert_not_nil(person)
        assert_equal(name, person.name.content)
        assert_equal(uri, person.uri.content)
        assert_equal(email, person.email.content)
      end
    end

    def assert_atom_category(generator)
      _wrap_assertion do
        term = "Music"
        scheme = "http://xmlns.com/wordnet/1.6/"
        label = "music"

        missing_args = [:missing_attribute, "category", "term"]
        assert_parse(generator.call(<<-EOA), *missing_args)
  <category/>
EOA

        assert_parse(generator.call(<<-EOA), *missing_args)
  <category scheme="#{scheme}" label="#{label}"/>
EOA

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <category term="#{term}"/>
EOA

      feed = RSS::Parser.parse(generator.call(<<-EOA))
  <category term="#{term}" scheme="#{scheme}" label="#{label}"/>
EOA

        category = yield(feed)
        assert_not_nil(category)
        assert_equal(term, category.term)
        assert_equal(scheme, category.scheme)
        assert_equal(label, category.label)
      end
    end

    def assert_atom_link(generator)
      _wrap_assertion do
        href = "http://example.org/feed.atom"
        rel = "self"
        type = "application/atom+xml"
        hreflang = "en"
        title = "Atom"
        length = "1024"

        assert_parse(generator.call(<<-EOA), :missing_attribute, "link", "href")
  <link/>
EOA

        assert_parse(generator.call(<<-EOA), :missing_attribute, "link", "href")
  <link rel="#{rel}" type="#{type}" hreflang="#{hreflang}"
        title="#{title}" length="#{length}"/>
EOA

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <link href="#{href}"/>
EOA

        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <link href="#{href}" rel="#{rel}" type="#{type}" hreflang="#{hreflang}"
        title="#{title}" length="#{length}"/>
EOA

        link = yield(feed)
        assert_not_nil(link)
        assert_equal(href, link.href)
        assert_equal(rel, link.rel)
        assert_equal(type, link.type)
        assert_equal(hreflang, link.hreflang)
        assert_equal(title, link.title)
        assert_equal(length, link.length)


        href = "http://example.org/index.html.ja"
        parent = link.parent.tag_name
        return if parent == "source"

        optional_attributes = %w(hreflang="ja" type="text/html")
        0.upto(optional_attributes.size) do |i|
          combination(optional_attributes, i).each do |attributes|
            attrs = attributes.join(" ")
            assert_parse(generator.call(<<-EOA), :too_much_tag, "link", parent)
  <link rel="alternate" #{attrs} href="#{href}"/>
  <link rel="alternate" #{attrs} href="#{href}"/>
EOA
          end
        end
      end
    end

    def assert_atom_generator(generator)
      _wrap_assertion do
        uri = "http://www.example.com/"
        version = "1.0"
        content = "Example Toolkit"

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <generator/>
EOA

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <generator uri="#{uri}" version="#{version}"/>
EOA

        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <generator uri="#{uri}" version="#{version}">#{content}</generator>
EOA

        gen = yield(feed)
        assert_not_nil(gen)
        assert_equal(uri, gen.uri)
        assert_equal(version, gen.version)
        assert_equal(content, gen.content)
      end
    end

    def assert_atom_icon(generator)
      _wrap_assertion do
        content = "http://www.example.com/example.png"

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <icon/>
EOA

        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <icon>#{content}</icon>
EOA

        icon = yield(feed)
        assert_not_nil(icon)
        assert_equal(content, icon.content)
      end
    end

    def assert_atom_text_construct(tag_name, generator)
      _wrap_assertion do
        [nil, "text", "html"].each do |type|
          attr = ""
          attr = " type=\"#{type}\"" if type
          assert_parse(generator.call(<<-EOA), :nothing_raised)
  <#{tag_name}#{attr}/>
EOA
        end

        assert_parse(generator.call(<<-EOA), :missing_tag, "div", tag_name)
  <#{tag_name} type="xhtml"/>
EOA

        args = ["x", Atom::URI, tag_name]
        assert_parse(generator.call(<<-EOA), :not_expected_tag, *args)
  <#{tag_name} type="xhtml"><x/></#{tag_name}>
EOA

        invalid_value = "invalid"
        args = ["type", invalid_value]
        assert_parse(generator.call(<<-EOA), :not_available_value, *args)
  <#{tag_name} type="#{invalid_value}"/>
EOA

        [
         [nil, "A lot of effort went into making this effortless"],
         ["text", "A lot of effort went into making this effortless"],
         ["html", "A <em>lot</em> of effort went into making this effortless"],
        ].each do |type, content|
          attr = ""
          attr = " type=\"#{type}\"" if type
          feed = RSS::Parser.parse(generator.call(<<-EOA))
  <#{tag_name}#{attr}>#{h content}</#{tag_name}>
EOA

          element = yield(feed)
          assert_not_nil(element)
          assert_equal(type, element.type)
          assert_equal(content, element.content)
        end

        [false, true].each do |with_space|
          xhtml_uri = "http://www.w3.org/1999/xhtml"
          xhtml_content = "<div xmlns=\"#{xhtml_uri}\">abc</div>"
          xhtml_element = RSS::XML::Element.new("div", nil, xhtml_uri,
                                                {"xmlns" => xhtml_uri},
                                                ["abc"])
          content = xhtml_content
          content = "  #{content}  " if with_space
          feed = RSS::Parser.parse(generator.call(<<-EOA))
  <#{tag_name} type="xhtml">#{content}</#{tag_name}>
EOA

          element = yield(feed)
          assert_not_nil(element)
          assert_equal("xhtml", element.type)
          assert_equal(xhtml_content, element.content)
          assert_equal(xhtml_element, element.xhtml)
        end
      end
    end

    def assert_atom_date_construct(tag_name, generator)
      _wrap_assertion do
        args = [tag_name, ""]
        assert_parse(generator.call(<<-EOR), :not_available_value, *args)
  <#{tag_name}/>
EOR

        [
         ["xxx", false],
         ["2007", false],
         ["2007/02/09", true],
        ].each do |invalid_value, can_parse|
          assert_not_available_value(tag_name, invalid_value) do
            RSS::Parser.parse(generator.call(<<-EOR))
  <#{tag_name}>#{invalid_value}</#{tag_name}>
EOR
          end

          feed = RSS::Parser.parse(generator.call(<<-EOR), false)
  <#{tag_name}>#{invalid_value}</#{tag_name}>
EOR
          value = yield(feed).content
          if can_parse
            assert_equal(Time.parse(invalid_value), value)
          else
            assert_nil(value)
          end
        end

        [
         "2003-12-13T18:30:02Z",
         "2003-12-13T18:30:02.25Z",
         "2003-12-13T18:30:02+01:00",
         "2003-12-13T18:30:02.25+01:00",
        ].each do |valid_value|
          assert_parse(generator.call(<<-EOR), :nothing_raised)
  <#{tag_name}>#{valid_value}</#{tag_name}>
EOR

          feed = RSS::Parser.parse(generator.call(<<-EOR))
  <#{tag_name}>#{valid_value}</#{tag_name}>
EOR
          assert_equal(Time.parse(valid_value), yield(feed).content)
        end
      end
    end

    def assert_atom_logo(generator)
      _wrap_assertion do
        content = "http://www.example.com/example.png"

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <logo/>
EOA

        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <logo>#{content}</logo>
EOA

        logo = yield(feed)
        assert_not_nil(logo)
        assert_equal(content, logo.content)
      end
    end

    def assert_atom_content(generator, &getter)
      _wrap_assertion do
        assert_atom_content_inline_text(generator, &getter)
        assert_atom_content_inline_xhtml(generator, &getter)
        assert_atom_content_inline_other(generator, &getter)
        assert_atom_content_out_of_line(generator, &getter)
      end
    end

    def assert_atom_content_inline_text(generator)
      _wrap_assertion do
        [nil, "text", "html"].each do |type|
          content = "<content"
          content << " type='#{type}'" if type

          suffix = "/>"
          assert_parse(generator.call(content + suffix), :nothing_raised)
          suffix = ">xxx</content>"
          assert_parse(generator.call(content + suffix), :nothing_raised)
        end

        [
         ["text", "sample content"],
         ["text/plain", "sample content"],
         ["html", "<em>sample</em> content"]
        ].each do |type, content_content|
          feed = RSS::Parser.parse(generator.call(<<-EOA))
  <content type="#{type}">#{h content_content}</content>
EOA
          content = yield(feed)
          assert_equal(type, content.type)
          if %w(text html).include?(type)
            assert(content.inline_text?)
          else
            assert(!content.inline_text?)
          end
          if type == "html"
            assert(content.inline_html?)
          else
            assert(!content.inline_html?)
          end
          assert(!content.inline_xhtml?)
          if type == "text/plain"
            assert(content.inline_other?)
            assert(content.inline_other_text?)
          else
            assert(!content.inline_other?)
            assert(!content.inline_other_text?)
          end
          assert(!content.inline_other_xml?)
          assert(!content.inline_other_base64?)
          assert(!content.out_of_line?)
          assert(!content.have_xml_content?)
          assert_equal(content_content, content.content)
        end
      end
    end

    def assert_atom_content_inline_xhtml(generator)
      _wrap_assertion do
        args = ["div", "content"]
        assert_parse(generator.call(<<-EOA), :missing_tag, *args)
  <content type="xhtml"/>
EOA

        args = ["x", Atom::URI, "content"]
        assert_parse(generator.call(<<-EOA), :not_expected_tag, *args)
  <content type="xhtml"><x/></content>
EOA

        xhtml_uri = "http://www.w3.org/1999/xhtml"
        xhtml_content = "<div xmlns=\"#{xhtml_uri}\">abc</div>"
        xhtml_element = RSS::XML::Element.new("div", nil, xhtml_uri,
                                              {"xmlns" => xhtml_uri},
                                              ["abc"])
        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <content type="xhtml">#{xhtml_content}</content>
EOA

        content = yield(feed)
        assert_not_nil(content)
        assert_equal("xhtml", content.type)
        assert(!content.inline_text?)
        assert(!content.inline_html?)
        assert(content.inline_xhtml?)
        assert(!content.inline_other?)
        assert(!content.inline_other_text?)
        assert(!content.inline_other_xml?)
        assert(!content.inline_other_base64?)
        assert(!content.out_of_line?)
        assert(content.have_xml_content?)
        assert_equal(xhtml_content, content.content)
        assert_equal(xhtml_element, content.xhtml)
      end
    end

    def assert_atom_content_inline_other(generator, &getter)
      _wrap_assertion do
        assert_atom_content_inline_other_text(generator, &getter)
        assert_atom_content_inline_other_xml(generator, &getter)
      end
    end

    def assert_atom_content_inline_other_text(generator)
      _wrap_assertion do
        type = "image/png"
        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <content type="#{type}"/>
EOA

        png_file = File.join(File.dirname(__FILE__), "dot.png")
        png = File.open(png_file, "rb") do |file|
          file.read.force_encoding("binary")
        end
        base64_content = [png].pack("m").delete("\n")

        [false, true].each do |with_space|
          xml_content = base64_content
          xml_content = "  #{base64_content}" if with_space
          feed = RSS::Parser.parse(generator.call(<<-EOA))
  <content type="#{type}">#{xml_content}</content>
EOA

          content = yield(feed)
          assert_not_nil(content)
          assert_equal(type, content.type)
          assert(!content.inline_text?)
          assert(!content.inline_html?)
          assert(!content.inline_xhtml?)
          assert(content.inline_other?)
          assert(!content.inline_other_text?)
          assert(!content.inline_other_xml?)
          assert(content.inline_other_base64?)
          assert(!content.out_of_line?)
          assert(!content.have_xml_content?)
          assert_equal(png, content.content)

          xml = REXML::Document.new(content.to_s).root
          assert_rexml_element([], {"type" => type}, base64_content, xml)
        end
      end
    end

    def assert_atom_content_inline_other_xml(generator)
      _wrap_assertion do
        type = "image/svg+xml"

        assert_parse(generator.call(<<-EOA), :nothing_raised)
  <content type="#{type}"/>
EOA

        svg_uri = "http://www.w3.org/2000/svg"
        svg_width = "50pt"
        svg_height = "20pt"
        svg_version = "1.0"
        text_x = "15"
        text_y = "15"
        text = "text"
        svg_content = <<-EOS
<svg
   xmlns="#{svg_uri}"
   width="#{svg_width}"
   height="#{svg_height}"
   version="#{svg_version}"
><text x="#{text_x}" y="#{text_y}">#{text}</text
></svg>
EOS

        text_element = RSS::XML::Element.new("text", nil, svg_uri,
                                             {
                                               "x" => text_x,
                                               "y" => text_y,
                                             },
                                             [text])
        svg_element = RSS::XML::Element.new("svg", nil, svg_uri,
                                            {
                                              "xmlns" => svg_uri,
                                              "width" => svg_width,
                                              "height" => svg_height,
                                              "version" => svg_version,
                                            },
                                            [text_element])
        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <content type="#{type}">#{svg_content}</content>
EOA

        content = yield(feed)
        assert_not_nil(content)
        assert_equal(type, content.type)
        assert(!content.inline_text?)
        assert(!content.inline_html?)
        assert(!content.inline_xhtml?)
        assert(content.inline_other?)
        assert(!content.inline_other_text?)
        assert(content.inline_other_xml?)
        assert(!content.inline_other_base64?)
        assert(!content.out_of_line?)
        assert(content.have_xml_content?)
        assert_equal(REXML::Document.new(svg_content).to_s.chomp,
                     REXML::Document.new(content.content).to_s.chomp)
        assert_equal(svg_element, content.xml)
        assert_nil(content.xhtml)
      end
    end

    def assert_atom_content_out_of_line(generator)
      _wrap_assertion do
        text_type = "text/plain"
        text_src = "http://example.com/README.txt"

        missing_args = [:missing_attribute, "content", "type"]
        # RSS Parser raises error even if this is "should" not "must".
        assert_parse(generator.call(<<-EOA), *missing_args)
  <content src="#{text_src}"/>
EOA

        content_content = "xxx"
        not_available_value_args = [:not_available_value,
                                    "content", content_content]
        assert_parse(generator.call(<<-EOA), *not_available_value_args)
  <content type="#{text_type}" src="#{text_src}">#{content_content}</content>
EOA

        feed = RSS::Parser.parse(generator.call(<<-EOA))
  <content type="#{text_type}" src="#{text_src}"/>
EOA
        content = yield(feed)
        assert_not_nil(content)
        assert_equal(text_type, content.type)
        assert_equal(text_src, content.src)
        assert(!content.inline_text?)
        assert(!content.inline_html?)
        assert(!content.inline_xhtml?)
        assert(!content.inline_other?)
        assert(!content.inline_other_text?)
        assert(!content.inline_other_xml?)
        assert(!content.inline_other_base64?)
        assert(content.out_of_line?)
        assert(!content.have_xml_content?)
        assert_nil(content.xml)
        assert_nil(content.xhtml)
        assert_equal("", content.content)
      end
    end

    def assert_atom_source(generator, &getter)
      _wrap_assertion do
        assert_atom_source_author(generator, &getter)
        assert_atom_source_category(generator, &getter)
        assert_atom_source_contributor(generator, &getter)
        assert_atom_source_generator(generator, &getter)
        assert_atom_source_icon(generator, &getter)
        assert_atom_source_id(generator, &getter)
        assert_atom_source_link(generator, &getter)
        assert_atom_source_logo(generator, &getter)
        assert_atom_source_rights(generator, &getter)
        assert_atom_source_subtitle(generator, &getter)
        assert_atom_source_title(generator, &getter)
        assert_atom_source_updated(generator, &getter)
      end
    end

    def assert_atom_source_author(generator)
      assert_atom_person("author", generator) do |feed|
        source = yield(feed)
        assert_equal(1, source.authors.size)
        source.author
      end
    end

    def assert_atom_source_category(generator)
      assert_atom_category(generator) do |feed|
        source = yield(feed)
        assert_equal(1, source.categories.size)
        source.category
      end
    end

    def assert_atom_source_contributor(generator)
      assert_atom_person("contributor", generator) do |feed|
        source = yield(feed)
        assert_equal(1, source.contributors.size)
        source.contributor
      end
    end

    def assert_atom_source_generator(generator)
      assert_atom_generator(generator) do |feed|
        yield(feed).generator
      end
    end

    def assert_atom_source_icon(generator)
      assert_atom_icon(generator) do |feed|
        yield(feed).icon
      end
    end

    def assert_atom_source_id(generator)
      id_content = "urn:uuid:a2fb588b-5674-4898-b420-265a734fea69"
      id = "<id>#{id_content}</id>"
      feed = RSS::Parser.parse(generator.call(id))
      assert_equal(id_content, yield(feed).id.content)
    end

    def assert_atom_source_link(generator)
      assert_atom_link(generator) do |feed|
        source = yield(feed)
        assert_equal(1, source.links.size)
        source.link
      end
    end

    def assert_atom_source_logo(generator)
      assert_atom_logo(generator) do |feed|
        yield(feed).logo
      end
    end

    def assert_atom_source_rights(generator)
      assert_atom_text_construct("rights", generator) do |feed|
        yield(feed).rights
      end
    end

    def assert_atom_source_subtitle(generator)
      assert_atom_text_construct("subtitle", generator) do |feed|
        yield(feed).subtitle
      end
    end

    def assert_atom_source_title(generator)
      assert_atom_text_construct("title", generator) do |feed|
        yield(feed).title
      end
    end

    def assert_atom_source_updated(generator)
      assert_atom_date_construct("updated", generator) do |feed|
        yield(feed).updated
      end
    end

    def assert_dublin_core(elems, target)
      _wrap_assertion do
        elems.each do |name, value|
          assert_equal(value, target.__send__("dc_#{name}"))
        end
      end
    end

    def assert_multiple_dublin_core(elems, target)
      _wrap_assertion do
        elems.each do |name, values, plural|
          plural ||= "#{name}s"
          actual = target.__send__("dc_#{plural}").collect{|x| x.value}
          assert_equal(values, actual)
        end
      end
    end

    def assert_syndication(elems, target)
      _wrap_assertion do
        elems.each do |name, value|
          meth = "sy_#{name}"
          value = value.to_i if meth == "sy_updateFrequency"
          assert_equal(value, target.__send__(meth ))
        end
      end
    end

    def assert_content(elems, target)
      _wrap_assertion do
        elems.each do |name, value|
          assert_equal(value, target.__send__("content_#{name}"))
        end
      end
    end

    def assert_trackback(attrs, target)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        if n_attrs["ping"]
          assert_equal(n_attrs["ping"], target.trackback_ping)
        end
        if n_attrs["abouts"]
          n_attrs["abouts"].each_with_index do |about, i|
            assert_equal(about, target.trackback_abouts[i].value)
          end
        end
      end
    end

    def assert_taxo_topic(topics, target)
      _wrap_assertion do
        topics.each_with_index do |topic, i|
          taxo_topic = target.taxo_topics[i]
          topic.each do |name, value|
            case name
            when :link
              assert_equal(value, taxo_topic.about)
              assert_equal(value, taxo_topic.taxo_link)
            when :topics
              assert_equal(value, taxo_topic.taxo_topics.resources)
            else
              assert_equal(value, taxo_topic.__send__("dc_#{name}"))
            end
          end
        end
      end
    end


    def assert_attributes(attrs, names, target)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        names.each do |info|
          if info.is_a?(String)
            name = info
            type = nil
          else
            name, type = info
          end
          value = n_attrs[name]
          if value.is_a?(Time)
            actual = target.__send__(name)
            assert_instance_of(Time, actual)
            assert_equal(value.to_i, actual.to_i)
          elsif value
            case type
            when :integer
              value = value.to_i
            when :boolean
              value = value == "true" if value.is_a?(String)
            end
            assert_equal(value, target.__send__(name))
          end
        end
      end
    end

    def assert_rexml_element(children, attrs, text, element, text_type=nil)
      _wrap_assertion do
        if children
          children_info = element.elements.collect {|e| [e.namespace, e.name]}
          assert_equal(children.collect {|uri, name| [uri, name]}.sort,
                       children_info.sort)
        end
        if attrs
          assert_equal(attrs.collect {|k, v| [k, v]}.sort,
                       element.attributes.collect {|k, v| [k, v]}.sort)
        end
        case text_type
        when :time
          assert_not_nil(element.text)
          assert_equal(Time.parse(text).to_s, Time.parse(element.text).to_s)
        else
          assert_equal(text, element.text)
        end
      end
    end

    def _assert_maker_atom_persons(feed_type, maker_readers, feed_readers)
      _wrap_assertion do
        persons = []
        feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
          yield maker
          targets = chain_reader(maker, maker_readers)
          targets.each do |target|
            person = {
              :name => target.name,
              :uri => target.uri,
              :email => target.email,
            }
            persons << person if person[:name]
          end
        end

        actual_persons = chain_reader(feed, feed_readers) || []
        actual_persons = actual_persons.collect do |person|
          {
            :name => person.name ? person.name.content : nil,
            :uri => person.uri ? person.uri.content : nil,
            :email => person.email ? person.email.content : nil,
          }
        end
        assert_equal(persons, actual_persons)
      end
    end

    def assert_maker_atom_persons(feed_type, maker_readers, feed_readers,
                                  not_set_error_name=nil,
                                  parent_not_set_error_name=nil,
                                  parent_not_set_variable=nil)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        args = [feed_type, maker_readers, feed_readers]
        if parent_not_set_error_name or parent_not_set_variable
          assert_not_set_error(parent_not_set_error_name,
                               parent_not_set_variable) do
            _assert_maker_atom_persons(*args) do |maker|
              yield maker
            end
          end
        else
          _assert_maker_atom_persons(*args) do |maker|
            yield maker
          end
        end

        assert_not_set_error(not_set_error_name, %w(name)) do
          _assert_maker_atom_persons(feed_type, maker_readers,
                                     feed_readers) do |maker|
            yield maker
            targets = chain_reader(maker, maker_readers)
            targets.new_child
          end
        end

        assert_not_set_error(not_set_error_name, %w(name)) do
          _assert_maker_atom_persons(feed_type, maker_readers,
                                     feed_readers) do |maker|
            yield maker
            targets = chain_reader(maker, maker_readers)
            target = targets.new_child
            target.uri = "http://example.com/~me/"
          end
        end

        assert_not_set_error(not_set_error_name, %w(name)) do
          _assert_maker_atom_persons(feed_type, maker_readers,
                                     feed_readers) do |maker|
            yield maker
            targets = chain_reader(maker, maker_readers)
            target = targets.new_child
            target.email = "me@example.com"
          end
        end

        assert_not_set_error(not_set_error_name, %w(name)) do
          _assert_maker_atom_persons(feed_type, maker_readers,
                                     feed_readers) do |maker|
            yield maker
            targets = chain_reader(maker, maker_readers)
            target = targets.new_child
            target.uri = "http://example.com/~me/"
            target.email = "me@example.com"
          end
        end

        _assert_maker_atom_persons(feed_type, maker_readers,
                                   feed_readers) do |maker|
          yield maker
          targets = chain_reader(maker, maker_readers)
          target = targets.new_child
          target.name = "me"
        end

        _assert_maker_atom_persons(feed_type, maker_readers,
                                   feed_readers) do |maker|
          yield maker
          targets = chain_reader(maker, maker_readers)
          target = targets.new_child
          target.name = "me"
          target.uri = "http://example.com/~me/"
        end

        _assert_maker_atom_persons(feed_type, maker_readers,
                                   feed_readers) do |maker|
          yield maker
          targets = chain_reader(maker, maker_readers)
          target = targets.new_child
          target.name = "me"
          target.email = "me@example.com"
        end

        _assert_maker_atom_persons(feed_type, maker_readers,
                                   feed_readers) do |maker|
          yield maker
          targets = chain_reader(maker, maker_readers)
          target = targets.new_child
          target.name = "me"
          target.uri = "http://example.com/~me/"
          target.email = "me@example.com"
        end

        _assert_maker_atom_persons(feed_type, maker_readers,
                                   feed_readers) do |maker|
          yield maker
          targets = chain_reader(maker, maker_readers)

          target = targets.new_child
          target.name = "me"
          target.uri = "http://example.com/~me/"
          target.email = "me@example.com"

          target = targets.new_child
          target.name = "you"
          target.uri = "http://example.com/~you/"
          target.email = "you@example.com"
        end

        assert_not_set_error(not_set_error_name, %w(name)) do
          _assert_maker_atom_persons(feed_type, maker_readers,
                                     feed_readers) do |maker|
            yield maker
            targets = chain_reader(maker, maker_readers)

            target = targets.new_child
            target.name = "me"
            target.uri = "http://example.com/~me/"
            target.email = "me@example.com"

            targets.new_child
          end
        end
      end
    end

    def _assert_maker_atom_text_construct(feed_type, maker_readers,
                                          feed_readers, &block)
      maker_extractor = Proc.new do |target|
        text = {
          :type => target.type,
          :content => target.content,
          :xml_content => target.xml_content,
        }
        if text[:type] == "xhtml"
          if text[:xml_content]
            xml_content = text[:xml_content]
            xhtml_uri = "http://www.w3.org/1999/xhtml"
            unless xml_content.is_a?(RSS::XML::Element) and
                ["div", xhtml_uri] == [xml_content.name, xml_content.uri]
              children = xml_content
              children = [children] unless children.is_a?(Array)
              xml_content = RSS::XML::Element.new("div", nil, xhtml_uri,
                                                  {"xmlns" => xhtml_uri},
                                                  children)
              text[:xml_content] = xml_content
            end
            text
          else
            nil
          end
        else
          text[:content] ? text : nil
        end
      end
      feed_extractor = Proc.new do |target|
        {
          :type => target.type,
          :content => target.content,
          :xml_content => target.xhtml,
        }
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, true,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_text_construct(feed_type, maker_readers, feed_readers,
                                         parent_not_set_error_name=nil,
                                         parent_not_set_variable=nil,
                                         not_set_error_name=nil)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        args = [feed_type, maker_readers, feed_readers]
        if parent_not_set_error_name or parent_not_set_variable
          assert_not_set_error(parent_not_set_error_name,
                               parent_not_set_variable) do
            _assert_maker_atom_text_construct(*args) do |maker|
              yield maker
            end
          end
        else
          _assert_maker_atom_text_construct(*args) do |maker|
            yield maker
          end
        end

        assert_not_set_error(not_set_error_name, %w(content)) do
          _assert_maker_atom_text_construct(*args) do |maker|
            yield maker
            target = chain_reader(maker, maker_readers) {|x| x}
            target.type = "text"
          end
        end

        assert_not_set_error(not_set_error_name, %w(content)) do
          _assert_maker_atom_text_construct(*args) do |maker|
            yield maker
            target = chain_reader(maker, maker_readers) {|x| x}
            target.type = "html"
          end
        end

        assert_not_set_error(not_set_error_name, %w(xml_content)) do
          _assert_maker_atom_text_construct(*args) do |maker|
            yield maker
            target = chain_reader(maker, maker_readers) {|x| x}
            target.type = "xhtml"
          end
        end

        assert_not_set_error(not_set_error_name, %w(xml_content)) do
          _assert_maker_atom_text_construct(*args) do |maker|
            yield maker
            target = chain_reader(maker, maker_readers) {|x| x}
            target.type = "xhtml"
            target.content = "Content"
          end
        end

        _assert_maker_atom_text_construct(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers) {|x| x}
          target.type = "text"
          target.content = "Content"
        end

        _assert_maker_atom_text_construct(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers) {|x| x}
          target.type = "html"
          target.content = "<em>Content</em>"
        end

        _assert_maker_atom_text_construct(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers) {|x| x}
          target.type = "xhtml"
          target.xml_content = "text only"
        end

        _assert_maker_atom_text_construct(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers) {|x| x}
          target.type = "xhtml"
          target.xml_content = RSS::XML::Element.new("unknown")
        end
      end
    end

    def _assert_maker_atom_date_construct(feed_type, maker_readers,
                                          feed_readers, &block)
      maker_extractor = Proc.new do |target|
        date = {
          :content => target,
        }
        date[:content] ? date : nil
      end
      feed_extractor = Proc.new do |target|
        {
          :content => target.content,
        }
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, false,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_date_construct(feed_type, maker_readers, feed_readers,
                                         parent_not_set_error_name=nil,
                                         parent_not_set_variable=nil)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        if parent_not_set_error_name or parent_not_set_variable
          assert_not_set_error(parent_not_set_error_name,
                               parent_not_set_variable) do
            _assert_maker_atom_date_construct(*args) do |maker|
              yield maker
            end
          end
        else
          _assert_maker_atom_date_construct(*args) do |maker|
            yield maker
          end
        end

        maker_readers = maker_readers.dup
        writer = "#{maker_readers.pop}="
        _assert_maker_atom_date_construct(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.__send__(writer, Time.now)
        end
      end
    end

    def _assert_maker_atom_element(feed_type,
                                   maker_readers,
                                   maker_readers_need_block,
                                   feed_readers,
                                   maker_extractor,
                                   feed_extractor)
      _wrap_assertion do
        element = nil
        feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
          yield maker
          if maker_readers_need_block
            target = chain_reader(maker, maker_readers) {|x| x}
          else
            target = chain_reader(maker, maker_readers)
          end
          element = maker_extractor.call(target)
        end

        target = chain_reader(feed, feed_readers)
        if target
          actual_element = feed_extractor.call(target)
        else
          actual_element = nil
        end
        assert_equal(element, actual_element)
      end
    end

    def _assert_maker_atom_elements(feed_type, maker_readers, feed_readers,
                                    maker_extractor, feed_extractor,
                                    invalid_feed_checker=nil)
      _wrap_assertion do
        elements = []
        invalid_feed_exception = nil
        feed = nil
        begin
          feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            targets = chain_reader(maker, maker_readers)
            targets.each do |target|
              element = maker_extractor.call(target)
              elements << element if element
            end
            if invalid_feed_checker
              invalid_feed_exception = invalid_feed_checker.call(targets)
            end
          end
        rescue RSS::Error
          if invalid_feed_exception.is_a?(RSS::TooMuchTagError)
            assert_too_much_tag(invalid_feed_exception.tag,
                                invalid_feed_exception.parent) do
              raise
            end
          else
            raise
          end
        end

        if invalid_feed_exception.nil?
          actual_elements = chain_reader(feed, feed_readers) || []
          actual_elements = actual_elements.collect do |target|
            feed_extractor.call(target)
          end
          assert_equal(elements, actual_elements)
        end
      end
    end

    def assert_maker_atom_element(feed_type, maker_readers, feed_readers,
                                  setup_target, optional_variables,
                                  required_variable, assert_method_name,
                                  not_set_error_name=nil,
                                  *additional_args)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        0.upto(optional_variables.size) do |i|
          combination(optional_variables, i).each do |names|
            have = {}
            names.each do |name|
              have[name.intern] = true
            end
            have_required_variable_too =
              have.merge({required_variable.intern => true})

            assert_not_set_error(not_set_error_name, [required_variable]) do
              __send__(assert_method_name, feed_type, maker_readers,
                       feed_readers, *additional_args) do |maker|
                yield maker
                target = chain_reader(maker, maker_readers) {|x| x}
                setup_target.call(target, have)
              end
            end

            __send__(assert_method_name, feed_type, maker_readers, feed_readers,
                     *additional_args) do |maker|
              yield maker
              target = chain_reader(maker, maker_readers) {|x| x}
              setup_target.call(target, have_required_variable_too)
            end
          end
        end
      end
    end

    def assert_maker_atom_elements(feed_type, maker_readers, feed_readers,
                                   setup_target, optional_variables,
                                   required_variable, assert_method_name,
                                   not_set_error_name=nil,
                                   *additional_args)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        0.upto(optional_variables.size) do |i|
          combination(optional_variables, i).each do |names|
            have = {}
            names.each do |name|
              have[name.intern] = true
            end
            have_required_variable_too =
              have.merge({required_variable.intern => true})

            assert_not_set_error(not_set_error_name, [required_variable]) do
              __send__(assert_method_name, feed_type, maker_readers,
                       feed_readers, *additional_args) do |maker|
                yield maker
                targets = chain_reader(maker, maker_readers)
                setup_target.call(targets, have)
              end
            end

            __send__(assert_method_name, feed_type, maker_readers, feed_readers,
                     *additional_args) do |maker|
              yield maker
              targets = chain_reader(maker, maker_readers)
              setup_target.call(targets, have_required_variable_too)
            end

            __send__(assert_method_name, feed_type, maker_readers, feed_readers,
                     *additional_args) do |maker|
              yield maker
              targets = chain_reader(maker, maker_readers)
              setup_target.call(targets, have_required_variable_too)
              setup_target.call(targets, have_required_variable_too)
            end

            assert_not_set_error(not_set_error_name, [required_variable]) do
            __send__(assert_method_name, feed_type, maker_readers, feed_readers,
                     *additional_args) do |maker|
                yield maker
                targets = chain_reader(maker, maker_readers)
                setup_target.call(targets, have_required_variable_too)
                setup_target.call(targets, have)
              end
            end
          end
        end
      end
    end

    def _assert_maker_atom_categories(feed_type, maker_readers,
                                      feed_readers, &block)
      maker_extractor = Proc.new do |target|
        category = {
          :term => target.term,
          :scheme => target.scheme,
          :label => target.label,
        }
        category[:term] ? category : nil
      end
      feed_extractor = Proc.new do |target|
        {
          :term => target.term,
          :scheme => target.scheme,
          :label => target.label,
        }
      end
      _assert_maker_atom_elements(feed_type, maker_readers, feed_readers,
                                  maker_extractor, feed_extractor, &block)
    end

    def assert_maker_atom_categories(feed_type, maker_readers, feed_readers,
                                     not_set_error_name=nil, &block)
      _wrap_assertion do
        _assert_maker_atom_categories(feed_type, maker_readers,
                                      feed_readers) do |maker|
          yield maker
        end

        setup_target = Proc.new do |targets, have|
          target = targets.new_child
          target.term = "music" if have[:term]
          target.scheme = "http://example.com/category/music" if have[:scheme]
          target.label = "Music" if have[:label]
        end

        optional_variables = %w(scheme label)

        assert_maker_atom_elements(feed_type, maker_readers, feed_readers,
                                   setup_target, optional_variables,
                                   "term", :_assert_maker_atom_categories,
                                   not_set_error_name, &block)
      end
    end

    def _assert_maker_atom_generator(feed_type, maker_readers,
                                     feed_readers, &block)
      maker_extractor = Proc.new do |target|
        generator = {
          :uri => target.uri,
          :version => target.version,
          :content => target.content,
        }
        generator[:content] ? generator : nil
      end
      feed_extractor = Proc.new do |target|
        {
          :uri => target.uri,
          :version => target.version,
          :content => target.content,
        }
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, true,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_generator(feed_type, maker_readers, feed_readers,
                                    not_set_error_name=nil, &block)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        _assert_maker_atom_generator(feed_type, maker_readers,
                                     feed_readers) do |maker|
          yield maker
        end

        setup_target = Proc.new do |target, have|
          target.content = "RSS Maker" if have[:content]
          target.uri = "http://example.com/rss/maker" if have[:uri]
          target.version = "0.0.1" if have[:version]
        end

        optional_variables = %w(uri version)

        assert_maker_atom_element(feed_type, maker_readers, feed_readers,
                                  setup_target, optional_variables,
                                  "content", :_assert_maker_atom_generator,
                                  not_set_error_name, &block)
      end
    end

    def _assert_maker_atom_icon(feed_type, maker_readers, feed_readers,
                                accessor_base, &block)
      maker_extractor = Proc.new do |target|
        icon = {
          :content => target.__send__(accessor_base),
        }
        icon[:content] ? icon : nil
      end
      feed_extractor = Proc.new do |target|
        {
          :content => target.content,
        }
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, true,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_icon(feed_type, maker_readers, feed_readers,
                               accessor_base=nil, not_set_error_name=nil)
      _wrap_assertion do
        accessor_base ||= "url"
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        _assert_maker_atom_icon(feed_type, maker_readers, feed_readers,
                                accessor_base) do |maker|
          yield maker
        end

        _assert_maker_atom_icon(feed_type, maker_readers, feed_readers,
                                accessor_base) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.__send__("#{accessor_base}=", "http://example.com/icon.png")
        end
      end
    end

    def _assert_maker_atom_links(feed_type, maker_readers, feed_readers,
                                 allow_duplication=false, &block)
      maker_extractor = Proc.new do |target|
        link = {
          :href => target.href,
          :rel => target.rel,
          :type => target.type,
          :hreflang => target.hreflang,
          :title => target.title,
          :length => target.length,
        }
        link[:href] ? link : nil
      end
      feed_extractor = Proc.new do |target|
        {
          :href => target.href,
          :rel => target.rel,
          :type => target.type,
          :hreflang => target.hreflang,
          :title => target.title,
          :length => target.length,
        }
      end

      if feed_readers.first == "entries"
        parent = "entry"
      else
        parent = feed_type
      end
      invalid_feed_checker = Proc.new do |targets|
        infos = {}
        invalid_exception = nil
        targets.each do |target|
          key = [target.hreflang, target.type]
          if infos.has_key?(key)
            invalid_exception = RSS::TooMuchTagError.new("link", parent)
            break
          end
          infos[key] = true if target.rel.nil? or target.rel == "alternate"
        end
        invalid_exception
      end
      invalid_feed_checker = nil if allow_duplication
      _assert_maker_atom_elements(feed_type, maker_readers, feed_readers,
                                  maker_extractor, feed_extractor,
                                  invalid_feed_checker,
                                  &block)
    end

    def assert_maker_atom_links(feed_type, maker_readers, feed_readers,
                                not_set_error_name=nil, allow_duplication=false,
                                &block)
      _wrap_assertion do
        _assert_maker_atom_links(feed_type, maker_readers,
                                 feed_readers) do |maker|
          yield maker
        end

        langs = %(ja en fr zh po)
        setup_target = Proc.new do |targets, have|
          target = targets.new_child
          lang = langs[targets.size % langs.size]
          target.href = "http://example.com/index.html.#{lang}" if have[:href]
          target.rel = "alternate" if have[:rel]
          target.type = "text/xhtml" if have[:type]
          target.hreflang = lang if have[:hreflang]
          target.title = "FrontPage(#{lang})" if have[:title]
          target.length = 1024 if have[:length]
        end

        optional_variables = %w(rel type hreflang title length)

        assert_maker_atom_elements(feed_type, maker_readers, feed_readers,
                                   setup_target, optional_variables,
                                   "href", :_assert_maker_atom_links,
                                   not_set_error_name, allow_duplication,
                                   &block)
      end
    end

    def _assert_maker_atom_logo(feed_type, maker_readers, feed_readers,
                                accessor_base, &block)
      maker_extractor = Proc.new do |target|
        logo = {
          :uri => target.__send__(accessor_base),
        }
        logo[:uri] ? logo : nil
      end
      feed_extractor = Proc.new do |target|
        {
          :uri => target.content,
        }
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, true,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_logo(feed_type, maker_readers, feed_readers,
                               accessor_base=nil, not_set_error_name=nil)
      _wrap_assertion do
        accessor_base ||= "uri"
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        _assert_maker_atom_logo(feed_type, maker_readers, feed_readers,
                                accessor_base) do |maker|
          yield maker
        end

        _assert_maker_atom_logo(feed_type, maker_readers, feed_readers,
                                accessor_base) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.__send__("#{accessor_base}=", "http://example.com/logo.png")
        end
      end
    end

    def _assert_maker_atom_id(feed_type, maker_readers, feed_readers, &block)
      maker_extractor = Proc.new do |target|
        id = {
          :uri => target.id,
        }
        id[:uri] ? id : nil
      end
      feed_extractor = Proc.new do |target|
        if target.id
          {
            :uri => target.id.content,
          }
        else
          nil
        end
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, true,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_id(feed_type, maker_readers, feed_readers,
                             not_set_error_name=nil)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"

        args = [feed_type, maker_readers, feed_readers]
        _assert_maker_atom_id(*args) do |maker|
          yield maker
        end

        _assert_maker_atom_id(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.id = "http://example.com/id/1"
        end
      end
    end

    def _assert_maker_atom_content(feed_type, maker_readers,
                                   feed_readers, &block)
      maker_extractor = Proc.new do |target|
        content = {
          :type => target.type,
          :src => target.src,
          :content => target.content,
          :xml => target.xml,
          :inline_text => target.inline_text?,
          :inline_html => target.inline_html?,
          :inline_xhtml => target.inline_xhtml?,
          :inline_other => target.inline_other?,
          :inline_other_text => target.inline_other_text?,
          :inline_other_xml => target.inline_other_xml?,
          :inline_other_base64 => target.inline_other_base64?,
          :out_of_line => target.out_of_line?,
        }
        content[:src] = nil if content[:src] and content[:content]
        if content[:type] or content[:content]
          content
        else
          nil
        end
      end
      feed_extractor = Proc.new do |target|
        {
          :type => target.type,
          :src => target.src,
          :content => target.content,
          :xml => target.xml,
          :inline_text => target.inline_text?,
          :inline_html => target.inline_html?,
          :inline_xhtml => target.inline_xhtml?,
          :inline_other => target.inline_other?,
          :inline_other_text => target.inline_other_text?,
          :inline_other_xml => target.inline_other_xml?,
          :inline_other_base64 => target.inline_other_base64?,
          :out_of_line => target.out_of_line?,
        }
      end
      _assert_maker_atom_element(feed_type,
                                 maker_readers, true,
                                 feed_readers,
                                 maker_extractor,
                                 feed_extractor,
                                 &block)
    end

    def assert_maker_atom_content(feed_type, maker_readers, feed_readers,
                                  not_set_error_name=nil, &block)
      _wrap_assertion do
        not_set_error_name ||= "maker.#{maker_readers.join('.')}"
        args = [feed_type, maker_readers, feed_readers, not_set_error_name]
        assert_maker_atom_content_inline_text(*args, &block)
        assert_maker_atom_content_inline_xhtml(*args, &block)
        assert_maker_atom_content_inline_other(*args, &block)
        assert_maker_atom_content_out_of_line(*args, &block)
      end
    end

    def assert_maker_atom_content_inline_text(feed_type, maker_readers,
                                              feed_readers, not_set_error_name)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        _assert_maker_atom_content(*args) do |maker|
          yield maker
        end

        assert_not_set_error(not_set_error_name, %w(content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "text"
          end
        end

        assert_not_set_error(not_set_error_name, %w(content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "html"
          end
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.content = ""
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "text"
          target.content = "example content"
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "html"
          target.content = "<em>text</em>"
        end
      end
    end

    def assert_maker_atom_content_inline_xhtml(feed_type, maker_readers,
                                               feed_readers, not_set_error_name)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        assert_not_set_error(not_set_error_name, %w(xml_content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "xhtml"
          end
        end

        assert_not_set_error(not_set_error_name, %w(xml_content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "xhtml"
            target.content = "dummy"
          end
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "xhtml"
          target.xml_content = "text"
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "xhtml"
          target.xml = "text"
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "xhtml"
          target.xml_content =
            RSS::XML::Element.new("em", nil, nil, {}, ["text"])
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "xhtml"
          target.xml = RSS::XML::Element.new("em", nil, nil, {}, ["text"])
        end


        xhtml_uri = "http://www.w3.org/1999/xhtml"
        em = RSS::XML::Element.new("em", nil, nil, {}, ["text"])
        em_with_xhtml_uri =
          RSS::XML::Element.new("em", nil, xhtml_uri, {}, ["text"])
        feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "xhtml"
          target.xml = em
        end
        assert_equal(RSS::XML::Element.new("div", nil, xhtml_uri,
                                           {"xmlns" => xhtml_uri},
                                           [em_with_xhtml_uri]),
                     chain_reader(feed, feed_readers).xml)

        div = RSS::XML::Element.new("div", nil, xhtml_uri,
                                    {"xmlns" => xhtml_uri,
                                     "class" => "sample"},
                                    ["text"])
        feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "xhtml"
          target.xml = div
        end
        assert_equal(div, chain_reader(feed, feed_readers).xml)
      end
    end

    def assert_maker_atom_content_inline_other(*args, &block)
      _wrap_assertion do
        assert_maker_atom_content_inline_other_xml(*args, &block)
        assert_maker_atom_content_inline_other_text(*args, &block)
        assert_maker_atom_content_inline_other_base64(*args, &block)
      end
    end

    def assert_maker_atom_content_inline_other_xml(feed_type, maker_readers,
                                                   feed_readers,
                                                   not_set_error_name)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        assert_not_set_error(not_set_error_name, %w(xml_content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "application/xml"
          end
        end

        assert_not_set_error(not_set_error_name, %w(xml_content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "svg/image+xml"
          end
        end

        svg_uri = "http://www.w3.org/2000/svg"
        rect = RSS::XML::Element.new("rect", nil, svg_uri,
                                     {"x" => "0.5cm",
                                      "y" => "0.5cm",
                                      "width" => "2cm",
                                      "height" => "1cm"})
        svg = RSS::XML::Element.new("svg", nil, svg_uri,
                                    {"xmlns" => svg_uri,
                                     "version" => "1.1",
                                     "width" => "5cm",
                                     "height" => "4cm"},
                                    [rect])
        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/svg+xml"
          target.xml = svg
        end

        feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/svg+xml"
          target.xml = svg
        end
        assert_equal(svg, chain_reader(feed, feed_readers).xml)
      end
    end

    def assert_maker_atom_content_inline_other_text(feed_type, maker_readers,
                                                    feed_readers,
                                                    not_set_error_name)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        assert_not_set_error(not_set_error_name, %w(content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "text/plain"
          end
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "text/plain"
          target.content = "text"
        end
      end
    end

    def assert_maker_atom_content_inline_other_base64(feed_type, maker_readers,
                                                      feed_readers,
                                                      not_set_error_name)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        content = "\211PNG\r\n\032\n"
        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/png"
          target.content = content
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/png"
          target.src = "http://example.com/logo.png"
          target.content = content
        end

        feed = RSS::Maker.make("atom:#{feed_type}") do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/png"
          target.src = "http://example.com/logo.png"
          target.content = content
        end
        target = chain_reader(feed, feed_readers)
        assert_nil(target.src)
        assert_equal(content, target.content)
      end
    end

    def assert_maker_atom_content_out_of_line(feed_type, maker_readers,
                                              feed_readers, not_set_error_name)
      _wrap_assertion do
        args = [feed_type, maker_readers, feed_readers]
        assert_not_set_error(not_set_error_name, %w(content)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.type = "image/png"
          end
        end

        assert_not_set_error(not_set_error_name, %w(type)) do
          RSS::Maker.make("atom:#{feed_type}") do |maker|
            yield maker
            target = chain_reader(maker, maker_readers)
            target.src = "http://example.com/logo.png"
          end
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/png"
          target.src = "http://example.com/logo.png"
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "image/png"
          target.content = "\211PNG\r\n\032\n"
        end

        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "application/xml"
          target.src = "http://example.com/sample.xml"
        end


        _assert_maker_atom_content(*args) do |maker|
          yield maker
          target = chain_reader(maker, maker_readers)
          target.type = "text/plain"
          target.src = "http://example.com/README.txt"
        end
      end
    end

    def assert_slash_elements(expected, target)
      assert_equal(expected,
                   {
                     "section" => target.slash_section,
                     "department" => target.slash_department,
                     "comments" => target.slash_comments,
                     "hit_parades" => target.slash_hit_parades,
                   })
      assert_equal(expected["hit_parades"].join(","),
                   target.slash_hit_parade)
    end

    def chain_reader(target, readers, &block)
      readers.inject(target) do |result, reader|
        return nil if result.nil?
        result.__send__(reader, &block)
      end
    end

    def normalized_attrs(attrs)
      n_attrs = {}
      attrs.each do |name, value|
        n_attrs[name.to_s] = value
      end
      n_attrs
    end

    def combination(elements, n)
      if n <= 0 or elements.size < n
        []
      elsif n == 1
        elements.collect {|element| [element]}
      else
        first, *rest = elements
        combination(rest, n - 1).collect do |sub_elements|
          [first, *sub_elements]
        end + combination(rest, n)
      end
    end

    def tag(name, content=nil, attributes={})
      attributes = attributes.collect do |key, value|
        "#{ERB::Util.h(key)}=\"#{ERB::Util.h(value)}\""
      end.join(" ")
      begin_tag = "<#{name}"
      begin_tag << " #{attributes}" unless attributes.empty?
      if content
        "#{begin_tag}>#{content}</#{name}>\n"
      else
        "#{begin_tag}/>\n"
      end
    end
  end
end
