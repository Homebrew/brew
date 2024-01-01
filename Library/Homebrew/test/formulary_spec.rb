# frozen_string_literal: true

require "formula"
require "formula_installer"
require "utils/bottles"

describe Formulary do
  let(:formula_name) { "testball_bottle" }
  let(:formula_path) { CoreTap.new.new_formula_path(formula_name) }
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
      before { CoreTap.instance.clear_cache }

      let(:formula_name) { "testball_sharded" }
      let(:formula_path) do
        core_tap = CoreTap.new
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
        end.to raise_error(FormulaClassUnavailableError)
      end
    end

    it "returns a Formula when given a path" do
      expect(described_class.factory(formula_path)).to be_a(Formula)
    end

    it "returns a Formula when given a URL" do
      formula = described_class.factory("file://#{formula_path}")
      expect(formula).to be_a(Formula)
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

      let(:alias_dir) { CoreTap.instance.alias_dir.tap(&:mkpath) }
      let(:alias_path) { alias_dir/"foo" }

      before do
        alias_dir.mkpath
        FileUtils.ln_s formula_path, alias_path
      end

      it "returns a Formula" do
        expect(formula).to be_a(Formula)
      end

      it "calling #alias_path on the returned Formula returns the alias path" do
        expect(formula.alias_path).to eq(alias_path.to_s)
      end
    end

    context "with installed Formula" do
      before do
        allow(described_class).to receive(:loader_for).and_call_original

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
      let(:tap) { Tap.new("homebrew", "foo") }
      let(:another_tap) { Tap.new("homebrew", "bar") }
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
      let(:tap) { Tap.new("homebrew", "foo") }
      let(:another_tap) { Tap.new("homebrew", "bar") }
      let(:formula_path) { tap.path/"Formula/#{formula_name}.rb" }

      it "returns a Formula when given a name" do
        expect(described_class.factory(formula_name)).to be_a(Formula)
      end

      it "returns a Formula from an Alias path" do
        alias_dir = tap.path/"Aliases"
        alias_dir.mkpath
        FileUtils.ln_s formula_path, alias_dir/"bar"
        expect(described_class.factory("bar")).to be_a(Formula)
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

    context "when loading from the API" do
      def formula_json_contents(extra_items = {})
        {
          formula_name => {
            "desc"                     => "testball",
            "homepage"                 => "https://example.com",
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
              },
            ],
            "conflicts_with"           => ["conflicting_formula"],
            "conflicts_with_reasons"   => ["it does"],
            "link_overwrite"           => ["bin/abc"],
            "caveats"                  => "example caveat string\n/$HOME\n$HOMEBREW_PREFIX",
            "service"                  => {
              "name"        => { macos: "custom.launchd.name", linux: "custom.systemd.name" },
              "run"         => ["$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd", "test"],
              "run_type"    => "immediate",
              "working_dir" => "/$HOME",
            },
          }.merge(extra_items),
        }
      end

      let(:deprecate_json) do
        {
          "deprecation_date"   => "2022-06-15",
          "deprecation_reason" => "repo_archived",
        }
      end

      let(:disable_json) do
        {
          "disable_date"   => "2022-06-15",
          "disable_reason" => "requires something else",
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
              "dependencies" => ["dep", "uses_from_macos_dep"],
            },
          },
        }
      end

      before do
        allow(described_class).to receive(:loader_for).and_return(described_class::FormulaAPILoader.new(formula_name))

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

        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a deprecated Formula when given a name" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents(deprecate_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.deprecated?).to be true
        expect do
          formula.install
        end.to raise_error("Cannot build from source from abstract formula.")
      end

      it "returns a disabled Formula when given a name" do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return formula_json_contents(disable_json)

        formula = described_class.factory(formula_name)
        expect(formula).to be_a(Formula)
        expect(formula.disabled?).to be true
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

  describe "::convert_to_string_or_symbol" do
    it "returns the original string if it doesn't start with a colon" do
      expect(described_class.convert_to_string_or_symbol("foo")).to eq "foo"
    end

    it "returns a symbol if the original string starts with a colon" do
      expect(described_class.convert_to_string_or_symbol(":foo")).to eq :foo
    end
  end
end
