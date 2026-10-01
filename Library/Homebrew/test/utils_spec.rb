# typed: true
# frozen_string_literal: true

require "timeout"
require "utils"

RSpec.describe Utils do
  describe ".fully_qualified_name" do
    [
      [Formula, "homebrew/core", "foo", "homebrew/core/foo"],
      [Cask::Cask, "homebrew/cask", "foo", "homebrew/cask/foo"],
      [Formula, "thirdparty/tap", "thirdparty/tap/foo", "thirdparty/tap/foo"],
      [Cask::Cask, "thirdparty/tap", "thirdparty/tap/foo", "thirdparty/tap/foo"],
      [Formula, nil, "foo", "foo"],
      [Cask::Cask, nil, "foo", "foo"],
    ].each do |klass, tap_name, full_name, expected|
      it "qualifies #{klass} from #{tap_name || "no tap"}" do
        T.bind(self, RSpec::Core::ExampleGroup)

        package = instance_double(klass, full_name:, tap: tap_name ? Tap.fetch(tap_name) : nil)

        expect(described_class.fully_qualified_name(package)).to eq(expected)
      end
    end
  end

  describe ".parallel_map" do
    it "runs all blocks concurrently" do
      # A barrier no block passes until every block has started: this
      # deadlocks (and times out) if the blocks run serially.
      mutex = Mutex.new
      condvar = ConditionVariable.new
      started = 0
      results = Timeout.timeout(5) do
        described_class.parallel_map([1, 2, 3]) do |i|
          mutex.synchronize do
            started += 1
            condvar.broadcast
            condvar.wait(mutex) while started < 3
          end
          i * 10
        end
      end
      expect(results).to eq [10, 20, 30]
    end

    it "returns results in input order, not completion order" do
      expect(described_class.parallel_map([3, 1, 2]) do |i|
        sleep(0.05 - (i * 0.01))
        i * 10
      end).to eq [30, 10, 20]
    end

    it "re-raises an exception from a block" do
      expect { described_class.parallel_map([1]) { raise "boom" } }.to raise_error("boom")
    end
  end

  describe ".deconstantize" do
    it "removes the rightmost segment from the constant expression in the string" do
      expect(described_class.deconstantize("Net::HTTP")).to eq("Net")
      expect(described_class.deconstantize("::Net::HTTP")).to eq("::Net")
      expect(described_class.deconstantize("String")).to eq("")
      expect(described_class.deconstantize("::String")).to eq("")
    end

    it "returns an empty string if the namespace is empty" do
      expect(described_class.deconstantize("")).to eq("")
      expect(described_class.deconstantize("::")).to eq("")
    end
  end

  describe ".demodulize" do
    it "removes the module part from the expression in the string" do
      expect(described_class.demodulize("Foo::Bar")).to eq("Bar")
    end

    it "returns the string if it does not contain a module expression" do
      expect(described_class.demodulize("FooBar")).to eq("FooBar")
    end

    it "returns an empty string if the namespace is empty" do
      expect(described_class.demodulize("")).to eq("")
      expect(described_class.demodulize("::")).to eq("")
    end

    it "raise an ArgumentError when passed nil" do
      expect { described_class.demodulize(nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".name_from_full_name" do
    it "returns the package name for a full name" do
      expect(described_class.name_from_full_name("homebrew/core/wget")).to eq("wget")
    end

    it "returns untapped names unchanged" do
      expect(described_class.name_from_full_name("wget")).to eq("wget")
    end

    it "does not treat taps as full names" do
      expect(described_class.name_from_full_name("homebrew/core")).to eq("homebrew/core")
    end
  end

  describe ".tap_from_full_name" do
    it "returns the tap for a full name" do
      expect(described_class.tap_from_full_name("homebrew/core/wget")).to eq("homebrew/core")
    end

    it "returns nil for untapped names" do
      expect(described_class.tap_from_full_name("wget")).to be_nil
    end

    it "returns nil for tap names" do
      expect(described_class.tap_from_full_name("homebrew/core")).to be_nil
    end
  end

  describe ".full_name?" do
    it "is true for a fully-qualified name" do
      expect(described_class.full_name?("homebrew/core/wget")).to be(true)
    end

    it "is false for an unqualified name" do
      expect(described_class.full_name?("wget")).to be(false)
    end

    it "is false for a tap name" do
      expect(described_class.full_name?("homebrew/core")).to be(false)
    end
  end

  specify ".parse_author!" do
    parse_error_msg = /Unable to parse name and email/

    expect(described_class.parse_author!("John Doe <john.doe@example.com>"))
      .to eq({ name: "John Doe", email: "john.doe@example.com" })
    expect { described_class.parse_author!("") }
      .to raise_error(parse_error_msg)
    expect { described_class.parse_author!("John Doe") }
      .to raise_error(parse_error_msg)
    expect { described_class.parse_author!("<john.doe@example.com>") }
      .to raise_error(parse_error_msg)
  end

  describe ".pluralize" do
    it "combines the stem with the default suffix based on the count" do
      expect(described_class.pluralize("foo", 0)).to eq("foos")
      expect(described_class.pluralize("foo", 1)).to eq("foo")
      expect(described_class.pluralize("foo", 2)).to eq("foos")
    end

    it "combines the stem with the singular suffix based on the count" do
      expect(described_class.pluralize("foo", 0, singular: "o")).to eq("foos")
      expect(described_class.pluralize("foo", 1, singular: "o")).to eq("fooo")
      expect(described_class.pluralize("foo", 2, singular: "o")).to eq("foos")
    end

    it "combines the stem with the plural suffix based on the count" do
      expect(described_class.pluralize("foo", 0, plural: "es")).to eq("fooes")
      expect(described_class.pluralize("foo", 1, plural: "es")).to eq("foo")
      expect(described_class.pluralize("foo", 2, plural: "es")).to eq("fooes")
    end

    it "combines the stem with the singular and plural suffix based on the count" do
      expect(described_class.pluralize("foo", 0, singular: "o", plural: "es")).to eq("fooes")
      expect(described_class.pluralize("foo", 1, singular: "o", plural: "es")).to eq("fooo")
      expect(described_class.pluralize("foo", 2, singular: "o", plural: "es")).to eq("fooes")
    end

    it "includes the count when requested" do
      expect(described_class.pluralize("foo", 0, include_count: true)).to eq("0 foos")
      expect(described_class.pluralize("foo", 1, include_count: true)).to eq("1 foo")
      expect(described_class.pluralize("foo", 2, include_count: true)).to eq("2 foos")
    end
  end

  describe ".exponential_backoff_sleep" do
    it "sleeps for 2**try seconds" do
      expect(described_class).to receive(:sleep).with(8)
      described_class.exponential_backoff_sleep(3)
    end

    it "sleeps for base**try seconds when a base is given" do
      expect(described_class).to receive(:sleep).with(27)
      described_class.exponential_backoff_sleep(3, base: 3)
    end

    it "yields the wait time before sleeping" do
      allow(described_class).to receive(:sleep)
      expect { |block| described_class.exponential_backoff_sleep(2, &block) }.to yield_with_args(4)
    end
  end

  describe ".underscore" do
    # commented out entries require acronyms inflections
    let(:words) do
      [
        ["API", "api"],
        ["APIController", "api_controller"],
        ["Nokogiri::HTML", "nokogiri/html"],
        # ["HTTPAPI", "http_api"],
        ["HTTP::Get", "http/get"],
        ["SSLError", "ssl_error"],
        # ["RESTful", "restful"],
        # ["RESTfulController", "restful_controller"],
        # ["Nested::RESTful", "nested/restful"],
        # ["IHeartW3C", "i_heart_w3c"],
        # ["PhDRequired", "phd_required"],
        # ["IRoRU", "i_ror_u"],
        # ["RESTfulHTTPAPI", "restful_http_api"],
        # ["HTTP::RESTful", "http/restful"],
        # ["HTTP::RESTfulAPI", "http/restful_api"],
        # ["APIRESTful", "api_restful"],
        ["Capistrano", "capistrano"],
        ["CapiController", "capi_controller"],
        ["HttpsApis", "https_apis"],
        ["Html5", "html5"],
        ["Restfully", "restfully"],
        ["RoRails", "ro_rails"],
      ]
    end

    it "converts strings to underscore case" do
      words.each do |camel, under|
        expect(described_class.underscore(camel)).to eq(under)
        expect(described_class.underscore(under)).to eq(under)
      end
    end
  end

  describe ".safe_filename?" do
    specify(:aggregate_failures) do
      expect(described_class.safe_filename?("formula-1.2.3.tar.gz")).to be(true)
      expect(described_class.safe_filename?("")).to be(true)

      expect(described_class.safe_filename?("etc/passwd")).to be(false)
      expect(described_class.safe_filename?("with\nnewline")).to be(false)
      expect(described_class.safe_filename?("with\0null")).to be(false)
      expect(described_class.safe_filename?("with\ttab")).to be(false)
    end

    # A basename is only unsafe here if it can escape its directory or smuggle a
    # control character; a relative traversal has to survive as a separate
    # component to matter, and the separator is what this rejects.
    specify "relative components are not separators", :aggregate_failures do
      expect(described_class.safe_filename?("..")).to be(true)
      expect(described_class.safe_filename?("../etc")).to be(false)
    end
  end

  describe ".safe_filename" do
    specify(:aggregate_failures) do
      expect(described_class.safe_filename("formula-1.2.3.tar.gz")).to eq("formula-1.2.3.tar.gz")

      expect(described_class.safe_filename("etc/passwd")).to eq("etcpasswd")
      expect(described_class.safe_filename("../../etc/passwd")).to eq("....etcpasswd")
      expect(described_class.safe_filename("with\nnewline")).to eq("withnewline")
      expect(described_class.safe_filename("with\0null")).to eq("withnull")
    end

    specify "the result is always safe", :aggregate_failures do
      ["a/b", "a\nb", "..", "", "\0"].each do |basename|
        expect(described_class.safe_filename?(described_class.safe_filename(basename))).to be(true)
      end
    end
  end

  describe ".convert_to_string_or_symbol" do
    specify(:aggregate_failures) do
      expect(described_class.convert_to_string_or_symbol(":example")).to eq(:example)
      expect(described_class.convert_to_string_or_symbol("example")).to eq("example")
    end
  end

  describe ".deep_stringify_symbols and .deep_unstringify_symbols" do
    it "converts all symbols in nested hashes and arrays", :aggregate_failures do
      with_symbols = {
        a: :symbol_a,
        b: {
          c: :symbol_c,
          d: ["string_d", :symbol_d],
        },
        e: [:symbol_e1, { f: :symbol_f }],
        g: "string_g",
        h: ":not_a_symbol",
        i: "\\also not a symbol", # literal: "\also not a symbol"
      }

      without_symbols = {
        ":a" => ":symbol_a",
        ":b" => {
          ":c" => ":symbol_c",
          ":d" => ["string_d", ":symbol_d"],
        },
        ":e" => [":symbol_e1", { ":f" => ":symbol_f" }],
        ":g" => "string_g",
        ":h" => "\\:not_a_symbol",       # literal: "\:not_a_symbol"
        ":i" => "\\\\also not a symbol", # literal: "\\also not a symbol"
      }

      expect(described_class.deep_stringify_symbols(with_symbols)).to eq(without_symbols)
      expect(described_class.deep_unstringify_symbols(without_symbols)).to eq(with_symbols)
    end
  end

  describe ".deep_compact_blank" do
    it "removes blank values from nested hashes and arrays" do
      input = {
        a: "",
        b: [],
        c: {},
        d: {
          e: "value",
          f: nil,
          g: {
            h: "",
            i: true,
            j: {
              k: nil,
              l: "",
            },
          },
          m: ["", nil],
        },
        n: [nil, "", 2, [], { o: nil }],
        p: false,
        q: 0,
        r: 0.0,
      }

      expected_output = {
        d: {
          e: "value",
          g: {
            i: true,
          },
        },
        n: [2],
      }

      expect(described_class.deep_compact_blank(input)).to eq(expected_output)
    end

    it "preserves false when compact_false is disabled" do
      input = { a: false, b: [false], c: { d: false } }

      expect(described_class.deep_compact_blank(input, compact_false: false)).to eq(input)
    end
  end
end
