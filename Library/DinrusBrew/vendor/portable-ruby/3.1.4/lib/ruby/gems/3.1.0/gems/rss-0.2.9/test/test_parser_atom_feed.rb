# frozen_string_literal: false
require_relative "rss-testcase"

require "rss/atom"

module RSS
  class TestParserAtomFeed < TestCase
    def test_feed_validation
      assert_ns("", Atom::URI) do
        Parser.parse(<<-EOA)
<feed/>
EOA
      end

      assert_ns("", Atom::URI) do
        Parser.parse(<<-EOA)
<feed xmlns="hoge"/>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "id", "feed") do
<feed xmlns="#{Atom::URI}"/>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "title", "feed") do
<feed xmlns="#{Atom::URI}">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
</feed>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "updated", "feed") do
<feed xmlns="#{Atom::URI}">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <title>Example Feed</title>
</feed>
EOA
      end

      assert_parse(<<-EOA, :missing_tag, "author", "feed") do
<feed xmlns="#{Atom::URI}">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <title>Example Feed</title>
  <updated>2003-12-13T18:30:02Z</updated>
</feed>
EOA
      end

      assert_parse(<<-EOA, :nothing_raised) do
<feed xmlns="#{Atom::URI}">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <title>Example Feed</title>
  <updated>2003-12-13T18:30:02Z</updated>
  <author>
    <name>A person</name>
  </author>
</feed>
EOA
      end
    end

    def test_lang
      feed = RSS::Parser.parse(<<-EOA)
<feed xmlns="#{Atom::URI}" xml:lang="ja">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <title xml:lang="en">Example Feed</title>
  <updated>2003-12-13T18:30:02Z</updated>
  <author xml:lang="en">
    <name>A person</name>
  </author>
</feed>
EOA

      assert_equal("ja", feed.lang)
      assert_equal("ja", feed.id.lang)
      assert_equal("en", feed.title.lang)
      assert_equal("ja", feed.updated.lang)
      assert_equal("en", feed.author.lang)
      assert_equal("en", feed.author.name.lang)
    end

    def test_base
      feed = RSS::Parser.parse(<<-EOA)
<feed xmlns="#{Atom::URI}" xml:base="http://example.com/">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <title xml:lang="en">Example Feed</title>
  <updated>2003-12-13T18:30:02Z</updated>
  <generator uri="generator">Generator</generator>
  <link hreflang="ja" href="http://example.org/link1"/>
  <link hreflang="en" href="link2"/>
  <link hreflang="fr" xml:base="http://example.net/" href="link3"/>
  <author>
    <name>A person</name>
    <uri>person</uri>
  </author>
