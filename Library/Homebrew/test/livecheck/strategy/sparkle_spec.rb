# frozen_string_literal: true

require "livecheck/strategy"
require "bundle_version"

RSpec.describe Homebrew::Livecheck::Strategy::Sparkle do
  subject(:sparkle) { described_class }

  def create_appcast_xml(items_str = "")
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel>
          <title>Example Changelog</title>
          <link>#{appcast_url}</link>
          <description>Most recent changes with links to updates.</description>
          <language>en</language>
          #{items_str}
        </channel>
      </rss>
    EOS
  end

  let(:appcast_url) { "https://www.example.com/example/appcast.xml" }
  let(:non_http_url) { "ftp://brew.sh/" }

  # The `item_hashes` data is used to create test appcast XML and expected
  # `Sparkle::Item` objects.
  let(:item_hashes) do
    {
      # The 1.2.4 version is only used in tests as the basis for an item that
      # should be excluded (after modifications).
      v124: {
        title:                  "Version 1.2.4",
        release_notes_link:     "https://www.example.com/example/1.2.4.html",
        pub_date:               "Fri, 02 Jan 2021 01:23:45 +0000",
        url:                    "https://www.example.com/example/example-1.2.4.tar.gz",
        short_version:          "1.2.4",
        version:                "124",
        minimum_system_version: "10.10",
      },
      v123: {
        title:                  "Version 1.2.3",
        release_notes_link:     "https://www.example.com/example/1.2.3.html",
        pub_date:               "Fri, 01 Jan 2021 01:23:45 +0000",
        url:                    "https://www.example.com/example/example-1.2.3.tar.gz",
        short_version:          "1.2.3",
        version:                "123",
        minimum_system_version: "10.10",
      },
      v122: {
        title:                  "Version 1.2.2",
        release_notes_link:     "https://www.example.com/example/1.2.2.html",
        pub_date:               "Not a parseable date string",
        link:                   "https://www.example.com/example/example-1.2.2.tar.gz",
        short_version:          "1.2.2",
        version:                "122",
        minimum_system_version: "10.10",
      },
      v121: {
        title:                  "Version 1.2.1",
        release_notes_link:     "https://www.example.com/example/1.2.1.html",
        pub_date:               "Thu, 31 Dec 2020 01:23:45 +0000",
        os:                     "osx",
        url:                    "https://www.example.com/example/example-1.2.1.tar.gz",
        short_version:          "1.2.1",
        version:                "121",
        minimum_system_version: "10.10",
      },
      v120: {
        title:                  "Version 1.2.0",
        release_notes_link:     "https://www.example.com/example/1.2.0.html",
        pub_date:               "Wed, 30 Dec 2020 01:23:45 +0000",
        os:                     "macos",
        url:                    "https://www.example.com/example/example-1.2.0.tar.gz",
        short_version:          "1.2.0",
        version:                "120",
        minimum_system_version: "10.10",
      },
    }
  end

  let(:xml) do
    v123_item = <<~EOS
      <item>
        <title>#{item_hashes[:v123][:title]}</title>
        <sparkle:minimumSystemVersion>#{item_hashes[:v123][:minimum_system_version]}</sparkle:minimumSystemVersion>
        <sparkle:releaseNotesLink>#{item_hashes[:v123][:release_notes_link]}</sparkle:releaseNotesLink>
        <pubDate>#{item_hashes[:v123][:pub_date]}</pubDate>
        <enclosure url="#{item_hashes[:v123][:url]}" sparkle:shortVersionString="#{item_hashes[:v123][:short_version]}" sparkle:version="#{item_hashes[:v123][:version]}" length="12345678" type="application/octet-stream" sparkle:dsaSignature="ABCDEF+GHIJKLMNOPQRSTUVWXYZab/cdefghijklmnopqrst/uvwxyz1234567==" />
      </item>
    EOS

    v122_item = <<~EOS
      <item>
        <title>#{item_hashes[:v122][:title]}</title>
        <link>#{item_hashes[:v122][:link]}</link>
        <sparkle:minimumSystemVersion>#{item_hashes[:v122][:minimum_system_version]}</sparkle:minimumSystemVersion>
        <sparkle:releaseNotesLink>#{item_hashes[:v122][:release_notes_link]}</sparkle:releaseNotesLink>
        <pubDate>#{item_hashes[:v122][:pub_date]}</pubDate>
        <sparkle:version>#{item_hashes[:v122][:version]}</sparkle:version>
        <sparkle:shortVersionString>#{item_hashes[:v122][:short_version]}</sparkle:shortVersionString>
      </item>
    EOS

    v121_item_with_osx_os = <<~EOS
      <item>
        <title>#{item_hashes[:v121][:title]}</title>
        <sparkle:minimumSystemVersion>#{item_hashes[:v121][:minimum_system_version]}</sparkle:minimumSystemVersion>
        <sparkle:releaseNotesLink>#{item_hashes[:v121][:release_notes_link]}</sparkle:releaseNotesLink>
        <pubDate>#{item_hashes[:v121][:pub_date]}</pubDate>
        <enclosure os="#{item_hashes[:v121][:os]}" url="#{item_hashes[:v121][:url]}" sparkle:shortVersionString="#{item_hashes[:v121][:short_version]}" sparkle:version="#{item_hashes[:v121][:version]}" length="12345678" type="application/octet-stream" sparkle:dsaSignature="ABCDEF+GHIJKLMNOPQRSTUVWXYZab/cdefghijklmnopqrst/uvwxyz1234567==" />
      </item>
    EOS

    v120_item_with_macos_os = <<~EOS
      <item>
        <title>#{item_hashes[:v120][:title]}</title>
        <sparkle:minimumSystemVersion>#{item_hashes[:v120][:minimum_system_version]}</sparkle:minimumSystemVersion>
        <sparkle:releaseNotesLink>#{item_hashes[:v120][:release_notes_link]}</sparkle:releaseNotesLink>
        <pubDate>#{item_hashes[:v120][:pub_date]}</pubDate>
        <enclosure os="#{item_hashes[:v120][:os]}" url="#{item_hashes[:v120][:url]}" sparkle:shortVersionString="#{item_hashes[:v120][:short_version]}" sparkle:version="#{item_hashes[:v120][:version]}" length="12345678" type="application/octet-stream" sparkle:dsaSignature="ABCDEF+GHIJKLMNOPQRSTUVWXYZab/cdefghijklmnopqrst/uvwxyz1234567==" />
      </item>
    EOS

    # This main `appcast` data is intended as a relatively normal example.
    # As such, it also serves as a base for some other test data.
    appcast = create_appcast_xml <<~EOS
      #{v123_item}
      #{v122_item}
      #{v121_item_with_osx_os}
      #{v120_item_with_macos_os}
    EOS

    omitted_items = create_appcast_xml <<~EOS
      #{v123_item.sub(%r{<(enclosure[^>]+?)\s*?/>}, '<\1 os="not-osx-or-macos" />')}
      #{v123_item.sub(/(<sparkle:minimumSystemVersion>)[^<]+?</m, '\1100<')}
      <item>
      </item>
    EOS

    # Set the first item in a copy of `appcast` to a bad `minimumSystemVersion`
    # value, to test `MacOSVersion::Error` handling.
    bad_macos_version = appcast.sub(
      v123_item,
      v123_item.sub(
        /(<sparkle:minimumSystemVersion>)[^<]+?</m,
        '\1Not a macOS version<',
      ),
    )

    # Set the first item in a copy of `appcast` to the "beta" channel, to test
    # filtering items by channel using a `strategy` block.
    beta_channel_item = appcast.sub(
      v123_item,
      v123_item.sub(
        "</title>",
        "</title>\n<sparkle:channel>beta</sparkle:channel>",
      ),
    )

    no_versions_item = create_appcast_xml <<~EOS
      <item>
        <title>Version</title>
        <sparkle:minimumSystemVersion>#{item_hashes[:v123][:minimum_system_version]}</sparkle:minimumSystemVersion>
        <sparkle:releaseNotesLink>#{item_hashes[:v123][:release_notes_link]}</sparkle:releaseNotesLink>
        <pubDate>#{item_hashes[:v123][:pub_date]}</pubDate>
        <enclosure url="#{item_hashes[:v123][:url]}" length="12345678" type="application/octet-stream" sparkle:dsaSignature="ABCDEF+GHIJKLMNOPQRSTUVWXYZab/cdefghijklmnopqrst/uvwxyz1234567==" />
      </item>
    EOS

    no_items = create_appcast_xml

    undefined_namespace = appcast.sub(/\s*xmlns:sparkle="[^"]+"/, "")

    {
      appcast:,
      omitted_items:,
      bad_macos_version:,
      beta_channel_item:,
      no_versions_item:,
      no_items:,
      undefined_namespace:,
    }
  end

  let(:title_regex) { /Version\s+v?(\d+(?:\.\d+)+)\s*$/i }

  let(:items) do
    {
      v124: Homebrew::Livecheck::Strategy::Sparkle::Item.new(
        title:                  item_hashes[:v124][:title],
        release_notes_link:     item_hashes[:v124][:release_notes_link],
        pub_date:               Time.parse(item_hashes[:v124][:pub_date]),
        url:                    item_hashes[:v124][:url],
        bundle_version:         Homebrew::BundleVersion.new(
          item_hashes[:v124][:short_version],
          item_hashes[:v124][:version],
        ),
        minimum_system_version: MacOSVersion.new(item_hashes[:v124][:minimum_system_version]),
      ),
      v123: Homebrew::Livecheck::Strategy::Sparkle::Item.new(
        title:                  item_hashes[:v123][:title],
        release_notes_link:     item_hashes[:v123][:release_notes_link],
        pub_date:               Time.parse(item_hashes[:v123][:pub_date]),
        url:                    item_hashes[:v123][:url],
        bundle_version:         Homebrew::BundleVersion.new(
          item_hashes[:v123][:short_version],
          item_hashes[:v123][:version],
        ),
        minimum_system_version: MacOSVersion.new(item_hashes[:v123][:minimum_system_version]),
      ),
      v122: Homebrew::Livecheck::Strategy::Sparkle::Item.new(
        title:                  item_hashes[:v122][:title],
        link:                   item_hashes[:v122][:link],
        release_notes_link:     item_hashes[:v122][:release_notes_link],
        # `#items_from_content` falls back to a default `pub_date` when
        # one isn't provided or can't be successfully parsed.
        pub_date:               Time.new(0),
        url:                    item_hashes[:v122][:link],
        bundle_version:         Homebrew::BundleVersion.new(
          item_hashes[:v122][:short_version],
          item_hashes[:v122][:version],
        ),
        minimum_system_version: MacOSVersion.new(item_hashes[:v122][:minimum_system_version]),
      ),
      v121: Homebrew::Livecheck::Strategy::Sparkle::Item.new(
        title:                  item_hashes[:v121][:title],
        release_notes_link:     item_hashes[:v121][:release_notes_link],
        pub_date:               Time.parse(item_hashes[:v121][:pub_date]),
        os:                     item_hashes[:v121][:os],
        url:                    item_hashes[:v121][:url],
        bundle_version:         Homebrew::BundleVersion.new(
          item_hashes[:v121][:short_version],
          item_hashes[:v121][:version],
        ),
        minimum_system_version: MacOSVersion.new(item_hashes[:v121][:minimum_system_version]),
      ),
      v120: Homebrew::Livecheck::Strategy::Sparkle::Item.new(
        title:                  item_hashes[:v120][:title],
        release_notes_link:     item_hashes[:v120][:release_notes_link],
        pub_date:               Time.parse(item_hashes[:v120][:pub_date]),
        os:                     item_hashes[:v120][:os],
        url:                    item_hashes[:v120][:url],
        bundle_version:         Homebrew::BundleVersion.new(
          item_hashes[:v120][:short_version],
          item_hashes[:v120][:version],
        ),
        minimum_system_version: MacOSVersion.new(item_hashes[:v120][:minimum_system_version]),
      ),
    }
  end

  let(:item_arrays) do
    item_arrays = {
      appcast:        [
        items[:v123],
        items[:v122],
        items[:v121],
        items[:v120],
      ],
      appcast_sorted: [
        items[:v123],
        items[:v121],
        items[:v120],
        items[:v122],
      ],
    }

    bad_macos_version_item = items[:v123].clone
    bad_macos_version_item.minimum_system_version = nil
    item_arrays[:bad_macos_version] = [
      bad_macos_version_item,
      items[:v122],
      items[:v121],
      items[:v120],
    ]

    beta_channel_item = items[:v123].clone
    beta_channel_item.channel = "beta"
    item_arrays[:beta_channel_item] = [
      beta_channel_item,
      items[:v122],
      items[:v121],
      items[:v120],
    ]

    no_versions_item = items[:v123].clone
    no_versions_item.title = "Version"
    no_versions_item.bundle_version = nil
    item_arrays[:no_versions_item] = [no_versions_item]

    item_arrays
  end

  let(:versions) { [items[:v123].nice_version] }

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(sparkle.match?(appcast_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(sparkle.match?(non_http_url)).to be false
    end
  end

  describe "::items_from_content" do
    let(:items_from_appcast) { sparkle.items_from_content(xml[:appcast]) }

    it "returns nil if content is blank" do
      expect(sparkle.items_from_content("")).to eq([])
    end

    it "returns an array of Items when given XML data" do
      expect(items_from_appcast).to eq(item_arrays[:appcast])
      expect(items_from_appcast[0].title).to eq(item_hashes[:v123][:title])
      expect(items_from_appcast[0].pub_date).to eq(Time.parse(item_hashes[:v123][:pub_date]))
      expect(items_from_appcast[0].url).to eq(item_hashes[:v123][:url])
      expect(items_from_appcast[0].short_version).to eq(item_hashes[:v123][:short_version])
      expect(items_from_appcast[0].version).to eq(item_hashes[:v123][:version])

      expect(sparkle.items_from_content(xml[:bad_macos_version])).to eq(item_arrays[:bad_macos_version])
      expect(sparkle.items_from_content(xml[:beta_channel_item])).to eq(item_arrays[:beta_channel_item])
      expect(sparkle.items_from_content(xml[:no_versions_item])).to eq(item_arrays[:no_versions_item])
    end
  end

  describe "::filter_items" do
    let(:items_non_mac_os) do
      item = items[:v124].clone
      item.os = "not-osx-or-macos"
      item_arrays[:appcast] + [item]
    end

    let(:items_prerelease_minimum_system_version) do
      item = items[:v124].clone
      item.minimum_system_version = MacOSVersion.new("100")
      item_arrays[:appcast] + [item]
    end

    it "removes items with a non-mac OS" do
      expect(sparkle.filter_items(items_non_mac_os)).to eq(item_arrays[:appcast])
    end

    it "removes items with a prerelease minimumSystemVersion" do
      expect(sparkle.filter_items(items_prerelease_minimum_system_version)).to eq(item_arrays[:appcast])
    end
  end

  describe "::sort_items" do
    it "returns a sorted array of items" do
      expect(sparkle.sort_items(item_arrays[:appcast])).to eq(item_arrays[:appcast_sorted])
    end
  end

  # `#versions_from_content` sorts items by `pub_date` and `bundle_version`, so
  # these tests have to account for this behavior in the expected output.
  # For example, the version 122 item doesn't have a parseable `pub_date` and
  # the substituted default will cause it to be sorted last.
  describe "::versions_from_content" do
    let(:subbed_items) { item_arrays[:appcast_sorted].map { |item| item.nice_version.sub("1", "0") } }

    it "returns an array of version strings when given content" do
      expect(sparkle.versions_from_content(xml[:appcast])).to eq(versions)
      expect(sparkle.versions_from_content(xml[:omitted_items])).to eq([])
      expect(sparkle.versions_from_content(xml[:beta_channel_item])).to eq(versions)
      expect(sparkle.versions_from_content(xml[:no_versions_item])).to eq([])
      expect(sparkle.versions_from_content(xml[:undefined_namespace])).to eq(versions)
    end

    it "returns an empty array if no items are found" do
      expect(sparkle.versions_from_content(xml[:no_items])).to eq([])
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block
      expect(
        sparkle.versions_from_content(xml[:appcast]) do |item|
          item.nice_version&.sub("1", "0")
        end,
      ).to eq([subbed_items[0]])

      # Returning an array of strings from block
      expect(
        sparkle.versions_from_content(xml[:appcast]) do |items|
          items.map { |item| item.nice_version&.sub("1", "0") }
        end,
      ).to eq(subbed_items)

      expect(
        sparkle.versions_from_content(xml[:beta_channel_item]) do |items|
          items.find { |item| item.channel.nil? }&.nice_version
        end,
      ).to eq([items[:v121].nice_version])
    end

    it "returns an array of version strings when given content, a regex and a block" do
      # Returning a string from the block
      expect(
        sparkle.versions_from_content(xml[:appcast], title_regex) do |item, regex|
          item.title[regex, 1]
        end,
      ).to eq([item_hashes[:v123][:short_version]])

      expect(
        sparkle.versions_from_content(xml[:appcast], title_regex) do |items, regex|
          next if (item = items[0]).blank?

          match = item&.title&.match(regex)
          next if match.blank?

          "#{match[1]},#{item.version}"
        end,
      ).to eq(["#{item_hashes[:v123][:short_version]},#{item_hashes[:v123][:version]}"])

      # Returning an array of strings from the block
      expect(
        sparkle.versions_from_content(xml[:appcast], title_regex) do |item, regex|
          [item.title[regex, 1]]
        end,
      ).to eq([item_hashes[:v123][:short_version]])

      expect(
        sparkle.versions_from_content(xml[:appcast], &:short_version),
      ).to eq([item_hashes[:v123][:short_version]])

      expect(
        sparkle.versions_from_content(xml[:appcast], title_regex) do |items, regex|
          items.map { |item| item.title[regex, 1] }
        end,
      ).to eq(item_arrays[:appcast_sorted].map(&:short_version))
    end

    it "allows a nil return from a block" do
      expect(
        sparkle.versions_from_content(xml[:appcast]) do |item|
          _ = item # To appease `brew style` without modifying arg name
          next
        end,
      ).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect do
        sparkle.versions_from_content(xml[:appcast]) do |item|
          _ = item # To appease `brew style` without modifying arg name
          123
        end
      end.to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end

    it "errors if the first block argument uses an unhandled name" do
      expect { sparkle.versions_from_content(xml[:appcast]) { |something| something } }
        .to raise_error("First argument of Sparkle `strategy` block must be `item` or `items`")
    end
  end
end
