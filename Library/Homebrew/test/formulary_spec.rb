# frozen_string_literal: true

require "formula"
require "formula_installer"
require "utils/bottles"

# rubocop:todo RSpec/AggregateExamples
RSpec.describe Formulary do
  let(:formula_name) { "testball_bottle" }
  let(:formula_path) { CoreTap.instance.new_formula_path(formula_name) }
  let(:formula_content) do
    <<~RUBY
      class #{described_class.class_s(formula_name)} < Formula
        url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
        sha256 TESTBALL_SHA256

        bottle do
          root_url "file://#{bottle_dir}"
          sha256 cellar: :any_skip_relocation, #{Utils::Bottles.tag}: "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97"
        end

        def install
          prefix.install "bin"
          prefix.install "libexec"
        end
      end
    RUBY
  end
  let(:bottle_dir) { Pathname.new("#{TEST_FIXTURE_DIR}/bottles") }
  let(:bottle) { bottle_dir/"testball_bottle-0.1.#{Utils::Bottles.tag}.bottle.tar.gz" }

  describe "::class_s" do
    it "replaces '+' with 'x'" do
      expect(described_class.class_s("foo++")).to eq("Fooxx")
    end

    it "converts a string with dots to PascalCase" do
      expect(described_class.class_s("shell.fm")).to eq("ShellFm")
    end

    it "converts a string with hyphens to PascalCase" do
      expect(described_class.class_s("pkg-config")).to eq("PkgConfig")
    end

    it "converts a string with a single letter separated by a hyphen to PascalCase" do
      expect(described_class.class_s("s-lang")).to eq("SLang")
    end

    it "converts a string with underscores to PascalCase" do
      expect(described_class.class_s("foo_bar")).to eq("FooBar")
    end

    it "replaces '@' with 'AT'" do
      expect(described_class.class_s("openssl@1.1")).to eq("OpensslAT11")
    end
  end

  describe "::factory" do
    context "without the API", :no_api do
      before do
        formula_path.dirname.mkpath
        formula_path.write formula_content
      end

      it "returns a Formula" do
        expect(described_class.factory(formula_name)).to be_a(Formula)
      end

      it "returns a Formula when given a fully qualified name" do
        expect(described_class.factory("homebrew/core/#{formula_name}")).to be_a(Formula)
      end

      it "raises an error if the Formula cannot be found" do
        expect do
          described_class.factory("not_existed_formula")
        end.to raise_error(FormulaUnavailableError)
      end

      it "raises an error if ref is nil" do
        expect do
          described_class.factory(nil)
        end.to raise_error(TypeError)
      end

      context "with sharded Formula directory" do
        let(:formula_name) { "testball_sharded" }
        let(:formula_path) do
          core_tap = CoreTap.instance
          (core_tap.formula_dir/formula_name[0]).mkpath
          core_tap.new_formula_path(formula_name)
        end

        it "returns a Formula" do
          expect(described_class.factory(formula_name)).to be_a(Formula)
        end

        it "returns a Formula when given a fully qualified name" do
          expect(described_class.factory("homebrew/core/#{formula_name}")).to be_a(Formula)
        end
      end

      context "when the Formula has the wrong class" do
        let(:formula_name) { "giraffe" }
        let(:formula_content) do
          <<~RUBY
            class Wrong#{described_class.class_s(formula_name)} < Formula
            end
          RUBY
        end

        it "raises an error" do
          expect do
            described_class.factory(formula_name)
          end.to raise_error(TapFormulaClassUnavailableError)
        end
      end

      it "returns a Formula when given a path" do
        expect(described_class.factory(formula_path)).to be_a(Formula)
      end

      it "errors when given a path but paths are disabled" do
        ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
        FileUtils.cp formula_path, HOMEBREW_TEMP
        temp_formula_path = HOMEBREW_TEMP/formula_path.basename
        expect do
          described_class.factory(temp_formula_path)
        ensure
          temp_formula_path.unlink
        end.to raise_error(RuntimeError, /requires formulae to be in a tap, rejecting/)
      end

      it "returns a Formula when given a URL", :needs_utils_curl do
        formula = described_class.factory("file://#{formula_path}")
        expect(formula).to be_a(Formula)
      end

      it "errors when given a URL but paths are disabled" do
        ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
        expect do
          described_class.factory("file://#{formula_path}")
        end.to raise_error(FormulaUnavailableError)
      end

      context "when given a cache path" do
        let(:cache_dir) { HOMEBREW_CACHE/"test_formula_cache" }
        let(:cache_formula_path) { cache_dir/formula_path.basename }

        before do
          cache_dir.mkpath
          FileUtils.cp formula_path, cache_formula_path
        end

        after do
          cache_formula_path.unlink if cache_formula_path.exist?
          cache_dir.rmdir if cache_dir.exist?
        end

        it "disallows cache paths when paths are explicitly disabled" do
          ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
          expect do
            described_class.factory(cache_formula_path)
          end.to raise_error(/requires formulae to be in a tap/)
        end
      end

      context "when given a bottle" do
        subject(:formula) { described_class.factory(bottle) }

        it "returns a Formula" do
          expect(formula).to be_a(Formula)
        end

        it "calling #local_bottle_path on the returned Formula returns the bottle path" do
          expect(formula.local_bottle_path).to eq(bottle.realpath)
        end
      end

      context "when given an alias" do
        subject(:formula) { described_class.factory("foo") }

        let(:alias_dir) { CoreTap.instance.alias_dir }
        let(:alias_path) { alias_dir/"foo" }

        before do
          alias_dir.mkpath
          FileUtils.ln_s formula_path, alias_path
        end

        it "returns a Formula" do
          expect(formula).to be_a(Formula)
        end

        it "calling #alias_path on the returned Formula returns the alias path" do
          expect(formula.alias_path).to eq(alias_path)
        end
      end

      context "with installed Formula" do
        before do
          # don't try to load/fetch gcc/glibc
          allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)
        end

        let(:installed_formula) { described_class.factory(formula_path) }
        let(:installer) { FormulaInstaller.new(installed_formula) }

        it "returns a Formula when given a rack" do
          installer.fetch
          installer.install

          f = described_class.from_rack(installed_formula.rack)
          expect(f).to be_a(Formula)
        end

        it "returns a Formula when given a Keg" do
          installer.fetch
          installer.install

          keg = Keg.new(installed_formula.prefix)
          f = described_class.from_keg(keg)
          expect(f).to be_a(Formula)
        end
      end

      context "when migrating from a Tap" do
        let(:tap) { Tap.fetch("homebrew", "foo") }
        let(:another_tap) { Tap.fetch("homebrew", "bar") }
        let(:tap_migrations_path) { tap.path/"tap_migrations.json" }
        let(:another_tap_formula_path) { another_tap.path/"Formula/#{formula_name}.rb" }

        before do
          tap.path.mkpath
          another_tap_formula_path.dirname.mkpath
          another_tap_formula_path.write formula_content
        end

        after do
          FileUtils.rm_rf tap.path
          FileUtils.rm_rf another_tap.path
        end

        it "returns a Formula that has gone through a tap migration into homebrew/core" do
          tap_migrations_path.write <<~EOS
            {
              "#{formula_name}": "homebrew/core"
            }
          EOS
          formula = described_class.factory("#{tap}/#{formula_name}")
          expect(formula).to be_a(Formula)
          expect(formula.tap).to eq(CoreTap.instance)
          expect(formula.path).to eq(formula_path)
        end

        it "returns a Formula that has gone through a tap migration into another tap" do
          tap_migrations_path.write <<~EOS
            {
              "#{formula_name}": "#{another_tap}"
            }
          EOS
          formula = described_class.factory("#{tap}/#{formula_name}")
          expect(formula).to be_a(Formula)
          expect(formula.tap).to eq(another_tap)
          expect(formula.path).to eq(another_tap_formula_path)
        end
      end

      context "when loading from Tap" do
        let(:tap) { Tap.fetch("homebrew", "foo") }
        let(:another_tap) { Tap.fetch("homebrew", "bar") }
        let(:formula_path) { tap.path/"Formula/#{formula_name}.rb" }
        let(:alias_name) { "bar" }
        let(:alias_dir) { tap.alias_dir }
        let(:alias_path) { alias_dir/alias_name }

        before do
          alias_dir.mkpath
          FileUtils.ln_s formula_path, alias_path
        end

        it "returns a Formula when given a name" do
          expect(described_class.factory(formula_name)).to be_a(Formula)
        end

        it "returns a Formula from an Alias path" do
          expect(described_class.factory(alias_name)).to be_a(Formula)
        end

        it "returns a Formula from a fully qualified Alias path" do
          expect(described_class.factory("#{tap.name}/#{alias_name}")).to be_a(Formula)
        end

        it "raises an error when the Formula cannot be found" do
          expect do
            described_class.factory("#{tap}/not_existed_formula")
          end.to raise_error(TapFormulaUnavailableError)
        end

        it "returns a Formula when given a fully qualified name" do
          expect(described_class.factory("#{tap}/#{formula_name}")).to be_a(Formula)
        end

        it "raises an error if a Formula is in multiple Taps" do
          (another_tap.path/"Formula").mkpath
          (another_tap.path/"Formula/#{formula_name}.rb").write formula_content

          expect do
            described_class.factory(formula_name)
          end.to raise_error(TapFormulaAmbiguityError)
        end
      end
    end

    context "with the API" do
      def formula_json_contents(extra_items = {})
        {
          formula_name => {
            "name"                     => formula_name,
            "desc"                     => "testball",
            "homepage"                 => "https://example.com",
            "installed"                => [],
            "outdated"                 => false,
            "pinned"                   => false,
            "license"                  => "MIT",
            "revision"                 => 0,
            "version_scheme"           => 0,
            "versions"                 => { "stable" => "0.1" },
            "urls"                     => {
              "stable" => {
                "url"      => "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz",
                "tag"      => nil,
                "revision" => nil,
              },
            },
            "bottle"                   => {
              "stable" => {
                "rebuild"  => 0,
                "root_url" => "file://#{bottle_dir}",
                "files"    => {
                  Utils::Bottles.tag.to_s => {
                    "cellar" => ":any",
                    "url"    => "file://#{bottle_dir}/#{formula_name}",
                    "sha256" => "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
                  },
                },
              },
            },
            "keg_only_reason"          => {
              "reason"      => ":provided_by_macos",
              "explanation" => "",
            },
            "build_dependencies"       => ["build_dep"],
            "dependencies"             => ["dep"],
            "test_dependencies"        => ["test_dep"],
            "recommended_dependencies" => ["recommended_dep"],
            "optional_dependencies"    => ["optional_dep"],
            "uses_from_macos"          => ["uses_from_macos_dep"],
            "requirements"             => [
              {
                "name"     => "xcode",
                "cask"     => nil,
                "download" => nil,
                "version"  => "1.0",
                "contexts" => ["build"],
                "specs"    => ["stable"],
              },
            ],
            "conflicts_with"           => ["conflicting_formula"],
            "conflicts_with_reasons"   => ["it does"],
            "link_overwrite"           => ["bin/abc"],
            "linked_keg"               => nil,
            "caveats"                  => "example caveat string\n/$HOME\n$HOMEBREW_PREFIX",
            "service"                  => {
              "name"        => { macos: "custom.launchd.name", linux: "custom.systemd.name" },
              "run"         => ["$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd", "test"],
              "run_type"    => "immediate",
              "working_dir" => "/$HOME",
            },
            "ruby_source_path"         => "Formula/#{formula_name}.rb",
            "ruby_source_checksum"     => { "sha256" => "ABCDEFGHIJKLMNOPQRSTUVWXYZ" },
            "tap_git_head"             => "0000000000000000000000000000000000000000",
          }.merge(extra_items),
        }
      end

      let(:deprecate_json) do
        {
          "deprecated"                      => true,
          "deprecation_date"                => "2022-06-15",
          "deprecation_reason"              => "repo_archived",
          "deprecation_replacement_formula" => nil,
          "deprecation_replacement_cask"    => nil,
          "deprecate_args"                  => { date: "2022-06-15", because: :repo_archived },
        }
      end

      let(:disable_json) do
        {
          "disabled"                    => true,
          "disable_date"                => "2022-06-15",
          "disable_reason"              => "requires something else",
          "disable_replacement_formula" => nil,
          "disable_replacement_cask"    => nil,
          "disable_args"                => { date: "2022-06-15", because: "requires something else" },
        }
      end

      let(:future_date) { Date.today + 365 }

      let(:deprecate_future_json) do
        {
          "deprecated"                      => true,
          "deprecation_date"                => future_date.to_s,
          "deprecation_reason"              => nil,
          "deprecation_replacement_formula" => nil,
          "deprecation_replacement_cask"    => nil,
          "deprecate_args"                  => {
            date:             future_date.to_s,
            because:          :repo_archived,
            replacement_cask: "bar",
          },
        }
      end

      let(:disable_future_json) do
        {
          "deprecated"                      => true,
          "deprecation_date"                => nil,
          "deprecation_reason"              => "requires something else",
          "deprecation_replacement_formula" => "foo",
          "deprecation_replacement_cask"    => nil,
          "deprecate_args"                  => nil,
          "disabled"                        => false,
          "disable_date"                    => future_date.to_s,
          "disable_reason"                  => nil,
          "disable_replacement_formula"     => nil,
          "disable_replacement_cask"        => nil,
          "disable_args"                    => {
            date:                future_date.to_s,
            because:             "requires something else",
            replacement_formula: "foo",
          },
        }
      end

      let(:variations_json) do
        {
          "variations" => {
            Utils::Bottles.tag.to_s => {
              "dependencies" => ["dep", "variations_dep"],
            },
          },
        }
      end

      let(:older_macos_variations_json) do
        {
          "variations" => {
            Utils::Bottles.tag.to_s => {
              "dependencies" => ["uses_from_macos_dep"],
            },
          },
        }
      end

      let(:linux_variations_json) do
        {
          "variations" => {
            "x86_64_linux" => {
              "dependencies" => ["dep"],
            },
          },
        }
      end

      before do
        # avoid unnecessary network calls
        allow(Homebrew::API::Formula).to receive_messages(all_aliases: {}, all_renames: {})
        allow(CoreTap.instance).to receive(:tap_migrations).and_return({})
        allow(CoreCaskTap.instance).to receive(:tap_migrations).and_return({})

        # don't try to load/fetch gcc/glibc
        allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)
      end

      it "returns a Formula when given a name" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)

        expect(formula.keg_only_reason.reason).to eq :provided_by_macos
        expect(formula.declared_deps.count).to eq 6
        if OS.mac?
          expect(formula.deps.count).to eq 5
        else
          expect(formula.deps.count).to eq 6
        end

        expect(formula.requirements.count).to eq 1
        req = formula.requirements.first
        expect(req).to be_an_instance_of XcodeRequirement
        expect(req.version).to eq "1.0"
        expect(req.tags).to eq [:build]

        expect(formula.conflicts.map(&:name)).to include "conflicting_formula"
        expect(formula.conflicts.map(&:reason)).to include "it does"
        expect(formula.class.link_overwrite_paths).to include "bin/abc"

        expect(formula.caveats).to eq "example caveat string\n#{Dir.home}\n#{HOMEBREW_PREFIX}"

        expect(formula).to be_a_service
        expect(formula.service.command).to eq(["#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd", "test"])
        expect(formula.service.run_type).to eq(:immediate)
        expect(formula.service.working_dir).to eq(Dir.home)
        expect(formula.plist_name).to eq("custom.launchd.name")
        expect(formula.service_name).to eq("custom.systemd.name")

        expect(formula.ruby_source_checksum.hexdigest).to eq("abcdefghijklmnopqrstuvwxyz")

        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a Formula that can regenerate its JSON API" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.loaded_from_api?).to be true

        expected_hash = formula_json_contents[formula_name]
        expect(formula.to_hash_with_variations).to eq(expected_hash)
      end

      it "returns a deprecated Formula when given a name" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents(deprecate_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.deprecated?).to be true
        expect(formula.deprecation_date).to eq(Date.parse("2022-06-15"))
        expect(formula.deprecation_reason).to eq :repo_archived
        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a disabled Formula when given a name" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents(disable_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.disabled?).to be true
        expect(formula.disable_date).to eq(Date.parse("2022-06-15"))
        expect(formula.disable_reason).to eq("requires something else")
        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a future-deprecated Formula when given a name" do
        contents = formula_json_contents(deprecate_future_json)
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return contents

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.deprecated?).to be false
        expect(formula.deprecation_date).to eq(future_date)
        expect(formula.deprecation_reason).to be_nil
        expect(formula.deprecation_replacement_formula).to be_nil
        expect(formula.deprecation_replacement_cask).to be_nil
        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a future-disabled Formula when given a name" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents(disable_future_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.deprecated?).to be true
        expect(formula.deprecation_date).to be_nil
        expect(formula.deprecation_reason).to eq("requires something else")
        expect(formula.deprecation_replacement_formula).to eq("foo")
        expect(formula.deprecation_replacement_cask).to be_nil
        expect(formula.disabled?).to be false
        expect(formula.disable_date).to eq(future_date)
        expect(formula.disable_reason).to be_nil
        expect(formula.disable_replacement_formula).to be_nil
        expect(formula.disable_replacement_cask).to be_nil
        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a Formula with variations when given a name", :needs_macos do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents(variations_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.declared_deps.count).to eq 7
        expect(formula.deps.count).to eq 6
        expect(formula.deps.map(&:name).include?("variations_dep")).to be true
        expect(formula.deps.map(&:name).include?("uses_from_macos_dep")).to be false
      end

      it "returns a Formula without duplicated deps and uses_from_macos with variations on Linux", :needs_linux do
        allow(Homebrew::API::Formula)
          .to receive(:all_formulae).and_return formula_json_contents(linux_variations_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.declared_deps.count).to eq 6
        expect(formula.deps.count).to eq 6
        expect(formula.deps.map(&:name).include?("uses_from_macos_dep")).to be true
      end

      it "returns a Formula with the correct uses_from_macos dep on older macOS", :needs_macos do
        allow(Homebrew::API::Formula)
          .to receive(:all_formulae).and_return formula_json_contents(older_macos_variations_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.declared_deps.count).to eq 6
        expect(formula.deps.count).to eq 5
        expect(formula.deps.map(&:name).include?("uses_from_macos_dep")).to be true
      end

      context "with core tap migration renames" do
        let(:foo_tap) { Tap.fetch("homebrew", "foo") }

        before do
          allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents
          foo_tap.path.mkpath
        end

        after do
          FileUtils.rm_rf foo_tap.path
        end

        it "returns the tap migration rename by old formula_name" do
          old_formula_name = "#{formula_name}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_formula_name}": "homebrew/core/#{formula_name}" }
          JSON

          loader = described_class::FromNameLoader.try_new(old_formula_name)
          expect(loader).to be_a(described_class::FromAPILoader)
          expect(loader.name).to eq formula_name
          expect(loader.path).not_to exist
        end

        it "returns the tap migration rename by old full name" do
          old_formula_name = "#{formula_name}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_formula_name}": "homebrew/core/#{formula_name}" }
          JSON

          loader = described_class::FromTapLoader.try_new("#{foo_tap}/#{old_formula_name}")
          expect(loader).to be_a(described_class::FromAPILoader)
          expect(loader.name).to eq formula_name
          expect(loader.path).not_to exist
        end
      end
    end

    context "when passed a URL" do
      it "raises an error when given an https URL" do
        expect do
          described_class.factory("https://brew.sh/foo.rb")
        end.to raise_error(UnsupportedInstallationMethod)
      end

      it "raises an error when given a bottle URL" do
        expect do
          described_class.factory("https://brew.sh/foo-1.0.arm64_catalina.bottle.tar.gz")
        end.to raise_error(UnsupportedInstallationMethod)
      end

      it "raises an error when given an ftp URL" do
        expect do
          described_class.factory("ftp://brew.sh/foo.rb")
        end.to raise_error(UnsupportedInstallationMethod)
      end

      it "raises an error when given an sftp URL" do
        expect do
          described_class.factory("sftp://brew.sh/foo.rb")
        end.to raise_error(UnsupportedInstallationMethod)
      end

      it "does not raise an error when given a file URL", :needs_utils_curl do
        expect do
          described_class.factory("file://#{TEST_FIXTURE_DIR}/testball.rb")
        end.not_to raise_error
      end
    end

    context "when passed ref with spaces" do
      it "raises a FormulaUnavailableError error" do
        expect do
          described_class.factory("foo bar")
        end.to raise_error(FormulaUnavailableError)
      end
    end
  end

  specify "::from_contents" do
    expect(described_class.from_contents(formula_name, formula_path, formula_content)).to be_a(Formula)
  end

  describe "::to_rack" do
    alias_matcher :exist, :be_exist

    let(:rack_path) { HOMEBREW_CELLAR/formula_name }

    context "when the Rack does not exist" do
      it "returns the Rack" do
        expect(described_class.to_rack(formula_name)).to eq(rack_path)
      end
    end

    context "when the Rack exists" do
      before do
        rack_path.mkpath
      end

      it "returns the Rack" do
        expect(described_class.to_rack(formula_name)).to eq(rack_path)
      end
    end

    it "raises an error if the Formula is not available" do
      expect do
        described_class.to_rack("a/b/#{formula_name}")
      end.to raise_error(TapFormulaUnavailableError)
    end
  end

  describe "::core_path" do
    it "returns the path to a Formula in the core tap" do
      name = "foo-bar"
      expect(described_class.core_path(name))
        .to eq(Pathname.new("#{HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-core/Formula/#{name}.rb"))
    end
  end

  describe "::loader_for" do
    context "when given a relative path with two slashes" do
      it "returns a `FromPathLoader`" do
        mktmpdir.cd do
          FileUtils.mkdir "Formula"
          FileUtils.touch "Formula/gcc.rb"
          expect(described_class.loader_for("./Formula/gcc.rb")).to be_a Formulary::FromPathLoader
        end
      end
    end

    context "when given a tapped name" do
      it "returns a `FromTapLoader`", :no_api do
        expect(described_class.loader_for("homebrew/core/gcc")).to be_a Formulary::FromTapLoader
      end
    end

    context "when not using the API", :no_api do
      context "when a formula is migrated" do
        let(:token) { "foo" }

        let(:core_tap) { CoreTap.instance }
        let(:core_cask_tap) { CoreCaskTap.instance }

        let(:tap_migrations) do
          {
            token => new_tap.name,
          }
        end

        before do
          old_tap.path.mkpath
          new_tap.path.mkpath
          (old_tap.path/"tap_migrations.json").write tap_migrations.to_json
        end

        context "to a cask in the default tap" do
          let(:old_tap) { core_tap }
          let(:new_tap) { core_cask_tap }

          let(:cask_file) { new_tap.cask_dir/"#{token}.rb" }

          before do
            new_tap.cask_dir.mkpath
            FileUtils.touch cask_file
          end

          it "warn only once" do
            expect do
              described_class.loader_for(token)
            end.to output(
              a_string_including("Warning: Formula #{token} was renamed to #{new_tap}/#{token}.").once,
            ).to_stderr
          end
        end

        context "to the default tap" do
          let(:old_tap) { core_cask_tap }
          let(:new_tap) { core_tap }

          let(:formula_file) { new_tap.formula_dir/"#{token}.rb" }

          before do
            new_tap.formula_dir.mkpath
            FileUtils.touch formula_file
          end

          it "does not warn when loading the short token" do
            expect do
              described_class.loader_for(token)
            end.not_to output.to_stderr
          end

          it "does not warn when loading the full token in the default tap" do
            expect do
              described_class.loader_for("#{new_tap}/#{token}")
            end.not_to output.to_stderr
          end

          it "warns when loading the full token in the old tap" do
            expect do
              described_class.loader_for("#{old_tap}/#{token}")
            end.to output(
              a_string_including("Formula #{old_tap}/#{token} was renamed to #{token}.").once,
            ).to_stderr
          end

          # FIXME
          # context "when there is an infinite tap migration loop" do
          #   before do
          #     (new_tap.path/"tap_migrations.json").write({
          #       token => old_tap.name,
          #     }.to_json)
          #   end
          #
          #   it "stops recursing" do
          #     expect do
          #       described_class.loader_for("#{new_tap}/#{token}")
          #     end.not_to output.to_stderr
          #   end
          # end
        end

        context "to a third-party tap" do
          let(:old_tap) { Tap.fetch("another", "foo") }
          let(:new_tap) { Tap.fetch("another", "bar") }
          let(:formula_file) { new_tap.formula_dir/"#{token}.rb" }

          before do
            new_tap.formula_dir.mkpath
            FileUtils.touch formula_file
          end

          after do
            FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"another"
          end

          # FIXME
          # It would be preferable not to print a warning when installing with the short token
          it "warns when loading the short token" do
            expect do
              described_class.loader_for(token)
            end.to output(
              a_string_including("Formula #{old_tap}/#{token} was renamed to #{new_tap}/#{token}.").once,
            ).to_stderr
          end

          it "does not warn when loading the full token in the new tap" do
            expect do
              described_class.loader_for("#{new_tap}/#{token}")
            end.not_to output.to_stderr
          end

          it "warns when loading the full token in the old tap" do
            expect do
              described_class.loader_for("#{old_tap}/#{token}")
            end.to output(
              a_string_including("Formula #{old_tap}/#{token} was renamed to #{new_tap}/#{token}.").once,
            ).to_stderr
          end
        end
      end
    end
  end
end
# rubocop:enable RSpec/AggregateExamples
