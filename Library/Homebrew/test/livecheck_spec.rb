# frozen_string_literal: true

require "formula"
require "livecheck"

RSpec.describe Livecheck do
  let(:f) do
    formula do
      homepage "https://brew.sh"
      url "https://brew.sh/test-0.0.1.tgz"
      head "https://github.com/Homebrew/brew.git"
    end
  end
  let(:livecheck_f) { described_class.new(f.class) }

  let(:c) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "test" do
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"
      end
    RUBY
  end
  let(:livecheck_c) { described_class.new(c) }

  let(:post_hash) do
    {
      "empty"   => "",
      "boolean" => "true",
      "number"  => "1",
      "string"  => "a + b = c",
    }
  end

  describe "#formula" do
    it "returns nil if not set" do
      expect(livecheck_f.formula).to be_nil
    end

    it "returns the String if set" do
      livecheck_f.formula("other-formula")
      expect(livecheck_f.formula).to eq("other-formula")
    end

    it "raises a TypeError if the argument isn't a String" do
      expect do
        livecheck_f.formula(123)
      end.to raise_error TypeError
    end
  end

  describe "#cask" do
    it "returns nil if not set" do
      expect(livecheck_c.cask).to be_nil
    end

    it "returns the String if set" do
      livecheck_c.cask("other-cask")
      expect(livecheck_c.cask).to eq("other-cask")
    end
  end

  describe "#regex" do
    it "returns nil if not set" do
      expect(livecheck_f.regex).to be_nil
    end

    it "returns the Regexp if set" do
      livecheck_f.regex(/foo/)
      expect(livecheck_f.regex).to eq(/foo/)
    end
  end

  describe "#skip" do
    it "sets @skip to true when no argument is provided" do
      expect(livecheck_f.skip).to be true
      expect(livecheck_f.instance_variable_get(:@skip)).to be true
      expect(livecheck_f.instance_variable_get(:@skip_msg)).to be_nil
    end

    it "sets @skip to true and @skip_msg to the provided String" do
      expect(livecheck_f.skip("foo")).to be true
      expect(livecheck_f.instance_variable_get(:@skip)).to be true
      expect(livecheck_f.instance_variable_get(:@skip_msg)).to eq("foo")
    end
  end

  describe "#skip?" do
    it "returns the value of @skip" do
      expect(livecheck_f.skip?).to be false

      livecheck_f.skip
      expect(livecheck_f.skip?).to be true
    end
  end

  describe "#strategy" do
    block = proc { |page, regex| page.scan(regex).map { |match| match[0].tr("_", ".") } }

    it "returns nil if not set" do
      expect(livecheck_f.strategy).to be_nil
      expect(livecheck_f.strategy_block).to be_nil
    end

    it "returns the Symbol if set" do
      livecheck_f.strategy(:page_match)
      expect(livecheck_f.strategy).to eq(:page_match)
      expect(livecheck_f.strategy_block).to be_nil
    end

    it "sets `strategy_block` when provided" do
      livecheck_f.strategy(:page_match, &block)
      expect(livecheck_f.strategy).to eq(:page_match)
      expect(livecheck_f.strategy_block).to eq(block)
    end
  end

  describe "#throttle" do
    it "returns nil if not set" do
      expect(livecheck_f.throttle).to be_nil
    end

    it "returns the Integer if set" do
      livecheck_f.throttle(10)
      expect(livecheck_f.throttle).to eq(10)
    end
  end

  describe "#url" do
    let(:url_string) { "https://brew.sh" }

    it "returns nil if not set" do
      expect(livecheck_f.url).to be_nil
    end

    it "returns a string when set to a string" do
      livecheck_f.url(url_string)
      expect(livecheck_f.url).to eq(url_string)
    end

    it "returns the URL symbol if valid" do
      livecheck_f.url(:head)
      expect(livecheck_f.url).to eq(:head)

      livecheck_f.url(:homepage)
      expect(livecheck_f.url).to eq(:homepage)

      livecheck_f.url(:stable)
      expect(livecheck_f.url).to eq(:stable)

      livecheck_c.url(:url)
      expect(livecheck_c.url).to eq(:url)
    end

    it "sets `url` options when provided" do
      # This test makes sure that we can set multiple options at once and
      # options from subsequent `url` calls are merged with existing values
      # (i.e. existing values aren't reset to `nil`). [We only call `url` once
      # in a `livecheck` block but this should technically work due to how it's
      # implemented.]
      livecheck_f.url(url_string, homebrew_curl: true, post_form: post_hash)
      livecheck_f.url(url_string, post_json: post_hash)
      expect(livecheck_f.options.homebrew_curl).to be(true)
      expect(livecheck_f.options.post_form).to eq(post_hash)
      expect(livecheck_f.options.post_json).to eq(post_hash)
    end

    it "raises an ArgumentError if the argument isn't a valid Symbol" do
      expect do
        livecheck_f.url(:not_a_valid_symbol)
      end.to raise_error ArgumentError
    end

    it "raises an ArgumentError if both `post_form` and `post_json` arguments are provided" do
      expect do
        livecheck_f.url(:stable, post_form: post_hash, post_json: post_hash)
      end.to raise_error ArgumentError
    end
  end

  describe "#to_hash" do
    it "returns a Hash of all instance variables" do
      expect(livecheck_f.to_hash).to eq(
        {
          "options"  => Homebrew::Livecheck::Options.new.to_hash,
          "cask"     => nil,
          "formula"  => nil,
          "regex"    => nil,
          "skip"     => false,
          "skip_msg" => nil,
          "strategy" => nil,
          "throttle" => nil,
          "url"      => nil,
        },
      )
    end
  end
end
