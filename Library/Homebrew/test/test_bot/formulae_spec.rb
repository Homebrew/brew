# typed: strict
# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::Formulae do
  describe "#dependency_name_match?" do
    it "requires exact matches when either name is tap-qualified", :aggregate_failures do
      Dir.mktmpdir do |tmpdir|
        output_paths = {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
        formulae = described_class.new(
          tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths:
        )

        expect(formulae.send(:dependency_name_match?, Dependency.new("foo"), "foo")).to be(true)
        expect(formulae.send(:dependency_name_match?, Dependency.new("homebrew/core/foo"), "homebrew/core/foo"))
          .to be(true)
        expect(formulae.send(:dependency_name_match?, Dependency.new("homebrew/core/foo"), "foo")).to be(false)
        expect(formulae.send(:dependency_name_match?, Dependency.new("homebrew/core/foo"), "user/tap/foo"))
          .to be(false)
      end
    end
  end

  describe "#annotate_added_dependencies" do
    it "writes a warning annotation for the new recursive dependency impact" do
      formula = formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
        depends_on "existing"
        depends_on "bar"
      end
      existing = formula("existing") do
        T.bind(self, T.class_of(Formula))
        url "existing-1.0"
      end
      bar = formula("bar") do
        T.bind(self, T.class_of(Formula))
        url "bar-1.0"
        depends_on "not-runtime" => :build
        depends_on "existing"
        depends_on "baz"
      end
      baz = formula("baz") do
        T.bind(self, T.class_of(Formula))
        url "baz-1.0"
        depends_on "not-runtime" => :test
        depends_on "recommended" => :recommended
      end
      recommended = formula("recommended") do
        T.bind(self, T.class_of(Formula))
        url "recommended-1.0"
        depends_on "not-runtime" => :optional
      end
      not_runtime = formula("not-runtime") do
        T.bind(self, T.class_of(Formula))
        url "not-runtime-1.0"
        depends_on "other"
      end
      other = formula("other") do
        T.bind(self, T.class_of(Formula))
        url "other-1.0"
      end

      [existing, bar, baz, recommended, not_runtime, other].each { |f| stub_formula_loader f }
      [[bar, 1_000_000], [baz, 500_000], [recommended, 400_000]].each do |f, size|
        allow(f).to receive(:bottle_for_tag)
          .and_return(instance_double(Bottle, fetch_tab: nil, installed_size: size))
      end
      allow(Utils).to receive(:safe_popen_read).and_return <<~DIFF
        @@ -2,0 +7,1 @@
        +  depends_on "bar"
      DIFF

      Dir.mktmpdir do |tmpdir|
        output_paths = {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
        formulae = described_class.new(
          tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths:
        )

        with_env(GITHUB_ACTIONS: "true") do
          expect { formulae.send(:annotate_added_dependencies, formula) }
            .to output(
              "::warning file=#{formula.path.relative_path_from(CoreTap.instance.path)},line=7," \
              "title=foo: new dependency impact::Adding `bar` adds 3 new recursive dependencies " \
              "on #{Utils::Bottles.tag} (1.9MB).\n",
            ).to_stdout
        end
      end
    end
  end

  describe "#annotate_missing_all_bottle" do
    sig { params(formula_path: Pathname, tag: Utils::Bottles::Tag, sha256: String).void }
    def write_platform_bottle_formula(formula_path, tag, sha256)
      formula_path.dirname.mkpath
      formula_path.write <<~RUBY
        class Foo < Formula
          desc "Foo"
          homepage "https://example.com"
          url "foo-1.0"
          sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

          bottle do
            sha256 cellar: :any_skip_relocation, #{tag.to_sym}: "#{sha256}"
          end
        end
      RUBY
    end

    sig {
      params(
        tap_path: Pathname,
        tag:      T.any(String, Utils::Bottles::Tag),
        sha256:   String,
        cellar:   String,
      ).void
    }
    def write_bottle_json(tap_path, tag, sha256, cellar: "any_skip_relocation")
      (tap_path/"foo--1.0.#{tag}.bottle.json").write JSON.generate(
        "foo" => {
          "bottle" => {
            "cellar" => cellar,
            "tags"   => {
              tag.to_s => {
                "sha256" => sha256,
              },
            },
          },
        },
      )
    end

    sig { params(formula_path: Pathname).returns(Formula) }
    def all_bottle_formula(formula_path)
      formula("foo", path: formula_path) do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
        bottle do
          sha256 cellar: :any_skip_relocation,
                 all:    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        end
      end
    end

    sig { params(tap_path: Pathname, tmpdir: String).returns(Homebrew::TestBot::Formulae) }
    def formulae_test_bot(tap_path, tmpdir)
      described_class.new(
        tap: instance_double(Tap, path: tap_path), git: "git", dry_run: true, fail_fast: false, verbose: false,
        output_paths: {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
      )
    end

    it "writes a warning annotation for a platform-specific bottle replacing an all bottle" do
      Dir.mktmpdir do |tmpdir|
        tag = Utils::Bottles.tag
        sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        other_tag = (tag.to_s == "arm64_tahoe") ? "tahoe" : "arm64_tahoe"
        other_sha256 = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        tap_path = Pathname(tmpdir)
        formula_path = tap_path/"Formula/foo.rb"
        write_platform_bottle_formula(formula_path, tag, sha256)
        write_bottle_json(tap_path, tag, sha256)
        write_bottle_json(tap_path, other_tag, other_sha256)

        old_formula = all_bottle_formula(formula_path)
        formulae = formulae_test_bot(tap_path, tmpdir)

        with_env(GITHUB_ACTIONS: "true", GITHUB_WORKSPACE: tap_path.to_s) do
          expect { formulae.send(:annotate_missing_all_bottle, old_formula, bottle_dir: tap_path) }
            .to output(
              "::warning file=Formula/foo.rb,line=8,title=foo: missing :all bottle::" \
              "This formula had an `:all` bottle but the #{tag} test-bot bottle is platform-specific " \
              "(cellar `any_skip_relocation`, sha256 `#{sha256}`). " \
              "If the final bottle merge cannot create a new `:all` bottle, expect publishing without one anyway; " \
              "this is for information only and should not block merge.\n",
            ).to_stdout
        end
      end
    end

    it "does not write a warning annotation when local JSON already has an all bottle" do
      Dir.mktmpdir do |tmpdir|
        tag = Utils::Bottles.tag
        sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        all_sha256 = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        tap_path = Pathname(tmpdir)
        formula_path = tap_path/"Formula/foo.rb"
        write_platform_bottle_formula(formula_path, tag, sha256)
        write_bottle_json(tap_path, tag, sha256)
        write_bottle_json(tap_path, "all", all_sha256)

        old_formula = all_bottle_formula(formula_path)
        formulae = formulae_test_bot(tap_path, tmpdir)

        with_env(GITHUB_ACTIONS: "true", GITHUB_WORKSPACE: tap_path.to_s) do
          expect { formulae.send(:annotate_missing_all_bottle, old_formula, bottle_dir: tap_path) }
            .not_to output.to_stdout
        end
      end
    end

    it "does not write a warning annotation for a single platform-specific bottle" do
      Dir.mktmpdir do |tmpdir|
        tag = Utils::Bottles.tag
        sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        tap_path = Pathname(tmpdir)
        formula_path = tap_path/"Formula/foo.rb"
        write_platform_bottle_formula(formula_path, tag, sha256)
        write_bottle_json(tap_path, tag, sha256)

        old_formula = all_bottle_formula(formula_path)
        formulae = formulae_test_bot(tap_path, tmpdir)

        with_env(GITHUB_ACTIONS: "true", GITHUB_WORKSPACE: tap_path.to_s) do
          expect { formulae.send(:annotate_missing_all_bottle, old_formula, bottle_dir: tap_path) }
            .not_to output.to_stdout
        end
      end
    end

    it "writes a warning annotation when matching checksums have different cellars" do
      Dir.mktmpdir do |tmpdir|
        tag = Utils::Bottles.tag
        other_tag = (tag.to_s == "arm64_tahoe") ? "tahoe" : "arm64_tahoe"
        sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        tap_path = Pathname(tmpdir)
        formula_path = tap_path/"Formula/foo.rb"
        write_platform_bottle_formula(formula_path, tag, sha256)
        write_bottle_json(tap_path, tag, sha256)
        write_bottle_json(tap_path, other_tag, sha256, cellar: "any")

        old_formula = all_bottle_formula(formula_path)
        formulae = formulae_test_bot(tap_path, tmpdir)

        with_env(GITHUB_ACTIONS: "true", GITHUB_WORKSPACE: tap_path.to_s) do
          expect { formulae.send(:annotate_missing_all_bottle, old_formula, bottle_dir: tap_path) }
            .to output(/title=foo: missing :all bottle::.*sha256 `#{sha256}`/).to_stdout
        end
      end
    end

    it "does not write a warning annotation when platform bottles can become an all bottle" do
      Dir.mktmpdir do |tmpdir|
        tag = Utils::Bottles.tag
        other_tag = (tag.to_s == "arm64_tahoe") ? "tahoe" : "arm64_tahoe"
        sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        tap_path = Pathname(tmpdir)
        formula_path = tap_path/"Formula/foo.rb"
        write_platform_bottle_formula(formula_path, tag, sha256)
        [tag.to_s, other_tag].each { |bottle_tag| write_bottle_json(tap_path, bottle_tag, sha256) }

        old_formula = all_bottle_formula(formula_path)
        formulae = formulae_test_bot(tap_path, tmpdir)

        with_env(GITHUB_ACTIONS: "true", GITHUB_WORKSPACE: tap_path.to_s) do
          expect { formulae.send(:annotate_missing_all_bottle, old_formula, bottle_dir: tap_path) }
            .not_to output.to_stdout
        end
      end
    end
  end

  describe "#testing_portable_ruby?" do
    it "returns false (not nil) when tap is nil" do
      # Regression test: without `!!`, tap&.core_tap? returns nil when tap is nil,
      # and `nil && ...` evaluates to nil, violating the T::Boolean return type.
      Dir.mktmpdir do |tmpdir|
        output_paths = {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
        formulae = described_class.new(
          tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths:
        )

        result = formulae.send(:testing_portable_ruby?)
        expect(result).to be(false)
      end
    end
  end

  describe "#verify_local_bottles" do
    it "returns false (not nil) when testing portable ruby" do
      # Regression test: the early return for portable ruby must be `return false`,
      # not bare `return` (which returns nil), to satisfy the T::Boolean return type.
      Dir.mktmpdir do |tmpdir|
        output_paths = {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
        formulae = described_class.new(
          tap: CoreTap.instance, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths:
        )
        formulae.testing_formulae = ["portable-ruby"]

        result = formulae.send(:verify_local_bottles)
        expect(result).to be(false)
      end
    end
  end

  describe "#cleanup_bottle_etc_var" do
    it "restores bottled config with InstallRenamed handling" do
      Dir.mktmpdir do |tmpdir|
        formula_class = Class.new(Formula)
        formula_class.url "foo-2.0"
        formula_class.version "2.0"
        f = formula_class.new("test-bot-config", Formulary.core_path("test-bot-config"), :stable)
        config_file = HOMEBREW_PREFIX/"etc/test-bot-config.conf"
        default_config_file = Pathname.new("#{config_file}.default")
        old_default_file = f.rack/"1.0/.bottle/etc/test-bot-config.conf"
        new_default_file = f.bottle_prefix/"etc/test-bot-config.conf"

        begin
          FileUtils.rm_rf f.rack
          FileUtils.rm_f config_file
          FileUtils.rm_f default_config_file

          old_default_file.dirname.mkpath
          old_default_file.write "old\n"
          new_default_file.dirname.mkpath
          new_default_file.write "new\n"
          config_file.dirname.mkpath
          config_file.write "old\n"

          described_class.new(
            tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
            output_paths: {
              bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
              linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
              skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
            }
          ).send(:cleanup_bottle_etc_var, f)

          expect([config_file.read, default_config_file.exist?]).to eq(["new\n", false])
        ensure
          FileUtils.rm_rf f.rack
          FileUtils.rm_f config_file
          FileUtils.rm_f default_config_file
        end
      end
    end
  end
end
