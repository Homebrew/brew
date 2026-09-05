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
  let(:f) do
    formula("test") do
      T.bind(self, T.class_of(Formula))
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
      T.bind(self, T.class_of(Formula))
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
        expect(livecheck.livecheck_strategy_names(Homebrew::Livecheck::Strategy::PageMatch)).to eq("PageMatch")
        expect(livecheck.livecheck_strategy_names(Homebrew::Livecheck::Strategy::PageMatch)).to eq("PageMatch")
      end
    end
  end

  describe "::livecheck_find_versions_parameters" do
    context "when provided with a strategy class" do
      it "returns parameter names" do
        strategy_class = Class.new do
          extend Homebrew::Livecheck::Strategic

          def self.match?(_url) = true
          def self.find_versions(url:, regex: nil) = {}
        end
        parameters = strategy_class.method(:find_versions).parameters.map(&:second)

        # We run this twice with the same argument to exercise the caching logic
        expect(livecheck.livecheck_find_versions_parameters(strategy_class)).to eq(parameters)
        expect(livecheck.livecheck_find_versions_parameters(strategy_class)).to eq(parameters)
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
        T.bind(self, T.class_of(Formula))
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
        T.bind(self, T.class_of(Formula))
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
        T.bind(self, T.class_of(Formula))
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz", using: :homebrew_curl
        # head is deliberately omitted to exercise more of the method

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

    it "returns `true` when the host matches a `using: :homebrew_curl` URL" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, livecheck_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, homepage_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, stable_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, livecheck_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, homepage_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, cask_url)).to be(true)
    end

    it "automatically uses brewed curl for matching pages" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({
        content: '{"stable":"0.0.2"}',
      })

      expect { livecheck.latest_version(f_homebrew_curl, debug: true) }
        .to output(a_string_matching(/Homebrew curl\?: +Yes/)).to_stdout
    end

    it "returns `false` if the host differs from `using: :homebrew_curl` URLs" do
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

    it "returns `false` if the URL string does not contain a valid host" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, "test")).to be(false)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, "https://[")).to be(false)
    end
  end

  describe "::latest_version" do
    let(:github_url) { head_url.delete_suffix(".git") }

    let(:f_no_livecheck) do
      formula("test_no_livecheck") do
        T.bind(self, T.class_of(Formula))
        desc "Test formula with no `livecheck` block"
        homepage "https://github.com/Homebrew/brew"
        url "https://brew.sh/test-0.0.1.tgz"
      end
    end

    let(:f_throttle_rate) do
      formula("test_throttle_rate") do
        T.bind(self, T.class_of(Formula))
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
        T.bind(self, T.class_of(Formula))
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
        T.bind(self, T.class_of(Formula))
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
    let(:git_content) do
      <<~EOS
        ed9942fbd1ec4243f0a92ab8f9b2411c8b1fb091\trefs/tags/1.2.3
      EOS
    end

    context "with terminal control characters" do
      let(:terminal_control_version) { "0.0.2\e]0;changed-title\a" }
      let(:f_terminal_control_version) do
        formula("terminal_control_version") do
          T.bind(self, T.class_of(Formula))
          desc "Formula with terminal controls in an upstream version"
          url "https://brew.sh/terminal-control-version-0.0.1.tgz"

          livecheck do
            url :stable
            regex(/terminal-control-version-(.+)\.tgz/i)
          end
        end
      end

      before do
        allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({
          content: %Q(<a href="terminal-control-version-#{terminal_control_version}.tgz">Download</a>),
        })
      end

      it "renders upstream terminal controls inert in human-readable output" do
        expect { livecheck.run_checks([f_terminal_control_version], debug: true, verbose: true) }
          .not_to output(/[\e\a\r]/).to_stdout
      end

      it "preserves upstream control characters as JSON data" do
        expected = JSON.pretty_generate([
          {
            formula: "terminal_control_version",
            version: {
              current:             "0.0.1",
              latest:              terminal_control_version,
              outdated:            true,
              newer_than_upstream: false,
            },
          },
        ])

        expect { livecheck.run_checks([f_terminal_control_version], json: true) }
          .to output("#{expected}\n").to_stdout
      end
    end

    it "can use a default check when there is no livecheck block" do
      # Only check the Git URL, so we can ensure the strategy doesn't make
      # network requests
      allow(livecheck).to receive(:checkable_urls).with(f_no_livecheck).and_return([github_url])
      allow(Homebrew::Livecheck::Strategy::Git).to receive(:ls_remote_tags)
        .and_return({ content: git_content })

      f_jv_version_info = livecheck.latest_version(f_no_livecheck, json: true, verbose: true)
      expect(f_jv_version_info&.dig(:meta)).not_to include(:references)
      expect(f_jv_version_info&.dig(:meta, :url, :original)).to eq(github_url)
      expect(f_jv_version_info&.dig(:meta, :url, :processed)).to eq(head_url)
      expect(f_jv_version_info&.dig(:latest)).to eq(Version.new("1.2.3"))
    end

    context "with a referenced formula/cask" do
      let(:f_options) do
        formula("test_options") do
          T.bind(self, T.class_of(Formula))
          desc "Test formula with `livecheck` block options"
          homepage "https://brew.sh"
          url "https://brew.sh/test-0.0.1.tgz"

          livecheck do
            url :homepage,
                homebrew_curl: true,
                post_json:     { key: "value" },
                user_agent:    :browser
            regex(/href=.*?test[._-]v?(\d+(?:\.\d+)+)\.(?:t|dmg)/i)
          end
        end
      end
      let(:f_reference) do
        formula("test_reference") do
          T.bind(self, T.class_of(Formula))
          desc "Test formula referencing another formula"
          homepage "https://brew.sh"
          url "https://brew.sh/test-0.0.1.tgz"

          livecheck do
            formula "test_options"
          end
        end
      end
      let(:f_reference_with_overrides) do
        formula("test_reference") do
          T.bind(self, T.class_of(Formula))
          desc "Test formula referencing another formula"
          homepage "https://brew.sh"
          url "https://brew.sh/test-0.0.1.tgz"

          livecheck do
            formula "test_options"
            url "https://brew.sh/test-override-referenced-url/",
                post_json:  { key: "overridden value" },
                user_agent: :curl
          end
        end
      end
      let(:f_reference_no_livecheck) do
        formula("test_reference") do
          T.bind(self, T.class_of(Formula))
          desc "Test formula referencing another formula"
          homepage "https://brew.sh"
          url "https://brew.sh/test-0.0.1.tgz"

          livecheck do
            formula "test_no_livecheck"
          end
        end
      end

      let(:c_options) do
        Cask::CaskLoader.load(+<<-RUBY)
          cask "test_options" do
            version "0.0.1"

            url "https://brew.sh/test-0.0.1.dmg"
            name "Test"
            desc "Test cask with `livecheck` block options"
            homepage "https://brew.sh"

            livecheck do
              url :homepage,
                  homebrew_curl: true,
                  post_json:     { key: "value" },
                  user_agent:    :browser
              regex(/href=.*?test[._-]v?(\\d+(?:\\.\\d+)+)\\.(?:t|dmg)/i)
            end
          end
        RUBY
      end
      let(:c_reference) do
        Cask::CaskLoader.load(+<<-RUBY)
          cask "test_reference" do
            version "0.0.1"

            url "https://brew.sh/test-0.0.1.dmg"
            name "Test"
            desc "Test cask referencing another cask"
            homepage "https://brew.sh"

            livecheck do
              cask "test_options"
            end
          end
        RUBY
      end

      it "uses options from the referenced `livecheck` block" do
        options_hash = {
          homebrew_curl: true,
          post_json:     { key: "value" },
          user_agent:    :browser,
        }

        expect(Homebrew::Livecheck::Strategy).to receive(:page_content)
          .at_least(:once)
          .with(
            homepage_url,
            options: Homebrew::Livecheck::Options.new(**options_hash),
          ).and_return({ content: base_content })

        expect do
          livecheck.latest_version(
            f_reference,
            referenced_formula_or_cask: f_options,
            livecheck_references:       [f_options],
            debug:                      true,
          )
        end.to output(
          a_string_matching(/Formula Ref:\s+test_options/)
            .and(matching(/URL \(homepage\):\s+#{homepage_url}/))
            .and(matching(/URL Options:\s+#{options_hash}/)),
        ).to_stdout

        f_jv_version_info = livecheck.latest_version(
          f_reference,
          referenced_formula_or_cask: f_options,
          livecheck_references:       [f_options],
          json:                       true,
          verbose:                    true,
        )
        expect(f_jv_version_info&.dig(:meta, :references)).to eq([{ formula: "test_options" }])
        expect(f_jv_version_info&.dig(:meta, :url, :symbol)).to eq(:homepage)
        expect(f_jv_version_info&.dig(:meta, :url, :original)).to eq(homepage_url)
        expect(f_jv_version_info&.dig(:meta, :url, :options)).to eq(options_hash)

        expect do
          livecheck.latest_version(
            c_reference,
            referenced_formula_or_cask: c_options,
            livecheck_references:       [c_options],
            debug:                      true,
          )
        end.to output(
          a_string_matching(/Cask Ref:\s+test_options/)
            .and(matching(/URL \(homepage\):\s+#{homepage_url}/))
            .and(matching(/URL Options:\s+#{options_hash}/)),
        ).to_stdout

        c_jv_version_info = livecheck.latest_version(
          c_reference,
          referenced_formula_or_cask: c_options,
          livecheck_references:       [c_options],
          json:                       true,
          verbose:                    true,
        )
        expect(c_jv_version_info&.dig(:meta, :references)).to eq([{ cask: "test_options" }])
        expect(c_jv_version_info&.dig(:meta, :url, :symbol)).to eq(:homepage)
        expect(c_jv_version_info&.dig(:meta, :url, :original)).to eq(homepage_url)
        expect(c_jv_version_info&.dig(:meta, :url, :options)).to eq(options_hash)
      end

      it "merges options from the initial `livecheck` block into referenced options" do
        overridden_url = "https://brew.sh/test-override-referenced-url/"
        options_hash = {
          homebrew_curl: true,
          post_json:     { key: "overridden value" },
          user_agent:    :curl,
        }

        expect(Homebrew::Livecheck::Strategy).to receive(:page_content)
          .at_least(:once)
          .with(
            overridden_url,
            options: Homebrew::Livecheck::Options.new(**options_hash),
          ).and_return({ content: base_content })

        expect do
          livecheck.latest_version(
            f_reference_with_overrides,
            referenced_formula_or_cask: f_options,
            livecheck_references:       [f_options],
            debug:                      true,
          )
        end.to output(
          a_string_matching(/Formula Ref:\s+test_options/)
            .and(matching(/URL:\s+#{overridden_url}/))
            .and(matching(/URL Options:\s+#{options_hash}/)),
        ).to_stdout

        f_jv_version_info = livecheck.latest_version(
          f_reference_with_overrides,
          referenced_formula_or_cask: f_options,
          livecheck_references:       [f_options],
          json:                       true,
          verbose:                    true,
        )
        expect(f_jv_version_info&.dig(:meta, :references)).to eq([{ formula: "test_options" }])
        expect(f_jv_version_info&.dig(:meta, :url, :original)).to eq(overridden_url)
        expect(f_jv_version_info&.dig(:meta, :url, :options)).to eq(options_hash)
      end

      it "uses values from a referenced package without a `livecheck` block" do
        # Only check the Git URL, so we can ensure the strategy doesn't make
        # network requests
        allow(livecheck).to receive(:checkable_urls).with(f_no_livecheck).and_return([github_url])
        allow(Homebrew::Livecheck::Strategy::Git).to receive(:ls_remote_tags)
          .and_return({ content: git_content })

        expect do
          livecheck.latest_version(
            f_reference_no_livecheck,
            referenced_formula_or_cask: f_no_livecheck,
            livecheck_references:       [f_no_livecheck],
            debug:                      true,
          )
        end.to output(
          a_string_matching(/Formula Ref:\s+test_no_livecheck/)
            .and(matching(/URL:\s+#{github_url}/))
            .and(matching(/URL \(processed\):\s+#{head_url}/)),
        ).to_stdout

        f_jv_version_info = livecheck.latest_version(
          f_reference_no_livecheck,
          referenced_formula_or_cask: f_no_livecheck,
          livecheck_references:       [f_no_livecheck],
          json:                       true,
          verbose:                    true,
        )
        expect(f_jv_version_info&.dig(:meta, :references)).to eq([{ formula: "test_no_livecheck" }])
        expect(f_jv_version_info&.dig(:meta, :url, :original)).to eq(github_url)
        expect(f_jv_version_info&.dig(:meta, :url, :processed)).to eq(head_url)
      end
    end

    it "sets `latest_throttled` to the highest throttled version" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({
        content: <<~HTML,
          <a href="test-0.0.3.tgz">0.0.3</a>
          <a href="test-0.0.4.tgz">0.0.4</a>
          <a href="test-0.0.5.tgz">0.0.5</a>
        HTML
      })

      f_result = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(Version)]))
      expect { f_result = livecheck.latest_version(f_throttle_rate, debug: true, verbose: true) }
        .to output(
          a_string_matching(/Throttle: +4 versions/)
          .and(matching(/Matched Throttled Versions:\n0.0.4 => #<Version 0.0.4>/)),
        ).to_stdout
      expect(f_result[:latest]).to eq(Version.new("0.0.5"))
      expect(f_result[:latest_throttled]).to eq(Version.new("0.0.4"))

      c_result = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(Version)]))
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

      f_result = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(Version)]))
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

      f_result = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(Version)]))
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

  describe "::throttle_allows_bump?" do
    let(:version) { Version.new("1.2.3") }

    it "returns true if `throttle_rate` and `throttle_days` are nil" do
      expect(livecheck.throttle_allows_bump?(f, version)).to be(true)
    end

    it "returns true if patch version is divisible by `throttle_rate`" do
      expect(livecheck.throttle_allows_bump?(f, version, throttle_rate: 3)).to be(true)
      expect(livecheck.throttle_allows_bump?(f, "1.2.3", throttle_rate: 3)).to be(true)
    end

    it "returns false if patch version is not divisible by `throttle_rate` and `throttle_days` is not set" do
      expect(livecheck.throttle_allows_bump?(f, version, throttle_rate: 5)).to be(false)
    end

    it "returns false if patch version is not divisible by `throttle_rate` and throttle interval has not elapsed" do
      allow(livecheck).to receive(:throttle_interval_elapsed?).and_return(false)
      expect(livecheck.throttle_allows_bump?(f, version, throttle_rate: 5, throttle_days: 1)).to be(false)
    end

    it "returns true if patch version is not divisible by `throttle_rate` and throttle interval has elapsed" do
      allow(livecheck).to receive(:throttle_interval_elapsed?).and_return(true)
      expect(livecheck.throttle_allows_bump?(f, version, throttle_rate: 5, throttle_days: 1)).to be(true)
    end

    it "returns false if only `throttle_days` is provided and throttle interval has not elapsed" do
      allow(livecheck).to receive(:throttle_interval_elapsed?).and_return(false)
      expect(livecheck.throttle_allows_bump?(f, version, throttle_days: 1)).to be(false)
    end

    it "returns true if only `throttle_days` is provided and throttle interval has elapsed" do
      allow(livecheck).to receive(:throttle_interval_elapsed?).and_return(true)
      expect(livecheck.throttle_allows_bump?(f, version, throttle_days: 1)).to be(true)
    end
  end

  describe "::throttle_interval_elapsed" do
    it "returns false if days is not positive" do
      expect(livecheck.throttle_interval_elapsed?(f, 0)).to be(false)
      expect(livecheck.throttle_interval_elapsed?(f, -1)).to be(false)
    end

    it "returns false if last_updated_timestamp can't be determined" do
      allow(livecheck).to receive(:formula_or_cask_last_updated_timestamp).and_return(nil)

      expect(livecheck.throttle_interval_elapsed?(f, 4)).to be(false)
    end

    it "returns false if throttle interval has not elapsed" do
      allow(livecheck).to receive(:formula_or_cask_last_updated_timestamp).and_return(Time.now.to_i)

      expect(livecheck.throttle_interval_elapsed?(f, 4)).to be(false)
    end

    it "returns true if throttle interval has elapsed" do
      allow(livecheck).to receive(:formula_or_cask_last_updated_timestamp).and_return(Time.now.to_i - 518400)

      expect(livecheck.throttle_interval_elapsed?(f, 4)).to be(true)
    end
  end

  describe "::formula_or_cask_last_updated_timestamp" do
    let(:tap_path) { Pathname("/tmp/homebrew-core") }
    let(:tap) { instance_double(Tap, git?: true, path: tap_path) }

    # HEAD walk (newest -> oldest):
    #   yield | rev    | version | action
    #   ------+--------+---------+-----------------------------------------
    #     1   | ddd444 |  0.0.2  | skip (in-flight PR commit, != current)
    #     2   | ccc333 |  0.0.1  | == current, version_update_revision = ccc333
    #     3   | bbb222 |  0.0.1  | == current, version_update_revision = bbb222
    #     4   | aaa111 |  0.0.0  | != current, return bbb222
    it "uses FormulaVersions to find the latest version update commit for formulae" do
      formula_versions = instance_double(FormulaVersions)
      bump_version = instance_double(SoftwareSpec, version: Version.new("0.0.2"))
      stable_same_version = instance_double(SoftwareSpec, version: Version.new("0.0.1"))
      stable_previous_version = instance_double(SoftwareSpec, version: Version.new("0.0.0"))
      bump_formula = instance_double(Formula, stable: bump_version)
      historical_formula_same = instance_double(Formula, stable: stable_same_version)
      historical_formula_previous = instance_double(Formula, stable: stable_previous_version)

      allow(f).to receive_messages(tap: tap, path: tap_path/"Formula/t/test.rb")
      allow(Utils::Git).to receive(:available?).and_return(true)
      allow(FormulaVersions).to receive(:new).with(f).and_return(formula_versions)
      allow(Utils).to receive(:popen_read)
        .with(Utils::Git.git, "rev-parse", "origin/HEAD", chdir: tap_path)
        .and_return("ccc333\n")
      allow(formula_versions).to receive(:rev_list).with("HEAD")
                                                   .and_yield("ddd444", "Formula/t/test.rb")
                                                   .and_yield("ccc333", "Formula/t/test.rb")
                                                   .and_yield("bbb222", "Formula/t/test.rb")
                                                   .and_yield("aaa111", "Formula/t/test.rb")
      allow(formula_versions).to receive(:formula_at_revision).with("ddd444", "Formula/t/test.rb")
                                                              .and_yield(bump_formula)
      allow(formula_versions).to receive(:formula_at_revision).with("ccc333", "Formula/t/test.rb")
                                                              .and_yield(historical_formula_same)
      allow(formula_versions).to receive(:formula_at_revision).with("bbb222", "Formula/t/test.rb")
                                                              .and_yield(historical_formula_same)
      allow(formula_versions).to receive(:formula_at_revision).with("aaa111", "Formula/t/test.rb")
                                                              .and_yield(historical_formula_previous)
      allow(Utils).to receive(:popen_read)
        .with(Utils::Git.git, "show", "-s", "--format=%ct", "bbb222", chdir: tap_path)
        .and_return("1711731600\n")

      expect(livecheck.formula_or_cask_last_updated_timestamp(f)).to eq(1711731600)
    end

    it "falls back to latest file commit timestamp for casks" do
      allow(c).to receive_messages(
        tap:             tap,
        sourcefile_path: tap_path/"Casks/test.rb",
      )
      allow(Utils::Git).to receive(:available?).and_return(true)
      allow(Utils).to receive(:popen_read).and_return("1711731600\n")

      expect(livecheck.formula_or_cask_last_updated_timestamp(c)).to eq(1711731600)
    end
  end
end