</feed>
EOA

      assert_equal("http://example.com/", feed.base)
      assert_equal("http://example.com/", feed.id.base)
      assert_equal("http://example.com/", feed.title.base)
      assert_equal("http://example.com/", feed.updated.base)
      assert_equal("http://example.com/", feed.generator.base)
      assert_equal("http://example.com/generator", feed.generator.uri)

      assert_equal("http://example.com/", feed.links[0].base)
      assert_equal("http://example.org/link1", feed.links[0].href)
      assert_equal("http://example.com/", feed.links[1].base)
      assert_equal("http://example.com/link2", feed.links[1].href)
      assert_equal("http://example.net/", feed.links[2].base)
      assert_equal("http://example.net/link3", feed.links[2].href)
      assert_equal("http://example.com/person", feed.author.uri.content)
    end

    def test_feed_author
      assert_atom_person("author", method(:make_feed)) do |feed|
        assert_equal(2, feed.authors.size)
        feed.authors[1]
      end
    end

    def test_entry_author
      generator = method(:make_feed_with_open_entry)
      assert_atom_person("author", generator) do |feed|
        assert_equal(1, feed.entries.size)
        assert_equal(1, feed.entry.authors.size)
        feed.entry.author
      end
    end

    def test_feed_category
      assert_atom_category(method(:make_feed)) do |feed|
        assert_equal(1, feed.categories.size)
        feed.category
      end
    end

    def test_entry_category
      assert_atom_category(method(:make_feed_with_open_entry)) do |feed|
        assert_equal(1, feed.entries.size)
        assert_equal(1, feed.entry.categories.size)
        feed.entry.category
      end
    end

    def test_entry_content
      assert_atom_content(method(:make_feed_with_open_entry)) do |feed|
        assert_equal(1, feed.entries.size)
        feed.entry.content
      end
    end

    def test_feed_contributor
      assert_atom_person("contributor", method(:make_feed)) do |feed|
        assert_equal(1, feed.contributors.size)
        feed.contributor
      end
    end

    def test_entry_contributor
      generator = method(:make_feed_with_open_entry)
      assert_atom_person("contributor", generator) do |feed|
        assert_equal(1, feed.entries.size)
        assert_equal(1, feed.entry.contributors.size)
        feed.entry.contributor
      end
    end

    def test_feed_generator
      assert_atom_generator(method(:make_feed)) do |feed|
        feed.generator
      end
    end

    def test_feed_icon
      assert_atom_icon(method(:make_feed)) do |feed|
        feed.icon
      end
    end

    def test_feed_id
      feed = RSS::Parser.parse(make_feed(''))
      assert_equal(FEED_ID, feed.id.content)
    end

    def test_entry_id
      feed = RSS::Parser.parse(make_feed(''))
      assert_equal(ENTRY_ID, feed.entry.id.content)
    end

    def test_feed_link
      assert_atom_link(method(:make_feed)) do |feed|
        assert_equal(1, feed.links.size)
        feed.link
      end
    end

    def test_entry_link
      assert_atom_link(method(:make_feed_with_open_entry)) do |feed|
        assert_equal(1, feed.entries.size)
        assert_equal(1, feed.entry.links.size)
        feed.entry.link
      end
    end

    def test_feed_logo
      assert_atom_logo(method(:make_feed)) do |feed|
        feed.logo
      end
    end

    def test_feed_rights
      assert_atom_text_construct("rights", method(:make_feed)) do |feed|
        feed.rights
      end
    end

    def test_entry_rights
      generator = method(:make_feed_with_open_entry)
      assert_atom_text_construct("rights", generator) do |feed|
        assert_equal(1, feed.entries.size)
        feed.entry.rights
      end
    end

    def test_entry_source
      assert_atom_source(method(:make_feed_with_open_entry_source)) do |feed|
        assert_equal(1, feed.entries.size)
        assert_not_nil(feed.entry.source)
        feed.entry.source
      end
    end

    def test_feed_subtitle
      assert_atom_text_construct("subtitle", method(:make_feed)) do |feed|
        feed.subtitle
      end
    end

    def test_feed_title
      feed = RSS::Parser.parse(make_feed(''))
      assert_equal(FEED_TITLE, feed.title.content)
    end

    def test_entry_title
      feed = RSS::Parser.parse(make_feed(''))
      assert_equal(ENTRY_TITLE, feed.entry.title.content)
    end

    def test_feed_updated
      feed = RSS::Parser.parse(make_feed(''))
      assert_equal(Time.parse(FEED_UPDATED), feed.updated.content)
    end

    def test_entry_updated
      feed = RSS::Parser.parse(make_feed(''))
      assert_equal(Time.parse(ENTRY_UPDATED), feed.entry.updated.content)
    end

    def test_entry_published
      generator = method(:make_feed_with_open_entry)
      assert_atom_date_construct("published", generator) do |feed|
        assert_equal(1, feed.entries.size)
        feed.entry.published
      end
    end

    def test_entry_summary
      generator = method(:make_feed_with_open_entry)
      assert_atom_text_construct("summary", generator) do |feed|
        assert_equal(1, feed.entries.size)
        feed.entry.summary
      end
    end
  end
end
