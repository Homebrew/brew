# typed: true
# frozen_string_literal: true

require "test_bot"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::Formulae do
  describe "#formula!" do
    subject(:formulae) do
      Class.new(described_class) do
        T.bind(self, T.class_of(Homebrew::TestBot::Formulae))
        public :formula!
      end.new(
        tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
        output_paths: {
          bottle:                     Pathname("bottle.txt"),
          linkage:                    Pathname("linkage.txt"),
          skipped_or_failed_formulae: Pathname("skipped.txt"),
        }
      )
    end

    it "includes test resources in the existing bottle-build fetch" do
      foo = formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0.tar.gz"
      end
      stub_formula_loader foo
      allow(formulae).to receive_messages(bottled?: true, build_bottle?: true, cleanup?: false,
                                          unsatisfied_requirements_messages: "Unavailable requirement")
      allow(formulae).to receive(:annotate_added_dependencies)
      allow(formulae).to receive(:install_ca_certificates_if_needed)
      allow(formulae).to receive(:skipped)

      formulae.formula!("foo", args: Homebrew::Cmd::TestBotCmd.new([]).args)

      expect(formulae.steps.map(&:command)).to include(%w[brew fetch --formula --retry foo --test --build-bottle])
    end
  end

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

        expect(formulae.dependency_name_match?(Dependency.new("foo"), "foo")).to be(true)
        expect(formulae.dependency_name_match?(Dependency.new("homebrew/core/foo"), "homebrew/core/foo"))
          .to be(true)
        expect(formulae.dependency_name_match?(Dependency.new("homebrew/core/foo"), "foo")).to be(false)
        expect(formulae.dependency_name_match?(Dependency.new("homebrew/core/foo"), "user/tap/foo"))
          .to be(false)
      end
    end
  end

  describe "#install_padded_prefix_source_dependencies" do
    it "installs dependencies without compatible bottles at a padded prefix" do
      Dir.mktmpdir do |tmpdir|
        formulae = described_class.new(
          tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths: {
            bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
            linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
            skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
          }
        )
        compatible = instance_double(Formula, bottle: instance_double(Bottle))
        incompatible = instance_double(Formula, bottle: nil)
        allow(Formulary).to receive(:factory).with("compatible").and_return(compatible)
        allow(Formulary).to receive(:factory).with("incompatible").and_return(incompatible)
        padded_prefix = Utils::Bottles.tag.padded_prefix
        raise "Current tag has no padded prefix" if padded_prefix.nil?

        stub_const("HOMEBREW_PREFIX", Pathname(padded_prefix))

        formulae.install_padded_prefix_source_dependencies(%w[compatible incompatible])

        expect(formulae.steps.map(&:command)).to eq [
          %w[brew install --formulae --build-from-source incompatible],
        ]
      end
    end
  end

  describe "#annotate_added_dependencies" do
    subject(:formulae) do
      described_class.new(
        tap: impact_tap, git: "git", dry_run: true, fail_fast: false, verbose: false,
        output_paths: {
          bottle:                     Pathname("bottle.txt"),
          linkage:                    Pathname("linkage.txt"),
          skipped_or_failed_formulae: Pathname("skipped.txt"),
        }
      )
    end

    let(:impact_tap) { CoreTap.instance }
    let(:repository) { impact_tap.path }

    before do
      ENV["GITHUB_ACTIONS"] = "true"
      allow(formulae).to receive(:opoo) { |message| raise message }
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", repository, "diff", "--no-ext-diff", "--no-renames", "--name-only", "--diff-filter=MD",
              "-z", "origin/HEAD", "HEAD").and_return("Formula/foo.rb\0")
    end

    it "writes a warning annotation for the new recursive dependency impact" do
      formula = formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
        depends_on "existing"
        depends_on "bar"
        depends_on "baz"
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
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", repository, "diff", "--no-ext-diff", "--unified=0",
              "origin/HEAD", "HEAD", "--", formula.path.relative_path_from(repository).to_s).and_return <<~DIFF
                @@ -2,0 +7,2 @@
                +  depends_on "bar"
                +  depends_on "baz"
              DIFF
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", repository, "show",
              "origin/HEAD:#{formula.path.relative_path_from(repository)}").and_return <<~RUBY
                class Foo < Formula
                  url "foo-1.0"
                  depends_on "existing"
                end
              RUBY

      expect { formulae.annotate_added_dependencies(formula) }
        .to output(
          "::warning file=#{formula.path.relative_path_from(repository)},line=7," \
          "title=foo: dependency impact::Recursive runtime dependencies on #{Utils::Bottles.tag}: " \
          "3 added, 0 removed (net change: 3). Installed size change: +1.9MB. " \
          "Added: `bar`, `baz`, `recommended`.\n",
        ).to_stdout
    end

    context "with a real tap history", :no_api do
      let(:git) do
        ["git", "-C", repository.to_s, "-c", "user.name=Test", "-c", "user.email=test@example.test",
         "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null"]
      end

      sig { params(name: String, dependencies: T::Array[String]).void }
      def write_impact_formula(name, dependencies)
        path = repository/"Formula/#{name}.rb"
        path.dirname.mkpath
        path.write <<~RUBY
          class #{Formulary.class_s(name)} < Formula
            url "https://example.com/#{name}-1.0.tar.gz"
            #{dependencies.map { |dependency| "depends_on #{dependency.inspect}" }.join("\n  ")}
          end
        RUBY
      end

      sig { void }
      def commit_impact_formulae
        Utils.safe_popen_read(*git, "add", ".")
        Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Update formulae")
      end

      before do
        allow(Utils).to receive(:safe_popen_read).and_call_original
        write_impact_formula("foo", %w[libssh2 openssl@3])
        write_impact_formula("libssh2", %w[openssl@3])
        write_impact_formula("openssl@3", %w[ca-certificates])
        write_impact_formula("openssl@4", %w[ca-certificates])
        write_impact_formula("ca-certificates", [])
        Utils.safe_popen_read(*git, "init", "--quiet")
        Utils.safe_popen_read(*git, "remote", "add", "origin", impact_tap.default_remote)
        commit_impact_formulae
        Utils.safe_popen_read(*git, "update-ref", "refs/remotes/origin/HEAD", "HEAD")
        allow(Formulary).to receive(:factory).and_wrap_original do |method, *args, **kwargs|
          loaded = method.call(*args, **kwargs)
          size = { "openssl@3" => 23_000_000, "openssl@4" => 24_000_000, "newlib" => nil }.fetch(loaded.name, 0)
          allow(loaded).to receive(:bottle_for_tag)
            .and_return(instance_double(Bottle, fetch_tab: nil, installed_size: size))
          loaded
        end
      end

      it "uses the previous dependencies of formulae migrated in the same change" do
        write_impact_formula("foo", %w[libssh2 openssl@4])
        write_impact_formula("libssh2", %w[openssl@4])
        commit_impact_formulae

        expect { formulae.annotate_added_dependencies(Formulary.factory("foo")) }
          .to output(
            "::warning file=Formula/foo.rb,line=4," \
            "title=foo: dependency impact::Recursive runtime dependencies on #{Utils::Bottles.tag}: " \
            "1 added, 1 removed (net change: 0). Installed size change: +1MB. " \
            "Added: `openssl@4`. Removed: `openssl@3`.\n",
          ).to_stdout
      end

      it "traverses a deleted previous dependency and its descendants" do
        write_impact_formula("foo", %w[openssl@4])
        (repository/"Formula/libssh2.rb").unlink
        commit_impact_formulae

        expect { formulae.annotate_added_dependencies(Formulary.factory("foo")) }
          .to output(
            "::warning file=Formula/foo.rb,line=3," \
            "title=foo: dependency impact::Recursive runtime dependencies on #{Utils::Bottles.tag}: " \
            "1 added, 2 removed (net change: -1). Installed size change: unknown (1 unknown size). " \
            "Added: `openssl@4`. Removed: `libssh2`, `openssl@3`.\n",
          ).to_stdout
      end

      it "reports a lower bound when only added dependency sizes are unknown" do
        write_impact_formula("newlib", [])
        write_impact_formula("foo", %w[libssh2 openssl@3 openssl@4 newlib])
        commit_impact_formulae

        expect { formulae.annotate_added_dependencies(Formulary.factory("foo")) }
          .to output(/Installed size change: at least \+24MB \(1 unknown size\)\./).to_stdout
      end

      it "includes explicitly enabled optional transitive dependencies" do
        write_impact_formula("newlib", [])
        (repository/"Formula/foo.rb").write <<~RUBY
          class Foo < Formula
            url "https://example.com/foo-1.0.tar.gz"
            depends_on "libssh2" => "with-newlib"
          end
        RUBY
        (repository/"Formula/libssh2.rb").write <<~RUBY
          class Libssh2 < Formula
            url "https://example.com/libssh2-1.0.tar.gz"
            depends_on "openssl@3"
            depends_on "newlib" => :optional
          end
        RUBY
        commit_impact_formulae

        expect { formulae.annotate_added_dependencies(Formulary.factory("foo")) }
          .to output(/1 added, 0 removed \(net change: 1\).*Added: `newlib`\./).to_stdout
      end

      it "loads each historical formula only once across annotations" do
        write_impact_formula("foo", %w[libssh2 openssl@4])
        write_impact_formula("libssh2", %w[openssl@4])
        commit_impact_formulae
        allow(formulae).to receive(:puts)

        expect(Utils).to receive(:safe_popen_read)
          .with("git", "-C", repository, "show", "origin/HEAD:Formula/libssh2.rb").once.and_call_original

        2.times { formulae.annotate_added_dependencies(Formulary.factory("foo")) }
      end

      context "with a non-core tap" do
        let(:impact_tap) { Tap.fetch("homebrew/test-bot") }

        it "finds a deleted dependency declared without its tap prefix" do
          write_impact_formula("foo", %w[openssl@4])
          (repository/"Formula/libssh2.rb").unlink
          commit_impact_formulae

          expect { formulae.annotate_added_dependencies(Formulary.factory("#{impact_tap}/foo")) }
            .to output(
              "::warning file=Formula/foo.rb,line=3," \
              "title=foo: dependency impact::" \
              "Recursive runtime dependencies on #{Utils::Bottles.tag}: " \
              "1 added, 2 removed (net change: -1). Installed size change: unknown (1 unknown size). " \
              "Added: `homebrew/test-bot/openssl@4`. " \
              "Removed: `homebrew/test-bot/libssh2`, `homebrew/test-bot/openssl@3`.\n",
            ).to_stdout
        end

        it "preserves core precedence over a deleted non-core formula with the same name" do
          (CoreTap.instance.path/"Formula/libssh2.rb").write <<~RUBY
            class Libssh2 < Formula
              url "https://example.com/libssh2-1.0.tar.gz"
            end
          RUBY
          write_impact_formula("foo", %w[openssl@4])
          (repository/"Formula/libssh2.rb").unlink
          commit_impact_formulae

          expect { formulae.annotate_added_dependencies(Formulary.factory("#{impact_tap}/foo")) }
            .to output(%r{Removed: `homebrew/test-bot/openssl@3`, `libssh2`\.}).to_stdout
        end
      end
    end

    context "when replacing a versioned dependency" do
      let(:current) do
        formula("foo") do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          depends_on "openssl@4"
        end
      end
      let(:old_dependency) { "openssl@3" }
      let(:old_size) { 23_000_000 }
      let(:new_size) { 24_000_000 }

      before do
        certificates = formula("ca-certificates") do
          T.bind(self, T.class_of(Formula))
          url "certificates-1.0"
        end
        stub_formula_loader certificates
        { "openssl@3" => old_size, "openssl@4" => new_size }.each do |name, size|
          openssl = formula(name) do
            T.bind(self, T.class_of(Formula))
            url "openssl-1.0"
            depends_on "ca-certificates"
          end
          stub_formula_loader openssl
          allow(openssl).to receive(:bottle_for_tag)
            .and_return(instance_double(Bottle, fetch_tab: nil, installed_size: size))
        end
        allow(Utils).to receive(:safe_popen_read)
          .with("git", "-C", repository, "diff", "--no-ext-diff", "--unified=0",
                "origin/HEAD", "HEAD", "--", current.path.relative_path_from(repository).to_s)
          .and_return <<~DIFF
            @@ -3 +3 @@
            -  depends_on "#{old_dependency}"
            +  depends_on "openssl@4"
          DIFF
        allow(Utils).to receive(:safe_popen_read)
          .with("git", "-C", repository, "show",
                "origin/HEAD:#{current.path.relative_path_from(repository)}").and_return <<~RUBY
                  class Foo < Formula
                    url "foo-1.0"
                    depends_on "#{old_dependency}"
                  end
                RUBY
      end

      it "reports the replacement and net size without counting shared dependencies" do
        expect { formulae.annotate_added_dependencies(current) }
          .to output(
            "::warning file=#{current.path.relative_path_from(repository)},line=3," \
            "title=foo: dependency impact::Recursive runtime dependencies on #{Utils::Bottles.tag}: " \
            "1 added, 1 removed (net change: 0). Installed size change: +1MB. " \
            "Added: `openssl@4`. Removed: `openssl@3`.\n",
          ).to_stdout
      end

      context "when the replacement is smaller" do
        let(:new_size) { 22_000_000 }

        it "reports the size reduction" do
          expect { formulae.annotate_added_dependencies(current) }
            .to output(/Installed size change: -1MB\./).to_stdout
        end
      end

      context "when a bottle size is unavailable" do
        let(:old_size) { nil }

        it "does not present a partial size difference as the net change" do
          expect { formulae.annotate_added_dependencies(current) }
            .to output(/Installed size change: unknown \(1 unknown size\)\./).to_stdout
        end
      end

      context "when the declaration is only moved" do
        let(:old_dependency) { "openssl@4" }

        it "does not annotate an unchanged dependency set" do
          expect { formulae.annotate_added_dependencies(current) }.not_to output.to_stdout
        end
      end

      context "when another new dependency still needs the old version" do
        let(:current) do
          formula("foo") do
            T.bind(self, T.class_of(Formula))
            url "foo-1.0"
            depends_on "openssl@4"
            depends_on "consumer"
          end
        end

        before do
          consumer = formula("consumer") do
            T.bind(self, T.class_of(Formula))
            url "consumer-1.0"
            depends_on "openssl@3"
          end
          stub_formula_loader consumer
          allow(consumer).to receive(:bottle_for_tag)
            .and_return(instance_double(Bottle, fetch_tab: nil, installed_size: 500_000))
          allow(Utils).to receive(:safe_popen_read)
            .with("git", "-C", repository, "diff", "--no-ext-diff", "--unified=0",
                  "origin/HEAD", "HEAD", "--", current.path.relative_path_from(repository).to_s)
            .and_return <<~DIFF
              @@ -3 +3,2 @@
              -  depends_on "openssl@3"
              +  depends_on "openssl@4"
              +  depends_on "consumer"
            DIFF
        end

        it "reports the combined growth without subtracting the retained dependency" do
          expect { formulae.annotate_added_dependencies(current) }
            .to output(
              "::warning file=#{current.path.relative_path_from(repository)},line=3," \
              "title=foo: dependency impact::Recursive runtime dependencies on #{Utils::Bottles.tag}: " \
              "2 added, 0 removed (net change: 2). Installed size change: +24.5MB. " \
              "Added: `consumer`, `openssl@4`.\n",
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
          expect { formulae.annotate_missing_all_bottle(old_formula, bottle_dir: tap_path) }
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
          expect { formulae.annotate_missing_all_bottle(old_formula, bottle_dir: tap_path) }
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
          expect { formulae.annotate_missing_all_bottle(old_formula, bottle_dir: tap_path) }
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
          expect { formulae.annotate_missing_all_bottle(old_formula, bottle_dir: tap_path) }
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
          expect { formulae.annotate_missing_all_bottle(old_formula, bottle_dir: tap_path) }
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

        result = formulae.testing_portable_ruby?
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

        result = formulae.verify_local_bottles
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
          ).cleanup_bottle_etc_var(f)

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
