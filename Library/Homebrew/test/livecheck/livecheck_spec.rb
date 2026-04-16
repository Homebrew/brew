# typed: false
# frozen_string_literal: true

require "livecheck/livecheck"

RSpec.describe Homebrew::Livecheck do
  subject(:livecheck) { described_class }

  let(:cask_url) { "https://brew.sh/test-0.0.1.dmg" }
  let(:head_url) { "https://github.com/Homebrew/brew.git" }
  let(:homepage_url) { "https://brew.sh" }
  let(:livecheck_url) { "https://formulae.brew.sh/api/formula/ruby.json" }
  let(:stable_url) { "https://brew.sh/test-0.0.1.tgz" }
  let(:resource_url) { "https://brew.sh/foo-1.0.tar.gz" }
  let(:brew_regex) { /href=.*?test[._-]v?(\d+(?:\.\d+)+)\.(?:t|dmg)/i }

  let(:f) do
    formula("test") do
      desc "Test formula"
      homepage "https://brew.sh"
      url "https://brew.sh/test-0.0.1.tgz"
      head "https://github.com/Homebrew/brew.git", branch: "main"

      livecheck do
        url "https://formulae.brew.sh/api/formula/ruby.json"
        regex(/"stable":"(\d+(?:\.\d+)+)"/i)
      end

      resource "foo" do
        url "https://brew.sh/foo-1.0.tar.gz"
        sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        livecheck do
          url "https://brew.sh/test/releases"
          regex(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
        end
      end
    end
  end

  let(:f_stable_url_only) do
    stable_url_s = stable_url

    formula("test_stable_url_only") do
      desc "Test formula with only a stable URL"
      url stable_url_s
    end
  end

  let(:r) { f.resources.first }

  let(:c) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "test" do
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"

        livecheck do
          url "https://formulae.brew.sh/api/formula/ruby.json"
          regex(/"stable":"(\d+(?:.\d+)+)"/i)
        end
      end
    RUBY
  end

  let(:c_no_checkable_urls) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "test_no_checkable_urls" do
        version "1.2.3"

        name "Test"
        desc "Test cask with no checkable URLs"
      end
    RUBY
  end

  describe "::livecheck_strategy_names" do
    context "when provided with a strategy class" do
      it "returns demodulized class name" do
        # We run this twice with the same argument to exercise the caching logic
        expect(livecheck.send(:livecheck_strategy_names, Homebrew::Livecheck::Strategy::PageMatch)).to eq("PageMatch")
        expect(livecheck.send(:livecheck_strategy_names, Homebrew::Livecheck::Strategy::PageMatch)).to eq("PageMatch")
      end
    end
  end

  describe "::livecheck_find_versions_parameters" do
    context "when provided with a strategy class" do
      it "returns demodulized class name" do
        page_match_parameters = T::Utils.signature_for_method(
          Homebrew::Livecheck::Strategy::PageMatch.method(:find_versions),
        ).parameters.map(&:second)

        # We run this twice with the same argument to exercise the caching logic
        expect(livecheck.send(:livecheck_find_versions_parameters, Homebrew::Livecheck::Strategy::PageMatch))
          .to eq(page_match_parameters)
        expect(livecheck.send(:livecheck_find_versions_parameters, Homebrew::Livecheck::Strategy::PageMatch))
          .to eq(page_match_parameters)
      end
    end
  end

  describe "::resolve_livecheck_reference" do
    context "when a formula/cask has a `livecheck` block without formula/cask methods" do
      it "returns [nil, []]" do
        expect(livecheck.resolve_livecheck_reference(f)).to eq([nil, []])
        expect(livecheck.resolve_livecheck_reference(c)).to eq([nil, []])
      end
    end
  end

  describe "::package_or_resource_name" do
    it "returns the name of a formula" do
      expect(livecheck.package_or_resource_name(f)).to eq("test")
    end

    it "returns the full name of a formula" do
      expect(livecheck.package_or_resource_name(f, full_name: true)).to eq("test")
    end

    it "returns the token of a cask" do
      expect(livecheck.package_or_resource_name(c)).to eq("test")
    end

    it "returns the full name of a cask" do
      expect(livecheck.package_or_resource_name(c, full_name: true)).to eq("test")
    end
  end

  describe "::status_hash" do
    it "returns a hash containing the livecheck status for a formula" do
      expect(livecheck.status_hash(f, "error", ["Unable to get versions"]))
        .to eq({
          formula:  "test",
          status:   "error",
          messages: ["Unable to get versions"],
          meta:     {
            livecheck_defined: true,
          },
        })
    end

    it "returns a hash containing the livecheck status for a resource" do
      expect(livecheck.status_hash(r, "error", ["Unable to get versions"]))
        .to eq({
          resource: "foo",
          status:   "error",
          messages: ["Unable to get versions"],
          meta:     {
            livecheck_defined: true,
          },
        })
    end
  end

  describe "::livecheck_url_to_string" do
    let(:f_livecheck_url) do
      homepage_url_s = homepage_url
      stable_url_s = stable_url
      head_url_s = head_url
      resource_url_s = resource_url

      formula("test_livecheck_url") do
        desc "Test Livecheck URL formula"
        homepage homepage_url_s
        url stable_url_s
        head head_url_s

        resource "foo" do
          url resource_url_s
          sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

          livecheck do
            url "https://brew.sh/test/releases"
            regex(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
          end
        end
      end
    end

    let(:r_livecheck_url) { f_livecheck_url.resources.first }

    let(:c_livecheck_url) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test_livecheck_url" do
          version "0.0.1,2"

          url "https://brew.sh/test-0.0.1.dmg"
          name "Test"
          desc "Test Livecheck URL cask"
          homepage "https://brew.sh"
        end
      RUBY
    end

    it "returns a URL string when given a livecheck_url string for a formula" do
      expect(livecheck.livecheck_url_to_string(livecheck_url, f_livecheck_url)).to eq(livecheck_url)
    end

    it "returns a URL string when given a livecheck_url string for a resource" do
      expect(livecheck.livecheck_url_to_string(livecheck_url, r_livecheck_url)).to eq(livecheck_url)
    end

    it "returns a URL symbol when given a valid livecheck_url symbol" do
      expect(livecheck.livecheck_url_to_string(:head, f_livecheck_url)).to eq(head_url)
      expect(livecheck.livecheck_url_to_string(:homepage, f_livecheck_url)).to eq(homepage_url)
      expect(livecheck.livecheck_url_to_string(:homepage, c_livecheck_url)).to eq(homepage_url)
      expect(livecheck.livecheck_url_to_string(:stable, f_livecheck_url)).to eq(stable_url)
      expect(livecheck.livecheck_url_to_string(:url, c_livecheck_url)).to eq(cask_url)
      expect(livecheck.livecheck_url_to_string(:url, r_livecheck_url)).to eq(resource_url)
    end

    it "returns nil when not given a string or valid symbol" do
      error_text = "`url :%<symbol>s` does not reference a checkable URL"

      # Invalid symbol in any context
      expect { livecheck.livecheck_url_to_string(:invalid_symbol, f_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :invalid_symbol))
      expect { livecheck.livecheck_url_to_string(:invalid_symbol, c_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :invalid_symbol))
      expect { livecheck.livecheck_url_to_string(:invalid_symbol, r_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :invalid_symbol))

      # Valid symbol in provided context but referenced URL is not present
      expect { livecheck.livecheck_url_to_string(:head, f_stable_url_only) }
        .to raise_error(ArgumentError, format(error_text, symbol: :head))
      expect { livecheck.livecheck_url_to_string(:homepage, f_stable_url_only) }
        .to raise_error(ArgumentError, format(error_text, symbol: :homepage))
      expect { livecheck.livecheck_url_to_string(:homepage, c_no_checkable_urls) }
        .to raise_error(ArgumentError, format(error_text, symbol: :homepage))
      expect { livecheck.livecheck_url_to_string(:url, c_no_checkable_urls) }
        .to raise_error(ArgumentError, format(error_text, symbol: :url))

      # Valid symbol but not in the provided context
      expect { livecheck.livecheck_url_to_string(:head, c_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :head))
      expect { livecheck.livecheck_url_to_string(:homepage, r_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :homepage))
      expect { livecheck.livecheck_url_to_string(:stable, c_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :stable))
      expect { livecheck.livecheck_url_to_string(:url, f_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :url))
    end
  end

  describe "::checkable_urls" do
    let(:resource_url) { "https://brew.sh/foo-1.0.tar.gz" }
    let(:f_duplicate_urls) do
      formula("test_duplicate_urls") do
        desc "Test formula with a duplicate URL"
        homepage "https://github.com/Homebrew/brew.git"
        url "https://brew.sh/test-0.0.1.tgz"
        head "https://github.com/Homebrew/brew.git", branch: "main"
      end
    end

    it "returns the list of URLs to check" do
      expect(livecheck.checkable_urls(f)).to eq([stable_url, head_url, homepage_url])
      expect(livecheck.checkable_urls(c)).to eq([cask_url, homepage_url])
      expect(livecheck.checkable_urls(r)).to eq([resource_url])
      expect(livecheck.checkable_urls(f_duplicate_urls)).to eq([stable_url, head_url])
      expect(livecheck.checkable_urls(f_stable_url_only)).to eq([stable_url])
      expect(livecheck.checkable_urls(c_no_checkable_urls)).to eq([])
    end
  end

  describe "::use_homebrew_curl?" do
    let(:example_url) { "https://www.example.com/test-0.0.1.tgz" }

    let(:f_homebrew_curl) do
      formula("test") do
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz", using: :homebrew_curl
        # head is deliberably omitted to exercise more of the method

        livecheck do
          url "https://formulae.brew.sh/api/formula/ruby.json"
          regex(/"stable":"(\d+(?:\.\d+)+)"/i)
        end
      end
    end

    let(:c_homebrew_curl) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test" do
          version "0.0.1,2"

          url "https://brew.sh/test-0.0.1.dmg", using: :homebrew_curl
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"

          livecheck do
            url "https://formulae.brew.sh/api/formula/ruby.json"
            regex(/"stable":"(\d+(?:.\d+)+)"/i)
          end
        end
      RUBY
    end

    it "returns `true` when URL matches a `using: :homebrew_curl` URL" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, livecheck_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, homepage_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, stable_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, livecheck_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, homepage_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, cask_url)).to be(true)
    end

    it "returns `false` if URL root domain differs from `using: :homebrew_curl` URLs" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, example_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, example_url)).to be(false)
    end

    it "returns `false` if a `using: homebrew_curl` URL is not present" do
      expect(livecheck.use_homebrew_curl?(f, livecheck_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(f, homepage_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(f, stable_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(f, example_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, livecheck_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, homepage_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, cask_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, example_url)).to be(false)
    end

    it "returns `false` if URL string does not contain a domain" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, "test")).to be(false)
    end
  end

  describe "::latest_version" do
    let(:f_throttle_rate) do
      formula("test_throttle_rate") do
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"

        livecheck do
          url :homepage
          regex(/href=.*?test[._-]v?(\d+(?:\.\d+)+)\.(?:t|dmg)/i)
          throttle 4
        end
      end
    end

    let(:f_throttle_days) do
      formula("test_throttle_days") do
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"

        livecheck do
          url :homepage
          regex(/href=.*?test[._-]v?(\d+(?:\.\d+)+)\.(?:t|dmg)/i)
          throttle days: 1
        end
      end
    end

    let(:f_throttle_rate_and_days) do
      formula("test_throttle_rate_and_days") do
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"

        livecheck do
          url :homepage
          regex(/href=.*?test[._-]v?(\d+(?:\.\d+)+)\.(?:t|dmg)/i)
          throttle 4, days: 1
        end
      end
    end

    let(:c_throttle_rate) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test_throttle_rate" do
          version "0.0.1"

          url "https://brew.sh/test-0.0.1.tgz"
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"

          livecheck do
            url :homepage
            regex(/href=.*?test[._-]v?(\\d+(?:\\.\\d+)+)\\.(?:t|dmg)/i)
            throttle 4
          end
        end
      RUBY
    end

    let(:c_throttle_days) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test_throttle_days" do
          version "0.0.1"

          url "https://brew.sh/test-0.0.1.tgz"
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"

          livecheck do
            url :homepage
            regex(/href=.*?test[._-]v?(\\d+(?:\\.\\d+)+)\\.(?:t|dmg)/i)
            throttle days: 1
          end
        end
      RUBY
    end

    let(:c_throttle_rate_and_days) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test_throttle_rate_and_days" do
          version "0.0.1"

          url "https://brew.sh/test-0.0.1.tgz"
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"

          livecheck do
            url :homepage
            regex(/href=.*?test[._-]v?(\\d+(?:\\.\\d+)+)\\.(?:t|dmg)/i)
            throttle 4, days: 1
          end
        end
      RUBY
    end

    let(:base_content) do
      <<~HTML
        <a href="test-0.0.1.tgz">0.0.1</a>
        <a href="test-0.0.2.tgz">0.0.2</a>
      HTML
    end

    it "sets `latest_throttled` to the highest throttled version" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({
        content: <<~HTML,
          <a href="test-0.0.3.tgz">0.0.3</a>
          <a href="test-0.0.4.tgz">0.0.4</a>
          <a href="test-0.0.5.tgz">0.0.5</a>
        HTML
      })

      f_result = nil
      expect { f_result = livecheck.latest_version(f_throttle_rate, debug: true, verbose: true) }
        .to output(
          a_string_matching(/Throttle: +4 versions/)
          .and(matching(/Matched Throttled Versions:\n0.0.4 => #<Version 0.0.4>/)),
        ).to_stdout
      expect(f_result[:latest]).to eq(Version.new("0.0.5"))
      expect(f_result[:latest_throttled]).to eq(Version.new("0.0.4"))

      c_result = nil
      expect { c_result = livecheck.latest_version(c_throttle_rate, debug: true) }
        .to output(
          a_string_matching(/Throttle: +4 versions/)
          .and(matching(/Matched Throttled Versions:\n0.0.4/)),
        ).to_stdout
      expect(c_result[:latest]).to eq(Version.new("0.0.5"))
      expect(c_result[:latest_throttled]).to eq(Version.new("0.0.4"))
    end

    it "does not set `latest_throttled` when there are no throttled versions and throttle interval has not elapsed" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: base_content })
      allow(livecheck).to receive(:throttle_interval_elapsed?).and_return(false)
      latest_version = Version.new("0.0.2")

      f_result = nil
      expect { f_result = livecheck.latest_version(f_throttle_rate_and_days, debug: true) }
        .to output(a_string_matching(/Throttle: +4 versions or 1 day/)).to_stdout
      expect(f_result[:latest]).to eq(latest_version)
      expect(f_result[:latest_throttled]).to be_nil

      c_result = livecheck.latest_version(c_throttle_rate_and_days)
      expect(c_result[:latest]).to eq(latest_version)
      expect(c_result[:latest_throttled]).to be_nil
    end

    it "sets `latest_throttled` to `latest` when there are no throttled versions and throttle interval has elapsed" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: base_content })
      allow(livecheck).to receive(:throttle_interval_elapsed?).and_return(true)
      latest_version = Version.new("0.0.2")

      f_result = nil
      expect { f_result = livecheck.latest_version(f_throttle_days, debug: true) }
        .to output(
          a_string_matching(/Throttle: +1 day/)
          .and(
            matching(/Matched Throttled Versions:\n#{Regexp.escape(latest_version)} \(throttle interval elapsed\)/),
          ),
        ).to_stdout
      expect(f_result[:latest]).to eq(latest_version)
      expect(f_result[:latest_throttled]).to eq(latest_version)

      f_result2 = livecheck.latest_version(f_throttle_rate_and_days)
      expect(f_result2[:latest]).to eq(latest_version)
      expect(f_result2[:latest_throttled]).to eq(latest_version)

      c_result = livecheck.latest_version(c_throttle_days)
      expect(c_result[:latest]).to eq(latest_version)
      expect(c_result[:latest_throttled]).to eq(latest_version)

      c_result2 = livecheck.latest_version(c_throttle_rate_and_days)
      expect(c_result2[:latest]).to eq(latest_version)
      expect(c_result2[:latest_throttled]).to eq(latest_version)
    end
  end

  describe "::throttle_interval_elapsed" do
    it "returns false if days is not positive" do
      expect(livecheck.send(:throttle_interval_elapsed?, f, 0)).to be(false)
      expect(livecheck.send(:throttle_interval_elapsed?, f, -1)).to be(false)
    end

    it "returns false if last_updated_timestamp can't be determined" do
      allow(livecheck).to receive(:formula_or_cask_last_updated_timestamp).and_return(nil)

      expect(livecheck.send(:throttle_interval_elapsed?, f, 4)).to be(false)
    end

    it "returns false if throttle interval has not elapsed" do
      allow(livecheck).to receive(:formula_or_cask_last_updated_timestamp).and_return(Time.now.to_i)

      expect(livecheck.send(:throttle_interval_elapsed?, f, 4)).to be(false)
    end

    it "returns true if throttle interval has elapsed" do
      allow(livecheck).to receive(:formula_or_cask_last_updated_timestamp).and_return(Time.now.to_i - 518400)

      expect(livecheck.send(:throttle_interval_elapsed?, f, 4)).to be(true)
    end
  end

  describe "::formula_or_cask_last_updated_timestamp" do
    let(:tap_path) { Pathname("/tmp/homebrew-core") }
    let(:tap) { instance_double(Tap, git?: true, path: tap_path) }

    it "uses FormulaVersions to find the latest version update commit for formulae" do
      formula_versions = instance_double(FormulaVersions)
      stable_same_version = instance_double(SoftwareSpec, version: Version.new("0.0.1"))
      stable_previous_version = instance_double(SoftwareSpec, version: Version.new("0.0.0"))
      historical_formula_same = instance_double(Formula, stable: stable_same_version)
      historical_formula_previous = instance_double(Formula, stable: stable_previous_version)

      allow(f).to receive(:tap).and_return(tap)
      allow(Utils::Git).to receive(:available?).and_return(true)
      allow(FormulaVersions).to receive(:new).with(f).and_return(formula_versions)
      allow(formula_versions).to receive(:rev_list).with("HEAD")
                                                   .and_yield("aaa111", "Formula/t/test.rb")
                                                   .and_yield("bbb222", "Formula/t/test.rb")
      allow(formula_versions).to receive(:formula_at_revision).with("aaa111", "Formula/t/test.rb")
                                                              .and_yield(historical_formula_same)
      allow(formula_versions).to receive(:formula_at_revision).with("bbb222", "Formula/t/test.rb")
                                                              .and_yield(historical_formula_previous)
      allow(Utils).to receive(:popen_read).and_return("1711731600\n")

      expect(livecheck.send(:formula_or_cask_last_updated_timestamp, f)).to eq(1711731600)
    end

    it "falls back to latest file commit timestamp for casks" do
      allow(c).to receive_messages(
        tap:             tap,
        sourcefile_path: tap_path/"Casks/test.rb",
      )
      allow(Utils::Git).to receive(:available?).and_return(true)
      allow(Utils).to receive(:popen_read).and_return("1711731600\n")

      expect(livecheck.send(:formula_or_cask_last_updated_timestamp, c)).to eq(1711731600)
    end
  end
end
