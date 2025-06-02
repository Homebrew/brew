# frozen_string_literal: false
require "rexml/document"

require_relative "rss-testcase"

require "rss/atom"

module RSS
  class TestAtomCore < TestCase
    def setup
      @uri = "http://www.w3.org/2005/Atom"
      @xhtml_uri = "http://www.w3.org/1999/xhtml"
    end

    def test_feed
      version = "1.0"
      encoding = "UTF-8"
      standalone = false

      feed = Atom::Feed.new(version, encoding, standalone)
      assert_equal("", feed.to_s)

      author = feed.class::Author.new
      name = feed.class::Author::Name.new
      name.content = "an author"
      author.name = name
      assert_not_equal("", author.to_s)
      feed.authors << author
      assert_equal("", feed.to_s)

      id = feed.class::Id.new
      id.content = "http://example.com/atom.xml"
      assert_not_equal("", id.to_s)
      feed.id = id
      assert_equal("", feed.to_s)

      title = feed.class::Title.new
      title.content = "a title"
      assert_not_equal("", title.to_s)
      feed.title = title
      assert_equal("", feed.to_s)

      updated = feed.class::Updated.new
      updated.content = Time.now
      assert_not_equal("", updated.to_s)
      feed.updated = updated
      assert_not_equal("", feed.to_s)


      feed.authors.clear
      assert_equal("", feed.to_s)
      entry = Atom::Feed::Entry.new
      setup_entry(entry)
      assert_not_equal("", entry.to_s)

      author = entry.authors.first
      entry.authors.clear
      assert_equal("", entry.to_s)
      entry.parent = feed
      assert_equal("", entry.to_s)
      feed.authors << author
      assert_not_equal("", entry.to_s)
      feed.authors.clear
      feed.entries << entry
      assert_equal("", feed.to_s)
      entry.authors << author
      assert_not_equal("", entry.to_s)
      assert_not_equal("", feed.to_s)

      doc = REXML::Document.new(feed.to_s)
      xmldecl = doc.xml_decl

      assert_equal(version, xmldecl.version)
      assert_equal(encoding, xmldecl.encoding.to_s)
      assert_equal(standalone, !xmldecl.standalone.nil?)

      assert_equal(@uri, doc.root.namespace)
    end

    def test_entry
      version = "1.0"
      encoding = "UTF-8"
      standalone = false

      entry = Atom::Entry.new(version, encoding, standalone)
      setup_entry(entry)

      author = entry.authors.first
      entry.authors.clear
      assert_equal("", entry.to_s)
      source = Atom::Entry::Source.new
      source.authors << author
      entry.source = source
      assert_not_equal("", entry.to_s)

      doc = REXML::Document.new(entry.to_s)
      xmldecl = doc.xml_decl

      assert_equal(version, xmldecl.version)
      assert_equal(encoding, xmldecl.encoding.to_s)
      assert_equal(standalone, !xmldecl.standalone.nil?)

      assert_equal(@uri, doc.root.namespace)
    end

    def test_not_displayed_xml_stylesheets
      feed = Atom::Feed.new
      plain_feed = feed.to_s
      3.times do
        feed.xml_stylesheets.push(XMLStyleSheet.new)
        assert_equal(plain_feed, feed.to_s)
      end
    end

    def test_atom_author
      assert_atom_person_to_s(Atom::Feed::Author)
      assert_atom_person_to_s(Atom::Feed::Entry::Author)
      assert_atom_person_to_s(Atom::Entry::Author)
      assert_atom_person_to_s(Atom::Feed::Entry::Source::Author)
      assert_atom_person_to_s(Atom::Entry::Source::Author)
    end

    def test_atom_category
      assert_atom_category_to_s(Atom::Feed::Category)
      assert_atom_category_to_s(Atom::Feed::Entry::Category)
      assert_atom_category_to_s(Atom::Entry::Category)
      assert_atom_category_to_s(Atom::Feed::Entry::Source::Category)
      assert_atom_category_to_s(Atom::Entry::Source::Category)
    end

    def test_atom_contributor
      assert_atom_person_to_s(Atom::Feed::Contributor)
      assert_atom_person_to_s(Atom::Feed::Entry::Contributor)
      assert_atom_person_to_s(Atom::Entry::Contributor)
      assert_atom_person_to_s(Atom::Feed::Entry::Source::Contributor)
      assert_atom_person_to_s(Atom::Entry::Source::Contributor)
    end

    def test_atom_generator
      assert_atom_generator_to_s(Atom::Feed::Generator)
      assert_atom_generator_to_s(Atom::Feed::Entry::Source::Generator)
      assert_atom_generator_to_s(Atom::Entry::Source::Generator)
    end

    def test_atom_icon
      assert_atom_icon_to_s(Atom::Feed::Icon)
      assert_atom_icon_to_s(Atom::Feed::Entry::Source::Icon)
      assert_atom_icon_to_s(Atom::Entry::Source::Icon)
    end

    def test_atom_id
      assert_atom_id_to_s(Atom::Feed::Id)
      assert_atom_id_to_s(Atom::Feed::Entry::Id)
      assert_atom_id_to_s(Atom::Entry::Id)
      assert_atom_id_to_s(Atom::Feed::Entry::Source::Id)
      assert_atom_id_to_s(Atom::Entry::Source::Id)
    end

    def test_atom_link
      assert_atom_link_to_s(Atom::Feed::Link)
      assert_atom_link_to_s(Atom::Feed::Entry::Link)
      assert_atom_link_to_s(Atom::Entry::Link)
      assert_atom_link_to_s(Atom::Feed::Entry::Source::Link)
      assert_atom_link_to_s(Atom::Entry::Source::Link)
    end

    def test_atom_logo
      assert_atom_logo_to_s(Atom::Feed::Logo)
      assert_atom_logo_to_s(Atom::Feed::Entry::Source::Logo)
      assert_atom_logo_to_s(Atom::Entry::Source::Logo)
    end

    def test_atom_rights
      assert_atom_text_construct_to_s(Atom::Feed::Rights)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Rights)
      assert_atom_text_construct_to_s(Atom::Entry::Rights)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Source::Rights)
      assert_atom_text_construct_to_s(Atom::Entry::Source::Rights)
    end

    def test_atom_subtitle
      assert_atom_text_construct_to_s(Atom::Feed::Subtitle)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Source::Subtitle)
      assert_atom_text_construct_to_s(Atom::Entry::Source::Subtitle)
    end

    def test_atom_title
      assert_atom_text_construct_to_s(Atom::Feed::Title)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Title)
      assert_atom_text_construct_to_s(Atom::Entry::Title)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Source::Title)
      assert_atom_text_construct_to_s(Atom::Entry::Source::Title)
    end

    def test_atom_updated
      assert_atom_date_construct_to_s(Atom::Feed::Updated)
      assert_atom_date_construct_to_s(Atom::Feed::Entry::Updated)
      assert_atom_date_construct_to_s(Atom::Entry::Updated)
      assert_atom_date_construct_to_s(Atom::Feed::Entry::Source::Updated)
      assert_atom_date_construct_to_s(Atom::Entry::Source::Updated)
    end

    def test_atom_content
      assert_atom_content_to_s(Atom::Feed::Entry::Content)
      assert_atom_content_to_s(Atom::Entry::Content)
    end

    def test_atom_published
      assert_atom_date_construct_to_s(Atom::Feed::Entry::Published)
      assert_atom_date_construct_to_s(Atom::Entry::Published)
    end

    def test_atom_summary
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Summary)
      assert_atom_text_construct_to_s(Atom::Entry::Summary)
    end


    def test_to_xml(with_convenience_way=true)
      atom = RSS::Parser.parse(make_feed)
      assert_equal(atom.to_s, atom.to_xml)
      assert_equal(atom.to_s, atom.to_xml("atom"))
      assert_equal(atom.to_s, atom.to_xml("atom1.0"))
      assert_equal(atom.to_s, atom.to_xml("atom1.0:feed"))
      assert_equal(atom.to_s, atom.to_xml("atom:feed"))

      rss09_xml = atom.to_xml("0.91") do |maker|
        maker.channel.language = "en-us"
        maker.channel.link = "http://example.com/"
        if with_convenience_way
          maker.channel.description = atom.title.content
        else
          maker.channel.description {|d| d.content = atom.title.content}
        end

        maker.image.url = "http://example.com/logo.png"
        maker.image.title = "Logo"
      end
      rss09 = RSS::Parser.parse(rss09_xml)
      assert_equal(["rss", "0.91", nil], rss09.feed_info)

      rss20_xml = atom.to_xml("2.0") do |maker|
        maker.channel.link = "http://example.com/"
        if with_convenience_way
          maker.channel.description = atom.title.content
        else
          maker.channel.description {|d| d.content = atom.title.content}
        end
      end
      rss20 = RSS::Parser.parse(rss20_xml)
      assert_equal("2.0", rss20.rss_version)
      assert_equal(["rss", "2.0", nil], rss20.feed_info)
    end

    def test_to_xml_with_new_api_since_018
      test_to_xml(false)
    end

    private
    def setup_entry(entry)
      _wrap_assertion do
        assert_equal("", entry.to_s)

        author = entry.class::Author.new
        name = entry.class::Author::Name.new
        name.content = "an author"
        author.name = name
        assert_not_equal("", author.to_s)
        entry.authors << author
        assert_equal("", entry.to_s)

        id = entry.class::Id.new
        id.content = "http://example.com/atom.xml"
        assert_not_equal("", id.to_s)
        entry.id = id
        assert_equal("", entry.to_s)

        title = entry.class::Title.new
        title.content = "a title"
        assert_not_equal("", title.to_s)
        entry.title = title
        assert_equal("", entry.to_s)

        updated = entry.class::Updated.new
        updated.content = Time.now
        assert_not_equal("", updated.to_s)
        entry.updated = updated
        assert_not_equal("", entry.to_s)
      end
    end


    def assert_atom_person_to_s(target_class)
      _wrap_assertion do
        name = "A person"
        uri = "http://example.com/person/"
        email = "person@example.com"

        target = target_class.new
        assert_equal("", target.to_s)

        target = target_class.new
        person_name = target_class::Name.new
        person_name.content = name
        target.name = person_name
        xml_target = REXML::Document.new(target.to_s).root
        assert_equal(["name"], xml_target.elements.collect {|e| e.name})
        assert_equal([name], xml_target.elements.collect {|e| e.text})

        person_uri = target_class::Uri.new
        person_uri.content = uri
        target.uri = person_uri
        xml_target = REXML::Document.new(target.to_s).root
        assert_equal(["name", "uri"], xml_target.elements.collect {|e| e.name})
        assert_equal([name, uri], xml_target.elements.collect {|e| e.text})

        person_email = target_class::Email.new
        person_email.content = email
        target.email = person_email
        xml_target = REXML::Document.new(target.to_s).root
        assert_equal(["name", "uri", "email"],
                     xml_target.elements.collect {|e| e.name})
        assert_equal([name, uri, email],
                     xml_target.elements.collect {|e| e.text})
      end
    end

    def assert_atom_category_to_s(target_class)
      _wrap_assertion do
        term = "music"
        scheme = "http://example.com/music"
        label = "Music"

        category = target_class.new
        assert_equal("", category.to_s)

        category = target_class.new
        category.scheme = scheme
        assert_equal("", category.to_s)

        category = target_class.new
        category.label = label
        assert_equal("", category.to_s)

        category = target_class.new
        category.scheme = scheme
        category.label = label
        assert_equal("", category.to_s)

        category = target_class.new
        category.term = term
        xml = REXML::Document.new(category.to_s).root
        assert_rexml_element([], {"term" => term}, nil, xml)

        category = target_class.new
        category.term = term
        category.scheme = scheme
        xml = REXML::Document.new(category.to_s).root
        assert_rexml_element([], {"term" => term, "scheme" => scheme}, nil, xml)

        category = target_class.new
        category.term = term
        category.label = label
        xml = REXML::Document.new(category.to_s).root
        assert_rexml_element([], {"term" => term, "label" => label}, nil, xml)

        category = target_class.new
        category.term = term
        category.scheme = scheme
        category.label = label
        xml = REXML::Document.new(category.to_s).root
        attrs = {"term" => term, "scheme" => scheme, "label" => label}
        assert_rexml_element([], attrs, nil, xml)
      end
    end

    def assert_atom_generator_to_s(target_class)
      _wrap_assertion do
        content = "Feed generator"
        uri = "http://example.com/generator"
        version = "0.0.1"

        generator = target_class.new
        assert_equal("", generator.to_s)

        generator = target_class.new
        generator.uri = uri
        assert_equal("", generator.to_s)

        generator = target_class.new
        generator.version = version
        assert_equal("", generator.to_s)

        generator = target_class.new
        generator.uri = uri
        generator.version = version
        assert_equal("", generator.to_s)

        generator = target_class.new
        generator.content = content
        xml = REXML::Document.new(generator.to_s).root
        assert_rexml_element([], {}, content, xml)

        generator = target_class.new
        generator.content = content
        generator.uri = uri
        xml = REXML::Document.new(generator.to_s).root
        assert_rexml_element([], {"uri" => uri}, content, xml)

        generator = target_class.new
        generator.content = content
        generator.version = version
        xml = REXML::Document.new(generator.to_s).root
        assert_rexml_element([], {"version" => version}, content, xml)

        generator = target_class.new
        generator.content = content
        generator.uri = uri
        generator.version = version
        xml = REXML::Document.new(generator.to_s).root
        assert_rexml_element([], {"uri" => uri, "version" => version},
                             content, xml)
      end
    end

    def assert_atom_icon_to_s(target_class)
      _wrap_assertion do
        content = "http://example.com/icon.png"

        icon = target_class.new
        assert_equal("", icon.to_s)

        icon = target_class.new
        icon.content = content
        xml = REXML::Document.new(icon.to_s).root
        assert_rexml_element([], {}, content, xml)
      end
    end

    def assert_atom_id_to_s(target_class)
      _wrap_assertion do
        content = "http://example.com/1"

        id = target_class.new
        assert_equal("", id.to_s)

        id = target_class.new
        id.content = content
        xml = REXML::Document.new(id.to_s).root
        assert_rexml_element([], {}, content, xml)
      end
    end

    def assert_atom_link_to_s(target_class)
      _wrap_assertion do
        href = "http://example.com/atom.xml"
        optvs = {
          'rel' => "self",
          'type' => "application/atom+xml",
          'hreflang' => "ja",
          'title' => "Atom Feed",
          'length' => "801",
        }

        link = target_class.new
        assert_equal("", link.to_s)

        link = target_class.new
        link.href = href
        xml = REXML::Document.new(link.to_s).root
        assert_rexml_element([], {"href" => href}, nil, xml)

        optional_arguments = %w(rel type hreflang title length)
        optional_arguments.each do |name|
          rest = optional_arguments.reject {|x| x == name}

          link = target_class.new
          link.__send__("#{name}=", optvs[name])
          assert_equal("", link.to_s)

          rest.each do |n|
            link.__send__("#{n}=", optvs[n])
            assert_equal("", link.to_s)
          end

          link = target_class.new
          link.href = href
          link.__send__("#{name}=", optvs[name])
          attrs = [["href", href], [name, optvs[name]]]
          xml = REXML::Document.new(link.to_s).root
          assert_rexml_element([], attrs, nil, xml)

          rest.each do |n|
            link.__send__("#{n}=", optvs[n])
            attrs << [n, optvs[n]]
            xml = REXML::Document.new(link.to_s).root
            assert_rexml_element([], attrs, nil, xml)
          end
        end
      end
    end

    def assert_atom_logo_to_s(target_class)
      _wrap_assertion do
        content = "http://example.com/logo.png"

        logo = target_class.new
        assert_equal("", logo.to_s)

        logo = target_class.new
        logo.content = content
        xml = REXML::Document.new(logo.to_s).root
        assert_rexml_element([], {}, content, xml)
      end
    end

    def assert_atom_text_construct_to_s(target_class)
      _wrap_assertion do
        text_content = "plain text"
        html_content = "<em>#{text_content}</em>"
        xhtml_uri = "http://www.w3.org/1999/xhtml"
        xhtml_em = RSS::XML::Element.new("em", nil, xhtml_uri, {}, text_content)
        xhtml_content = RSS::XML::Element.new("div", nil, xhtml_uri,
                                              {"xmlns" => xhtml_uri},
                                              [xhtml_em])

        text = target_class.new
        assert_equal("", text.to_s)

        text = target_class.new
        text.type = "text"
        assert_equal("", text.to_s)

        text = target_class.new
        text.content = text_content
        xml = REXML::Document.new(text.to_s).root
        assert_rexml_element([], {}, text_content, xml)

        text = target_class.new
        text.type = "text"
        text.content = text_content
        xml = REXML::Document.new(text.to_s).root
        assert_rexml_element([], {"type" => "text"}, text_content, xml)

        text = target_class.new
        text.type = "html"
        text.content = html_content
        xml = REXML::Document.new(text.to_s).root
        assert_rexml_element([], {"type" => "html"}, html_content, xml)

        text = target_class.new
        text.type = "xhtml"
        text.content = xhtml_content
        assert_equal("", text.to_s)

        text = target_class.new
        text.type = "xhtml"
        text.__send__(target_class.xml_setter, xhtml_content)
        xml = REXML::Document.new(text.to_s).root
        assert_rexml_element([[xhtml_uri, "div"]], {"type" => "xhtml"},
                             nil, xml)
        assert_rexml_element([[xhtml_uri, "em"]], nil, nil, xml.elements[1])
        assert_rexml_element([], {}, text_content, xml.elements[1].elements[1])

        text = target_class.new
        text.type = "xhtml"
        text.__send__(target_class.xml_setter, xhtml_em)
        xml = REXML::Document.new(text.to_s).root
        assert_rexml_element([[xhtml_uri, "div"]], {"type" => "xhtml"},
                             nil, xml)
        assert_rexml_element([[xhtml_uri, "em"]], nil, nil, xml.elements[1])
        assert_rexml_element([], {}, text_content, xml.elements[1].elements[1])
      end
    end

    def assert_atom_date_construct_to_s(target_class)
      _wrap_assertion do
        date = target_class.new
        assert_equal("", date.to_s)

        [
         "2003-12-13T18:30:02Z",
         "2003-12-13T18:30:02.25Z",
         "2003-12-13T18:30:02+01:00",
         "2003-12-13T18:30:02.25+01:00",
        ].each do |content|
          date = target_class.new
          date.content = content
          xml = REXML::Document.new(date.to_s).root
          assert_rexml_element([], {}, content, xml, :time)

          date = target_class.new
          date.content = Time.parse(content)
          xml = REXML::Document.new(date.to_s).root
          assert_rexml_element([], {}, content, xml, :time)
        end
      end
    end

    def assert_atom_content_to_s(target_class)
      _wrap_assertion do
        assert_atom_text_construct_to_s(target_class)
        assert_atom_content_inline_other_xml_to_s(target_class)
        assert_atom_content_inline_other_text_to_s(target_class)
        assert_atom_content_inline_other_base64_to_s(target_class)
        assert_atom_content_out_of_line_to_s(target_class)
      end
    end

    def assert_atom_content_inline_other_xml_to_s(target_class)
      _wrap_assertion do
        content = target_class.new
        content.type = "text/xml"
        assert_equal("", content.to_s)

        content = target_class.new
        content.type = "text/xml"
        content.xml = RSS::XML::Element.new("em")
        xml = REXML::Document.new(content.to_s).root
        assert_rexml_element([["", "em"]], {"type" => "text/xml"}, nil, xml)
      end
    end

    def assert_atom_content_inline_other_text_to_s(target_class)
      _wrap_assertion do
        content = target_class.new
        content.type = "text/plain"
        assert_equal("", content.to_s)

        content = target_class.new
        content.type = "text/plain"
        content.xml = RSS::XML::Element.new("em")
        assert_equal("", content.to_s)

        content = target_class.new
        content.type = "text/plain"
        content.content = "content"
        xml = REXML::Document.new(content.to_s).root
        assert_rexml_element([], {"type" => "text/plain"}, "content", xml)
      end
    end

    def assert_atom_content_inline_other_base64_to_s(target_class)
      _wrap_assertion do
        type = "image/png"
        png_file = File.join(File.dirname(__FILE__), "dot.png")
        original_content = File.open(png_file, "rb") do |file|
          file.read.force_encoding("binary")
        end

        content = target_class.new
        content.type = type
        content.content = original_content
        xml = REXML::Document.new(content.to_s).root
        assert_rexml_element([], {"type" => type},
                             [original_content].pack("m").delete("\n"),
                             xml)
      end
    end

    def assert_atom_content_out_of_line_to_s(target_class)
      _wrap_assertion do
        type = "application/zip"
        src = "http://example.com/xxx.zip"

        content = target_class.new
        assert(!content.out_of_line?)
        content.src = src
        assert(content.out_of_line?)
        xml = REXML::Document.new(content.to_s).root
        assert_rexml_element([], {"src" => src}, nil, xml)

        content = target_class.new
        assert(!content.out_of_line?)
        content.type = type
        assert(!content.out_of_line?)
        content.src = src
        assert(content.out_of_line?)
        xml = REXML::Document.new(content.to_s).root
        assert_rexml_element([], {"type" => type, "src" => src}, nil, xml)
      end
    end
  end
end
