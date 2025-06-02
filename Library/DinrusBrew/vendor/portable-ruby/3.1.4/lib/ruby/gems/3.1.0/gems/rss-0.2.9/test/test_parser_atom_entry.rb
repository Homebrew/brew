# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/atom"

module RSS
  class TestParserAtom < TestCase
    def test_entry_validation
      assert_ns("", Atom::URI) do
        Parser.parse(<<-EOA)
<entry/>
EOA
      end

      assert_ns("", Atom::URI) do
        Parser.parse(<<-EOA)
<entry xmlns="hoge"/>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "id", "entry") do
<entry xmlns="#{Atom::URI}"/>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "title", "entry") do
<entry xmlns="#{Atom::URI}">
  <id>urn:uuid:506e336c-a26e-4457-917b-b89dca7ae746</id>
</entry>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "updated", "entry") do
<entry xmlns="#{Atom::URI}">
  <id>urn:uuid:506e336c-a26e-4457-917b-b89dca7ae746</id>
  <title>Example Entry</title>
</entry>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "author", "entry") do
<entry xmlns="#{Atom::URI}">
  <id>urn:uuid:506e336c-a26e-4457-917b-b89dca7ae746</id>
  <title>Example Entry</title>
  <updated>2003-10-10T18:30:02Z</updated>
</entry>
EOA
      end

      assert_parse(<<-EOA, :nothing_raised) do
<entry xmlns="#{Atom::URI}">
  <id>urn:uuid:506e336c-a26e-4457-917b-b89dca7ae746</id>
  <title>Example Entry</title>
  <updated>2003-10-10T18:30:02Z</updated>
  <author>
    <name>A person</name>
  </author>
</entry>
EOA
      end
    end

    def test_entry
      entry = RSS::Parser.parse(<<-EOA)
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://www.w3.org/2005/Atom">
  <author>
    <name>A person</name>
  </author>
  <title>Atom-Powered Robots Run Amok</title>
  <link href="http://example.org/2003/12/13/atom03"/>
  <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
  <updated>2003-12-13T18:30:02Z</updated>
  <summary>Some text.</summary>
</entry>
EOA
      assert_not_nil(entry)
      assert_equal("Atom-Powered Robots Run Amok", entry.title.content)
      assert_equal("http://example.org/2003/12/13/atom03", entry.link.href)
      assert_equal("urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a",
                   entry.id.content)
      assert_equal(Time.parse("2003-12-13T18:30:02Z"), entry.updated.content)
      assert_equal("Some text.", entry.summary.content)
    end

    def test_entry_author
      assert_atom_person("author", method(:make_entry_document)) do |entry|
        assert_equal(2, entry.authors.size)
        entry.authors.last
      end
    end

    def test_entry_category
      assert_atom_category(method(:make_entry_document)) do |entry|
        assert_equal(1, entry.categories.size)
        entry.category
      end
    end

    def test_entry_content_text
      assert_atom_content(method(:make_entry_document)) do |entry|
        entry.content
      end
    end

    def test_entry_contributor
      assert_atom_person("contributor", method(:make_entry_document)) do |entry|
        assert_equal(1, entry.contributors.size)
        entry.contributor
      end
    end

    def test_entry_id
      entry = RSS::Parser.parse(make_entry_document)
      assert_equal(ENTRY_ID, entry.id.content)
    end

    def test_entry_link
      assert_atom_link(method(:make_entry_document)) do |entry|
        assert_equal(1, entry.links.size)
        entry.link
      end
    end

    def test_published
      generator = method(:make_entry_document)
      assert_atom_date_construct("published", generator) do |entry|
        entry.published
      end
    end

    def test_entry_rights
      generator = method(:make_entry_document)
      assert_atom_text_construct("rights", generator) do |entry|
        entry.rights
      end
    end

    def test_entry_source
      generator = method(:make_entry_document_with_open_source)
      assert_atom_source(generator) do |entry|
        assert_not_nil(entry.source)
        entry.source
      end
    end

    def test_entry_summary
      generator = method(:make_entry_document)
      assert_atom_text_construct("summary", generator) do |entry|
        entry.summary
      end
    end

    def test_entry_title
      entry = RSS::Parser.parse(make_entry_document)
      assert_equal(ENTRY_TITLE, entry.title.content)
    end

    def test_entry_updated
      entry = RSS::Parser.parse(make_entry_document)
      assert_equal(Time.parse(ENTRY_UPDATED), entry.updated.content)
    end
  end
end
