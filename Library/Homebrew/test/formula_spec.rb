# frozen_string_literal: true

require "test/support/fixtures/testball"
require "formula"

RSpec.describe Formula do
  alias_matcher :follow_installed_alias, :be_follow_installed_alias
  alias_matcher :have_any_version_installed, :be_any_version_installed
  alias_matcher :need_migration, :be_migration_needed

  alias_matcher :have_changed_installed_alias_target, :be_installed_alias_target_changed
  alias_matcher :supersede_an_installed_formula, :be_supersedes_an_installed_formula
  alias_matcher :have_changed_alias, :be_alias_changed

  alias_matcher :have_option_defined, :be_option_defined
  alias_matcher :have_post_install_defined, :be_post_install_defined
  alias_matcher :have_test_defined, :be_test_defined
  alias_matcher :pour_bottle, :be_pour_bottle

  describe "::new" do
    let(:klass) do
      Class.new(described_class) do
        url "https://brew.sh/foo-1.0.tar.gz"
      end
    end

    let(:name) { "formula_name" }
    let(:path) { Formulary.core_path(name) }
    let(:spec) { :stable }
    let(:alias_name) { "baz@1" }
    let(:alias_path) { CoreTap.instance.alias_dir/alias_name }
    let(:f) { klass.new(name, path, spec) }
    let(:f_alias) { klass.new(name, path, spec, alias_path:) }

    specify "formula instantiation" do
      expect(f.name).to eq(name)
      expect(f.specified_name).to eq(name)
      expect(f.full_name).to eq(name)
      expect(f.full_specified_name).to eq(name)
      expect(f.path).to eq(path)
      expect(f.alias_path).to be_nil
      expect(f.alias_name).to be_nil
      expect(f.full_alias_name).to be_nil
      expect(f.specified_path).to eq(path)
      [:build, :test, :postinstall].each { |phase| expect(f.network_access_allowed?(phase)).to be(true) }
      expect { klass.new }.to raise_error(ArgumentError)
    end

    specify "formula instantiation with alias" do
      expect(f_alias.name).to eq(name)
      expect(f_alias.full_name).to eq(name)
      expect(f_alias.path).to eq(path)
      expect(f_alias.alias_path).to eq(alias_path)
      expect(f_alias.alias_name).to eq(alias_name)
      expect(f_alias.specified_name).to eq(alias_name)
      expect(f_alias.specified_path).to eq(Pathname(alias_path))
      expect(f_alias.full_alias_name).to eq(alias_name)
      expect(f_alias.full_specified_name).to eq(alias_name)
      [:build, :test, :postinstall].each { |phase| expect(f_alias.network_access_allowed?(phase)).to be(true) }
      expect { klass.new }.to raise_error(ArgumentError)
    end

    specify "formula instantiation without a subclass" do
      expect { described_class.new(name, path, spec) }
        .to raise_error(RuntimeError, "Do not call `Formula.new' directly without a subclass.")
    end

    context "when in a Tap" do
      let(:tap) { Tap.fetch("foo", "bar") }
      let(:path) { (tap.path/"Formula/#{name}.rb") }
      let(:full_name) { "#{tap.user}/#{tap.repository}/#{name}" }
      let(:full_alias_name) { "#{tap.user}/#{tap.repository}/#{alias_name}" }

      specify "formula instantiation" do
        expect(f.name).to eq(name)
        expect(f.specified_name).to eq(name)
        expect(f.full_name).to eq(full_name)
        expect(f.full_specified_name).to eq(full_name)
        expect(f.path).to eq(path)
        expect(f.alias_path).to be_nil
        expect(f.alias_name).to be_nil
        expect(f.full_alias_name).to be_nil
        expect(f.specified_path).to eq(path)
        expect { klass.new }.to raise_error(ArgumentError)
      end

      specify "formula instantiation with alias" do
        expect(f_alias.name).to eq(name)
        expect(f_alias.full_name).to eq(full_name)
        expect(f_alias.path).to eq(path)
        expect(f_alias.alias_path).to eq(alias_path)
        expect(f_alias.alias_name).to eq(alias_name)
        expect(f_alias.specified_name).to eq(alias_name)
        expect(f_alias.specified_path).to eq(Pathname(alias_path))
        expect(f_alias.full_alias_name).to eq(full_alias_name)
        expect(f_alias.full_specified_name).to eq(full_alias_name)
        expect { klass.new }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#follow_installed_alias?" do
    let(:f) do
      formula do
        url "foo-1.0"
      end
    end

    it "returns true by default" do
      expect(f).to follow_installed_alias
    end

    it "can be set to true" do
      f.follow_installed_alias = true
      expect(f).to follow_installed_alias
    end

    it "can be set to false" do
      f.follow_installed_alias = false
      expect(f).not_to follow_installed_alias
    end
  end

  describe "#versioned_formula?" do
    let(:f) do
      formula "foo" do
        url "foo-1.0"
      end
    end

    let(:f2) do
      formula "foo@2.0" do
        url "foo-2.0"
      end
    end

    it "returns true for @-versioned formulae" do
      expect(f2.versioned_formula?).to be true
    end

    it "returns false for non-@-versioned formulae" do
      expect(f.versioned_formula?).to be false
    end
  end

  describe "#versioned_formulae" do
    let(:f) do
      formula "foo" do
        url "foo-1.0"
      end
    end

    let(:f2) do
      formula "foo@2.0" do
        url "foo-2.0"
      end
    end

    before do
      # don't try to load/fetch gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      allow(Formulary).to receive(:load_formula_from_path).with(f2.name, f2.path).and_return(f2)
      allow(Formulary).to receive(:factory).with(f2.name).and_return(f2)
      allow(f).to receive(:versioned_formulae_names).and_return([f2.name])
    end

    it "returns array with versioned formulae" do
      FileUtils.touch f.path
      FileUtils.touch f2.path
      expect(f.versioned_formulae).to eq [f2]
    end

    it "returns empty array for non-@-versioned formulae" do
      FileUtils.touch f.path
      FileUtils.touch f2.path
      expect(f2.versioned_formulae).to be_empty
    end
  end

  example "installed alias with core" do
    f = formula do
      url "foo-1.0"
    end

    build_values_with_no_installed_alias = [
      BuildOptions.new(Options.new, f.options),
      Tab.new(source: { "path" => f.path.to_s }),
    ]
    build_values_with_no_installed_alias.each do |build|
      f.build = build
      expect(f.installed_alias_path).to be_nil
      expect(f.installed_alias_name).to be_nil
      expect(f.full_installed_alias_name).to be_nil
      expect(f.installed_specified_name).to eq(f.name)
      expect(f.full_installed_specified_name).to eq(f.name)
    end

    alias_name = "bar"
    alias_path = CoreTap.instance.alias_dir/alias_name
    CoreTap.instance.alias_dir.mkpath
    FileUtils.ln_sf f.path, alias_path

    f.build = Tab.new(source: { "path" => alias_path.to_s })

    expect(f.installed_alias_path).to eq(alias_path)
    expect(f.installed_alias_name).to eq(alias_name)
    expect(f.full_installed_alias_name).to eq(alias_name)
    expect(f.installed_specified_name).to eq(alias_name)
    expect(f.full_installed_specified_name).to eq(alias_name)
  end

  example "installed alias with tap" do
    tap = Tap.fetch("user", "repo")
    name = "foo"
    path = tap.path/"Formula/#{name}.rb"
    f = formula(name, path:) do
      url "foo-1.0"
    end

    build_values_with_no_installed_alias = [
      BuildOptions.new(Options.new, f.options),
      Tab.new(source: { "path" => f.path.to_s }),
    ]
    build_values_with_no_installed_alias.each do |build|
      f.build = build
      expect(f.installed_alias_path).to be_nil
      expect(f.installed_alias_name).to be_nil
      expect(f.full_installed_alias_name).to be_nil
      expect(f.installed_specified_name).to eq(f.name)
      expect(f.full_installed_specified_name).to eq(f.full_name)
    end

    alias_name = "bar"
    alias_path = tap.alias_dir/alias_name
    full_alias_name = "#{tap.user}/#{tap.repository}/#{alias_name}"
    tap.alias_dir.mkpath
    FileUtils.ln_sf f.path, alias_path

    f.build = Tab.new(source: { "path" => alias_path.to_s })

    expect(f.installed_alias_path).to eq(alias_path)
    expect(f.installed_alias_name).to eq(alias_name)
    expect(f.full_installed_alias_name).to eq(full_alias_name)
    expect(f.installed_specified_name).to eq(alias_name)
    expect(f.full_installed_specified_name).to eq(full_alias_name)

    FileUtils.rm_rf HOMEBREW_LIBRARY/"Taps/user"
  end

  specify "#prefix" do
    f = Testball.new
    expect(f.prefix).to eq(HOMEBREW_CELLAR/f.name/"0.1")
    expect(f.prefix).to be_a(Pathname)
  end

  example "revised prefix" do
    f = Class.new(Testball) { revision(1) }.new
    expect(f.prefix).to eq(HOMEBREW_CELLAR/f.name/"0.1_1")
  end

  specify "#any_version_installed?" do
    f = formula do
      url "foo"
      version "1.0"
    end

    expect(f).not_to have_any_version_installed

    prefix = HOMEBREW_CELLAR/f.name/"0.1"
    prefix.mkpath
    FileUtils.touch prefix/AbstractTab::FILENAME

    expect(f).to have_any_version_installed
  end

  specify "#migration_needed" do
    f = Testball.new("newname")
    f.instance_variable_set(:@oldnames, ["oldname"])
    f.instance_variable_set(:@tap, CoreTap.instance)

    oldname_prefix = (HOMEBREW_CELLAR/"oldname/2.20")
    newname_prefix = (HOMEBREW_CELLAR/"newname/2.10")

    oldname_prefix.mkpath
    oldname_tab = Tab.empty
    oldname_tab.tabfile = oldname_prefix/AbstractTab::FILENAME
    oldname_tab.write

    expect(f).not_to need_migration

    oldname_tab.tabfile.unlink
    oldname_tab.source["tap"] = "homebrew/core"
    oldname_tab.write

    expect(f).to need_migration

    newname_prefix.mkpath

    expect(f).not_to need_migration
  end

  describe "#latest_version_installed?" do
    let(:f) { Testball.new }

    it "returns false if the #latest_installed_prefix is not a directory" do
      allow(f).to receive(:latest_installed_prefix).and_return(instance_double(Pathname, directory?: false))
      expect(f).not_to be_latest_version_installed
    end

    it "returns false if the #latest_installed_prefix does not have children" do
      allow(f).to receive(:latest_installed_prefix)
        .and_return(instance_double(Pathname, directory?: true, children: []))
      expect(f).not_to be_latest_version_installed
    end

    it "returns true if the #latest_installed_prefix has children" do
      allow(f).to receive(:latest_installed_prefix)
        .and_return(instance_double(Pathname, directory?: true, children: [double]))
      expect(f).to be_latest_version_installed
    end
  end

  describe "#latest_installed_prefix" do
    let(:f) do
      formula do
        url "foo"
        version "1.9"
        head "foo"
      end
    end

    let(:stable_prefix) { HOMEBREW_CELLAR/f.name/f.version }
    let(:head_prefix) { HOMEBREW_CELLAR/f.name/f.head.version }

    it "is the same as #prefix by default" do
      expect(f.latest_installed_prefix).to eq(f.prefix)
    end

    it "returns the stable prefix if it is installed" do
      stable_prefix.mkpath
      expect(f.latest_installed_prefix).to eq(stable_prefix)
    end

    it "returns the head prefix if it is installed" do
      head_prefix.mkpath
      expect(f.latest_installed_prefix).to eq(head_prefix)
    end

    it "returns the stable prefix if head is outdated" do
      head_prefix.mkpath

      tab = Tab.empty
      tab.tabfile = head_prefix/AbstractTab::FILENAME
      tab.source["versions"] = { "stable" => "1.0" }
      tab.write

      expect(f.latest_installed_prefix).to eq(stable_prefix)
    end

    it "returns the head prefix if the active specification is :head" do
      f.active_spec = :head
      expect(f.latest_installed_prefix).to eq(head_prefix)
    end
  end

  describe "#latest_head_prefix" do
    let(:f) { Testball.new }

    it "returns the latest head prefix" do
      stamps_with_revisions = [
        [111111, 1],
        [222222, 0],
        [222222, 1],
        [222222, 2],
      ]

      stamps_with_revisions.each do |stamp, revision|
        version = "HEAD-#{stamp}"
        version = "#{version}_#{revision}" unless revision.zero?

        prefix = f.rack/version
        prefix.mkpath

        tab = Tab.empty
        tab.tabfile = prefix/AbstractTab::FILENAME
        tab.source_modified_time = stamp
        tab.write
      end

      prefix = HOMEBREW_CELLAR/f.name/"HEAD-222222_2"

      expect(f.latest_head_prefix).to eq(prefix)
    end
  end

  specify "equality" do
    x = Testball.new
    y = Testball.new

    expect(x).to eq(y)
    expect(x).to eql(y)
    expect(x.hash).to eq(y.hash)
  end

  specify "inequality" do
    x = Testball.new("foo")
    y = Testball.new("bar")

    expect(x).not_to eq(y)
    expect(x).not_to eql(y)
    expect(x.hash).not_to eq(y.hash)
  end

  specify "comparison with non formula objects does not raise" do
    expect(Object.new).not_to eq(Testball.new)
  end

  specify "#<=>" do
    expect(Testball.new <=> Object.new).to be_nil
  end

  describe "#installed_alias_path" do
    example "alias paths with build options" do
      alias_path = (CoreTap.instance.alias_dir/"another_name")

      f = formula(alias_path:) do
        url "foo-1.0"
      end
      f.build = BuildOptions.new(Options.new, f.options)

      expect(f.alias_path).to eq(alias_path)
      expect(f.installed_alias_path).to be_nil
    end

    example "alias paths with tab with non alias source path" do
      alias_path = (CoreTap.instance.alias_dir/"another_name")
      source_path = CoreTap.instance.new_formula_path("another_other_name")

      f = formula(alias_path:) do
        url "foo-1.0"
      end
      f.build = Tab.new(source: { "path" => source_path.to_s })

      expect(f.alias_path).to eq(alias_path)
      expect(f.installed_alias_path).to be_nil
    end

    example "alias paths with tab with alias source path" do
      alias_path = (CoreTap.instance.alias_dir/"another_name")
      source_path = (CoreTap.instance.alias_dir/"another_other_name")

      f = formula(alias_path:) do
        url "foo-1.0"
      end
      f.build = Tab.new(source: { "path" => source_path.to_s })
      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf f.path, source_path

      expect(f.alias_path).to eq(alias_path)
      expect(f.installed_alias_path).to eq(source_path)
    end
  end

  describe "::inreplace" do
    specify "raises build error on failure" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
      end

      expect { f.inreplace([]) }.to raise_error(BuildError)
    end

    specify "replaces text in file" do
      file = Tempfile.new("test")
      File.binwrite(file, <<~EOS)
        ab
        bc
        cd
      EOS
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
      end
      f.inreplace(file.path) do |s|
        s.gsub!("bc", "yz")
      end
      expect(File.binread(file)).to eq <<~EOS
        ab
        yz
        cd
      EOS
    end
  end

  describe "::installed_with_alias_path" do
    specify "with alias path with nil" do
      expect(described_class.installed_with_alias_path(nil)).to be_empty
    end

    specify "with alias path with a path" do
      alias_path = CoreTap.instance.alias_dir/"alias"
      different_alias_path = CoreTap.instance.alias_dir/"another_alias"

      formula_with_alias = formula "foo" do
        url "foo-1.0"
      end
      formula_with_alias.build = Tab.empty
      formula_with_alias.build.source["path"] = alias_path.to_s

      formula_without_alias = formula "bar" do
        url "bar-1.0"
      end
      formula_without_alias.build = Tab.empty
      formula_without_alias.build.source["path"] = formula_without_alias.path.to_s

      formula_with_different_alias = formula "baz" do
        url "baz-1.0"
      end
      formula_with_different_alias.build = Tab.empty
      formula_with_different_alias.build.source["path"] = different_alias_path.to_s

      formulae = [
        formula_with_alias,
        formula_without_alias,
        formula_with_different_alias,
      ]

      allow(described_class).to receive(:installed).and_return(formulae)

      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf formula_with_alias.path, alias_path

      expect(described_class.installed_with_alias_path(alias_path))
        .to eq([formula_with_alias])
    end
  end

  specify "spec integration" do
    f = formula do
      homepage "https://brew.sh"

      url "https://brew.sh/test-0.1.tbz"
      mirror "https://example.org/test-0.1.tbz"
      sha256 TEST_SHA256

      head "https://brew.sh/test.git", tag: "foo"
    end

    expect(f.homepage).to eq("https://brew.sh")
    expect(f.version).to eq(Version.new("0.1"))
    expect(f).to be_stable
    expect(f.stable.version).to eq(Version.new("0.1"))
    expect(f.head.version).to eq(Version.new("HEAD"))
  end

  specify "#active_spec=" do
    f = formula do
      url "foo"
      version "1.0"
      revision 1
    end

    expect(f.active_spec_sym).to eq(:stable)
    expect(f.send(:active_spec)).to eq(f.stable)
    expect(f.pkg_version.to_s).to eq("1.0_1")

    expect { f.active_spec = :head }.to raise_error(FormulaSpecificationError)
  end

  specify "class specs are always initialized" do
    f = formula do
      url "foo-1.0"
    end

    expect(f.class.stable).to be_a(SoftwareSpec)
    expect(f.class.head).to be_a(SoftwareSpec)
  end

  specify "instance specs have different references" do
    f = Testball.new
    f2 = Testball.new

    expect(f.stable.owner).to equal(f)
    expect(f2.stable.owner).to equal(f2)
  end

  specify "incomplete instance specs are not accessible" do
    f = formula do
      url "foo-1.0"
    end

    expect(f.head).to be_nil
  end

  it "honors attributes declared before specs" do
    f = formula do
      url "foo-1.0"

      depends_on "foo"
    end

    expect(f.class.stable.deps.first.name).to eq("foo")
    expect(f.class.head.deps.first.name).to eq("foo")
  end

  describe "#pkg_version" do
    specify "simple version" do
      f = formula do
        url "foo-1.0.bar"
      end

      expect(f.pkg_version).to eq(PkgVersion.parse("1.0"))
    end

    specify "version with revision" do
      f = formula do
        url "foo-1.0.bar"
        revision 1
      end

      expect(f.pkg_version).to eq(PkgVersion.parse("1.0_1"))
    end

    specify "head uses revisions" do
      f = formula "test", spec: :head do
        url "foo-1.0.bar"
        revision 1

        head "foo"
      end

      expect(f.pkg_version).to eq(PkgVersion.parse("HEAD_1"))
    end
  end

  specify "#update_head_version" do
    f = formula do
      head "foo", using: :git
    end

    cached_location = f.head.downloader.cached_location
    cached_location.mkpath
    cached_location.cd do
      FileUtils.touch "LICENSE"

      system("git", "init")
      system("git", "add", "--all")
      system("git", "commit", "-m", "Initial commit")
    end

    f.update_head_version

    expect(f.head.version).to eq(Version.new("HEAD-5658946"))
  end

  specify "#desc" do
    f = formula do
      desc "a formula"

      url "foo-1.0"
    end

    expect(f.desc).to eq("a formula")
  end

  specify "#post_install_defined?" do
    f1 = formula do
      url "foo-1.0"

      def post_install
        # do nothing
      end
    end

    f2 = formula do
      url "foo-1.0"
    end

    expect(f1).to have_post_install_defined
    expect(f2).not_to have_post_install_defined
  end

  specify "test fixtures" do
    f1 = formula do
      url "foo-1.0"
    end

    expect(f1.test_fixtures("foo")).to eq(Pathname.new("#{HOMEBREW_LIBRARY_PATH}/test/support/fixtures/foo"))
  end

  specify "#livecheck" do
    f = formula do
      url "https://brew.sh/test-1.0.tbz"
      livecheck do
        skip "foo"
        url "https://brew.sh/test/releases"
        regex(/test-v?(\d+(?:\.\d+)+)\.t/i)
      end
    end

    expect(f.livecheck.skip?).to be true
    expect(f.livecheck.skip_msg).to eq("foo")
    expect(f.livecheck.url).to eq("https://brew.sh/test/releases")
    expect(f.livecheck.regex).to eq(/test-v?(\d+(?:\.\d+)+)\.t/i)
  end

  describe "#livecheck_defined?" do
    specify "no `livecheck` block defined" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
      end

      expect(f.livecheck_defined?).to be false
    end

    specify "`livecheck` block defined" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
        livecheck do
          regex(/test-v?(\d+(?:\.\d+)+)\.t/i)
        end
      end

      expect(f.livecheck_defined?).to be true
    end

    specify "livecheck references Formula URL" do
      f = formula do
        homepage "https://brew.sh/test"

        url "https://brew.sh/test-1.0.tbz"
        livecheck do
          url :homepage
          regex(/test-v?(\d+(?:\.\d+)+)\.t/i)
        end
      end

      expect(f.livecheck.url).to eq(:homepage)
    end
  end

  describe "#service" do
    specify "no service defined" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
      end

      expect(f.service.to_hash).to eq({})
    end

    specify "service complicated" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"

        service do
          run [opt_bin/"beanstalkd"]
          run_type :immediate
          error_log_path var/"log/beanstalkd.error.log"
          log_path var/"log/beanstalkd.log"
          working_dir var
          keep_alive true
        end
      end
      expect(f.service.to_hash.keys)
        .to contain_exactly(:run, :run_type, :error_log_path, :log_path, :working_dir, :keep_alive)
    end

    specify "service uses simple run" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
        service do
          run opt_bin/"beanstalkd"
        end
      end

      expect(f.service.to_hash.keys).to contain_exactly(:run, :run_type)
    end

    specify "service with only custom names" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
        service do
          name macos: "custom.macos.beanstalkd", linux: "custom.linux.beanstalkd"
        end
      end

      expect(f.plist_name).to eq("custom.macos.beanstalkd")
      expect(f.service_name).to eq("custom.linux.beanstalkd")
      expect(f.service.to_hash.keys).to contain_exactly(:name)
    end

    specify "service helpers return data" do
      f = formula do
        url "https://brew.sh/test-1.0.tbz"
      end

      expect(f.plist_name).to eq("homebrew.mxcl.formula_name")
      expect(f.service_name).to eq("homebrew.formula_name")
      expect(f.launchd_service_path).to eq(HOMEBREW_PREFIX/"opt/formula_name/homebrew.mxcl.formula_name.plist")
      expect(f.systemd_service_path).to eq(HOMEBREW_PREFIX/"opt/formula_name/homebrew.formula_name.service")
      expect(f.systemd_timer_path).to eq(HOMEBREW_PREFIX/"opt/formula_name/homebrew.formula_name.timer")
    end
  end

  specify "dependencies" do
    # don't try to load/fetch gcc/glibc
    allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

    f1 = formula "f1" do
      url "f1-1.0"
    end

    f2 = formula "f2" do
      url "f2-1.0"
    end

    f3 = formula "f3" do
      url "f3-1.0"

      depends_on "f1" => :build
      depends_on "f2"
    end

    f4 = formula "f4" do
      url "f4-1.0"

      depends_on "f1"
    end

    stub_formula_loader(f1)
    stub_formula_loader(f2)
    stub_formula_loader(f3)
    stub_formula_loader(f4)

    f5 = formula "f5" do
      url "f5-1.0"

      depends_on "f3" => :build
      depends_on "f4"
    end

    expect(f5.deps.map(&:name)).to eq(["f3", "f4"])
    expect(f5.recursive_dependencies.map(&:name)).to eq(%w[f1 f2 f3 f4])
    expect(f5.runtime_dependencies.map(&:name)).to eq(["f1", "f4"])
  end

  describe "#runtime_dependencies" do
    specify "runtime dependencies with optional deps from tap" do
      tap_loader = double

      # don't try to load/fetch gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      allow(tap_loader).to receive(:get_formula).and_raise(RuntimeError, "tried resolving tap formula")
      allow(Formulary).to receive(:loader_for).with("foo/bar/f1", from: nil).and_return(tap_loader)

      f2_path = Tap.fetch("baz", "qux").path/"Formula/f2.rb"
      stub_formula_loader(formula("f2", path: f2_path) { url("f2-1.0") }, "baz/qux/f2")

      f3 = formula "f3" do
        url "f3-1.0"

        depends_on "foo/bar/f1" => :optional
        depends_on "baz/qux/f2"
      end

      expect(f3.runtime_dependencies.map(&:name)).to eq(["baz/qux/f2"])

      f1_path = Tap.fetch("foo", "bar").path/"Formula/f1.rb"
      stub_formula_loader(formula("f1", path: f1_path) { url("f1-1.0") }, "foo/bar/f1")

      f3.build = BuildOptions.new(Options.create(["--with-f1"]), f3.options)

      expect(f3.runtime_dependencies.map(&:name)).to eq(["foo/bar/f1", "baz/qux/f2"])
    end

    it "includes non-declared direct dependencies" do
      formula = Class.new(Testball).new
      dependency = formula("dependency") { url "f-1.0" }

      formula.brew { formula.install }
      keg = Keg.for(formula.latest_installed_prefix)
      keg.link

      linkage_checker = instance_double(LinkageChecker, "linkage checker", undeclared_deps: [dependency.name])
      allow(LinkageChecker).to receive(:new).and_return(linkage_checker)

      expect(formula.runtime_dependencies.map(&:name)).to eq [dependency.name]
    end

    it "handles bad tab runtime_dependencies" do
      formula = Class.new(Testball).new

      formula.brew { formula.install }
      tab = Tab.create(formula, DevelopmentTools.default_compiler, :libcxx)
      tab.runtime_dependencies = ["foo"]
      tab.write

      keg = Keg.for(formula.latest_installed_prefix)
      keg.link

      expect(formula.runtime_dependencies.map(&:name)).to be_empty
    end
  end

  specify "requirements" do
    # don't try to load/fetch gcc/glibc
    allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

    f1 = formula "f1" do
      url "f1-1"

      depends_on xcode: ["1.0", :optional]
    end
    stub_formula_loader(f1)

    xcode = XcodeRequirement.new(["1.0", :optional])

    expect(Set.new(f1.recursive_requirements)).to eq(Set[])

    f1.build = BuildOptions.new(Options.create(["--with-xcode"]), f1.options)

    expect(Set.new(f1.recursive_requirements)).to eq(Set[xcode])

    f1.build = f1.stable.build
    f2 = formula "f2" do
      url "f2-1"

      depends_on "f1"
    end

    expect(Set.new(f2.recursive_requirements)).to eq(Set[])
    expect(
      f2.recursive_requirements do
        # do nothing
      end.to_set,
    ).to eq(Set[xcode])

    requirements = f2.recursive_requirements do |_dependent, requirement|
      Requirement.prune if requirement.is_a?(XcodeRequirement)
    end

    expect(Set.new(requirements)).to eq(Set[])
  end

  specify "#to_hash" do
    f1 = formula "foo" do
      url "foo-1.0"

      bottle do
        sha256 cellar: :any, Utils::Bottles.tag.to_sym => TEST_SHA256
      end
    end

    h = f1.to_hash

    expect(h).to be_a(Hash)
    expect(h["name"]).to eq("foo")
    expect(h["full_name"]).to eq("foo")
    expect(h["tap"]).to eq("homebrew/core")
    expect(h["versions"]["stable"]).to eq("1.0")
    expect(h["versions"]["bottle"]).to be_truthy
  end

  describe "#to_hash_with_variations", :needs_macos do
    let(:formula_path) { CoreTap.instance.new_formula_path("foo-variations") }
    let(:formula_content) do
      <<~RUBY
        class FooVariations < Formula
          url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
          sha256 TESTBALL_SHA256

          on_intel do
            depends_on "intel-formula"
          end

          on_big_sur do
            depends_on "big-sur-formula"
          end

          on_catalina :or_older do
            depends_on "catalina-or-older-formula"
          end

          on_linux do
            depends_on "linux-formula"
          end
        end
      RUBY
    end
    let(:expected_variations) do
      <<~JSON
        {
          "monterey": {
            "dependencies": [
              "intel-formula"
            ]
          },
          "big_sur": {
            "dependencies": [
              "intel-formula",
              "big-sur-formula"
            ]
          },
          "arm64_big_sur": {
            "dependencies": [
              "big-sur-formula"
            ]
          },
          "catalina": {
            "dependencies": [
              "intel-formula",
              "catalina-or-older-formula"
            ]
          },
          "mojave": {
            "dependencies": [
              "intel-formula",
              "catalina-or-older-formula"
            ]
          },
          "x86_64_linux": {
            "dependencies": [
              "intel-formula",
              "linux-formula"
            ]
          },
          "arm64_linux": {
            "dependencies": [
              "linux-formula"
            ]
          }
        }
      JSON
    end

    before do
      # Use a more limited os list to shorten the variations hash
      os_list = [:monterey, :big_sur, :catalina, :mojave, :linux]
      stub_const("OnSystem::ALL_OS_ARCH_COMBINATIONS", os_list.product(OnSystem::ARCH_OPTIONS))

      # For consistency, always run on Monterey and ARM
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("12"))
      allow(Hardware::CPU).to receive(:type).and_return(:arm)

      formula_path.dirname.mkpath
      formula_path.write formula_content
    end

    it "returns the correct variations hash" do
      h = Formulary.factory("foo-variations").to_hash_with_variations

      expect(h).to be_a(Hash)
      expect(JSON.pretty_generate(h["variations"])).to eq expected_variations.strip
    end
  end

  describe "#eligible_kegs_for_cleanup" do
    it "returns Kegs eligible for cleanup" do
      f1 = Class.new(Testball) do
        version("1.0")
      end.new

      f2 = Class.new(Testball) do
        version("0.2")
        version_scheme(1)
      end.new

      f3 = Class.new(Testball) do
        version("0.3")
        version_scheme(1)
      end.new

      f4 = Class.new(Testball) do
        version("0.1")
        version_scheme(2)
      end.new

      [f1, f2, f3, f4].each do |f|
        f.brew { f.install }
        Tab.create(f, DevelopmentTools.default_compiler, :libcxx).write
      end

      expect(f1).to be_latest_version_installed
      expect(f2).to be_latest_version_installed
      expect(f3).to be_latest_version_installed
      expect(f4).to be_latest_version_installed
      expect(f3.eligible_kegs_for_cleanup.sort_by(&:version))
        .to eq([f2, f1].map { |f| Keg.new(f.prefix) })
    end

    specify "with pinned Keg" do
      f1 = Class.new(Testball) { version("0.1") }.new
      f2 = Class.new(Testball) { version("0.2") }.new
      f3 = Class.new(Testball) { version("0.3") }.new

      f1.brew { f1.install }
      f1.pin
      f2.brew { f2.install }
      f3.brew { f3.install }

      expect(f1.prefix).to eq((HOMEBREW_PINNED_KEGS/f1.name).resolved_path)
      expect(f1).to be_latest_version_installed
      expect(f2).to be_latest_version_installed
      expect(f3).to be_latest_version_installed
      expect(f3.eligible_kegs_for_cleanup).to eq([Keg.new(f2.prefix)])
    end

    specify "with HEAD installed" do
      f = formula do
        version("0.1")
        head("foo")
      end

      ["0.0.1", "0.0.2", "0.1", "HEAD-000000", "HEAD-111111", "HEAD-111111_1"].each do |version|
        prefix = f.prefix(version)
        prefix.mkpath
        tab = Tab.empty
        tab.tabfile = prefix/AbstractTab::FILENAME
        tab.source_modified_time = 1
        tab.write
      end

      eligible_kegs = f.installed_kegs - [Keg.new(f.prefix("HEAD-111111_1")), Keg.new(f.prefix("0.1"))]
      expect(f.eligible_kegs_for_cleanup.sort_by(&:version)).to eq(eligible_kegs.sort_by(&:version))
    end
  end

  describe "#pour_bottle?" do
    it "returns false if set to false" do
      f = formula "foo" do
        url "foo-1.0"

        def pour_bottle?
          false
        end
      end

      expect(f).not_to pour_bottle
    end

    it "returns true if set to true" do
      f = formula "foo" do
        url "foo-1.0"

        def pour_bottle?
          true
        end
      end

      expect(f).to pour_bottle
    end

    it "returns false if set to false via DSL" do
      f = formula "foo" do
        url "foo-1.0"

        pour_bottle? do
          reason "false reason"
          satisfy { (var == etc) }
        end
      end

      expect(f).not_to pour_bottle
    end

    it "returns true if set to true via DSL" do
      f = formula "foo" do
        url "foo-1.0"

        pour_bottle? do
          reason "true reason"
          satisfy { true }
        end
      end

      expect(f).to pour_bottle
    end

    it "returns false with `only_if: :clt_installed` on macOS", :needs_macos do
      # Pretend CLT is not installed
      allow(MacOS::CLT).to receive(:installed?).and_return(false)

      f = formula "foo" do
        url "foo-1.0"

        pour_bottle? only_if: :clt_installed
      end

      expect(f).not_to pour_bottle
    end

    it "returns true with `only_if: :clt_installed` on macOS", :needs_macos do
      # Pretend CLT is installed
      allow(MacOS::CLT).to receive(:installed?).and_return(true)

      f = formula "foo" do
        url "foo-1.0"

        pour_bottle? only_if: :clt_installed
      end

      expect(f).to pour_bottle
    end

    it "returns true with `only_if: :clt_installed` on Linux", :needs_linux do
      f = formula "foo" do
        url "foo-1.0"

        pour_bottle? only_if: :clt_installed
      end

      expect(f).to pour_bottle
    end

    it "throws an error if passed both a symbol and a block" do
      expect do
        formula "foo" do
          url "foo-1.0"

          pour_bottle? only_if: :clt_installed do
            reason "true reason"
            satisfy { true }
          end
        end
      end.to raise_error(ArgumentError, "Do not pass both a preset condition and a block to `pour_bottle?`")
    end

    it "throws an error if passed an invalid symbol" do
      expect do
        formula "foo" do
          url "foo-1.0"

          pour_bottle? only_if: :foo
        end
      end.to raise_error(ArgumentError, "Invalid preset `pour_bottle?` condition")
    end
  end

  describe "alias changes" do
    let(:f) do
      formula("formula_name", alias_path:) do
        url "foo-1.0"
      end
    end

    let(:new_formula) do
      formula("new_formula_name", alias_path:) do
        url "foo-1.1"
      end
    end

    let(:tab) { Tab.empty }
    let(:alias_name) { "bar" }
    let(:alias_path) { CoreTap.instance.alias_dir/alias_name }

    before do
      allow(described_class).to receive(:installed).and_return([f])

      f.build = tab
      new_formula.build = tab
    end

    specify "alias changes when not installed with alias" do
      tab.source["path"] = Formulary.core_path(f.name).to_s

      expect(f.current_installed_alias_target).to be_nil
      expect(f.latest_formula).to eq(f)
      expect(f).not_to have_changed_installed_alias_target
      expect(f).not_to supersede_an_installed_formula
      expect(f).not_to have_changed_alias
      expect(f.old_installed_formulae).to be_empty
    end

    specify "alias changes when not changed" do
      tab.source["path"] = alias_path.to_s
      stub_formula_loader(f, alias_name)

      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf f.path, alias_path

      expect(f.current_installed_alias_target).to eq(f)
      expect(f.latest_formula).to eq(f)
      expect(f).not_to have_changed_installed_alias_target
      expect(f).not_to supersede_an_installed_formula
      expect(f).not_to have_changed_alias
      expect(f.old_installed_formulae).to be_empty
    end

    specify "alias changes when new alias target" do
      tab.source["path"] = alias_path.to_s
      stub_formula_loader(new_formula, alias_name)

      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf new_formula.path, alias_path

      expect(f.current_installed_alias_target).to eq(new_formula)
      expect(f.latest_formula).to eq(new_formula)
      expect(f).to have_changed_installed_alias_target
      expect(f).not_to supersede_an_installed_formula
      expect(f).to have_changed_alias
      expect(f.old_installed_formulae).to be_empty
    end

    specify "alias changes when old formulae installed" do
      tab.source["path"] = alias_path.to_s
      stub_formula_loader(new_formula, alias_name)

      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf new_formula.path, alias_path

      expect(new_formula.current_installed_alias_target).to eq(new_formula)
      expect(new_formula.latest_formula).to eq(new_formula)
      expect(new_formula).not_to have_changed_installed_alias_target
      expect(new_formula).to supersede_an_installed_formula
      expect(new_formula).to have_changed_alias
      expect(new_formula.old_installed_formulae).to eq([f])
    end
  end

  describe "#outdated_kegs" do
    let(:outdated_prefix) { (HOMEBREW_CELLAR/"#{f.name}/1.11") }
    let(:same_prefix) { (HOMEBREW_CELLAR/"#{f.name}/1.20") }
    let(:greater_prefix) { (HOMEBREW_CELLAR/"#{f.name}/1.21") }
    let(:head_prefix) { (HOMEBREW_CELLAR/"#{f.name}/HEAD") }
    let(:old_alias_target_prefix) { (HOMEBREW_CELLAR/"#{old_formula.name}/1.0") }

    let(:f) do
      formula do
        url "foo"
        version "1.20"
      end
    end

    let(:old_formula) do
      formula "foo@1" do
        url "foo-1.0"
      end
    end

    let(:new_formula) do
      formula "foo@2" do
        url "foo-2.0"
      end
    end

    let(:alias_name) { "bar" }
    let(:alias_path) { f.tap.alias_dir/alias_name }

    def setup_tab_for_prefix(prefix, options = {})
      prefix.mkpath
      tab = Tab.empty
      tab.tabfile = prefix/AbstractTab::FILENAME
      tab.source["path"] = options[:path].to_s if options[:path]
      tab.source["tap"] = options[:tap] if options[:tap]
      tab.source["versions"] = options[:versions] if options[:versions]
      tab.source_modified_time = options[:source_modified_time].to_i
      tab.write unless options[:no_write]
      tab
    end

    example "greater different tap installed" do
      setup_tab_for_prefix(greater_prefix, tap: "user/repo")
      expect(f.outdated_kegs).to be_empty
    end

    example "greater same tap installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)
      setup_tab_for_prefix(greater_prefix, tap: "homebrew/core")
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated different tap installed" do
      setup_tab_for_prefix(outdated_prefix, tap: "user/repo")
      expect(f.outdated_kegs).not_to be_empty
    end

    example "outdated same tap installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)
      setup_tab_for_prefix(outdated_prefix, tap: "homebrew/core")
      expect(f.outdated_kegs).not_to be_empty
    end

    example "outdated follow alias and alias unchanged" do
      f.follow_installed_alias = true
      f.build = setup_tab_for_prefix(same_prefix, path: alias_path)
      stub_formula_loader(f, alias_name)
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated follow alias and alias changed and new target not installed" do
      f.follow_installed_alias = true
      f.build = setup_tab_for_prefix(same_prefix, path: alias_path)
      stub_formula_loader(new_formula, alias_name)

      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf new_formula.path, alias_path

      expect(f.outdated_kegs).not_to be_empty
    end

    example "outdated follow alias and alias changed and new target installed" do
      f.follow_installed_alias = true
      f.build = setup_tab_for_prefix(same_prefix, path: alias_path)
      stub_formula_loader(new_formula, alias_name)
      setup_tab_for_prefix(new_formula.prefix)
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated no follow alias and alias unchanged" do
      f.follow_installed_alias = false
      f.build = setup_tab_for_prefix(same_prefix, path: alias_path)
      stub_formula_loader(f, alias_name)
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated no follow alias and alias changed" do
      f.follow_installed_alias = false
      f.build = setup_tab_for_prefix(same_prefix, path: alias_path)

      f2 = formula "foo@2" do
        url "foo-2.0"
      end

      stub_formula_loader(f2, alias_path)
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated old alias targets installed" do
      f = formula(alias_path:) do
        url "foo-1.0"
      end

      tab = setup_tab_for_prefix(old_alias_target_prefix, path: alias_path)
      old_formula.build = tab
      allow(described_class).to receive(:installed).and_return([old_formula])

      CoreTap.instance.alias_dir.mkpath
      FileUtils.ln_sf f.path, alias_path

      expect(f.outdated_kegs).not_to be_empty
    end

    example "outdated old alias targets not installed" do
      f = formula(alias_path:) do
        url "foo-1.0"
      end

      tab = setup_tab_for_prefix(old_alias_target_prefix, path: old_formula.path)
      old_formula.build = tab
      allow(described_class).to receive(:installed).and_return([old_formula])
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated same head installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)
      setup_tab_for_prefix(head_prefix, tap: "homebrew/core")
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated different head installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)
      setup_tab_for_prefix(head_prefix, tap: "user/repo")
      expect(f.outdated_kegs).to be_empty
    end

    example "outdated mixed taps greater version installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)
      setup_tab_for_prefix(outdated_prefix, tap: "homebrew/core")
      setup_tab_for_prefix(greater_prefix, tap: "user/repo")

      expect(f.outdated_kegs).to be_empty

      setup_tab_for_prefix(greater_prefix, tap: "homebrew/core")
      described_class.clear_cache

      expect(f.outdated_kegs).to be_empty
    end

    example "outdated mixed taps outdated version installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)

      extra_outdated_prefix = HOMEBREW_CELLAR/f.name/"1.0"

      setup_tab_for_prefix(outdated_prefix)
      setup_tab_for_prefix(extra_outdated_prefix, tap: "homebrew/core")
      described_class.clear_cache

      expect(f.outdated_kegs).not_to be_empty

      setup_tab_for_prefix(outdated_prefix, tap: "user/repo")
      described_class.clear_cache

      expect(f.outdated_kegs).not_to be_empty
    end

    example "outdated same version tap installed" do
      f.instance_variable_set(:@tap, CoreTap.instance)
      setup_tab_for_prefix(same_prefix, tap: "homebrew/core")

      expect(f.outdated_kegs).to be_empty

      setup_tab_for_prefix(same_prefix, tap: "user/repo")
      described_class.clear_cache

      expect(f.outdated_kegs).to be_empty
    end

    example "outdated installed head less than stable" do
      tab = setup_tab_for_prefix(head_prefix, versions: { "stable" => "1.0" })

      expect(f.outdated_kegs).not_to be_empty

      tab.source["versions"] = { "stable" => f.version.to_s }
      tab.write
      described_class.clear_cache

      expect(f.outdated_kegs).to be_empty
    end

    describe ":fetch_head" do
      let(:f) do
        repo = testball_repo
        formula "testball" do
          url "foo"
          version "2.10"
          head "file://#{repo}", using: :git
        end
      end
      let(:testball_repo) { HOMEBREW_PREFIX/"testball_repo" }

      example do
        outdated_stable_prefix = HOMEBREW_CELLAR/"testball/1.0"
        head_prefix_a = HOMEBREW_CELLAR/"testball/HEAD"
        head_prefix_b = HOMEBREW_CELLAR/"testball/HEAD-aaaaaaa_1"
        head_prefix_c = HOMEBREW_CELLAR/"testball/HEAD-18a7103"

        setup_tab_for_prefix(outdated_stable_prefix)
        tab_a = setup_tab_for_prefix(head_prefix_a, versions: { "stable" => "1.0" })
        setup_tab_for_prefix(head_prefix_b)

        testball_repo.mkdir
        testball_repo.cd do
          FileUtils.touch "LICENSE"

          system("git", "-c", "init.defaultBranch=master", "init")
          system("git", "add", "--all")
          system("git", "commit", "-m", "Initial commit")
        end

        expect(f.outdated_kegs(fetch_head: true)).not_to be_empty

        tab_a.source["versions"] = { "stable" => f.version.to_s }
        tab_a.write
        described_class.clear_cache
        expect(f.outdated_kegs(fetch_head: true)).not_to be_empty

        FileUtils.rm_r(head_prefix_a)
        described_class.clear_cache
        expect(f.outdated_kegs(fetch_head: true)).not_to be_empty

        setup_tab_for_prefix(head_prefix_c, source_modified_time: 1)
        described_class.clear_cache
        expect(f.outdated_kegs(fetch_head: true)).to be_empty
      ensure
        FileUtils.rm_r(testball_repo) if testball_repo.exist?
      end
    end

    describe "#mkdir" do
      let(:dst) { mktmpdir }

      it "creates intermediate directories" do
        f.mkdir dst/"foo/bar/baz" do
          expect(dst/"foo/bar/baz").to exist, "foo/bar/baz was not created"
          expect(dst/"foo/bar/baz").to be_a_directory, "foo/bar/baz was not a directory structure"
        end
      end
    end

    describe "with changed version scheme" do
      let(:f) do
        formula "testball" do
          url "foo"
          version "20141010"
          version_scheme 1
        end
      end

      example do
        prefix = HOMEBREW_CELLAR/"testball/0.1"
        setup_tab_for_prefix(prefix, versions: { "stable" => "0.1" })

        expect(f.outdated_kegs).not_to be_empty
      end
    end

    describe "with mixed version schemes" do
      let(:f) do
        formula "testball" do
          url "foo"
          version "20141010"
          version_scheme 3
        end
      end

      example do
        prefix_a = HOMEBREW_CELLAR/"testball/20141009"
        setup_tab_for_prefix(prefix_a, versions: { "stable" => "20141009", "version_scheme" => 1 })

        prefix_b = HOMEBREW_CELLAR/"testball/2.14"
        setup_tab_for_prefix(prefix_b, versions: { "stable" => "2.14", "version_scheme" => 2 })

        expect(f.outdated_kegs).not_to be_empty
        described_class.clear_cache

        prefix_c = HOMEBREW_CELLAR/"testball/20141009"
        setup_tab_for_prefix(prefix_c, versions: { "stable" => "20141009", "version_scheme" => 3 })

        expect(f.outdated_kegs).not_to be_empty
        described_class.clear_cache

        prefix_d = HOMEBREW_CELLAR/"testball/20141011"
        setup_tab_for_prefix(prefix_d, versions: { "stable" => "20141009", "version_scheme" => 3 })
        expect(f.outdated_kegs).to be_empty
      end
    end

    describe "with version scheme" do
      let(:f) do
        formula "testball" do
          url "foo"
          version "1.0"
          version_scheme 2
        end
      end

      example do
        head_prefix = HOMEBREW_CELLAR/"testball/HEAD"

        setup_tab_for_prefix(head_prefix, versions: { "stable" => "1.0", "version_scheme" => 1 })
        expect(f.outdated_kegs).not_to be_empty

        described_class.clear_cache
        FileUtils.rm_r(head_prefix)

        setup_tab_for_prefix(head_prefix, versions: { "stable" => "1.0", "version_scheme" => 2 })
        expect(f.outdated_kegs).to be_empty
      end
    end
  end

  describe "#any_installed_version" do
    let(:f) do
      Class.new(Testball) do
        version "1.0"
        revision 1
      end.new
    end

    it "returns nil when not installed" do
      expect(f.any_installed_version).to be_nil
    end

    it "returns package version when installed" do
      f.brew { f.install }
      expect(f.any_installed_version).to eq(PkgVersion.parse("1.0_1"))
    end
  end

  describe "#on_macos", :needs_macos do
    let(:f) do
      Class.new(Testball) do
        attr_reader :test

        def install
          @test = 0
          on_macos do
            @test = 1
          end
          on_linux do
            @test = 2
          end
        end
      end.new
    end

    it "only calls code within on_macos" do
      f.brew { f.install }
      expect(f.test).to eq(1)
    end
  end

  describe "#on_linux", :needs_linux do
    let(:f) do
      Class.new(Testball) do
        attr_reader :test

        def install
          @test = 0
          on_macos do
            @test = 1
          end
          on_linux do
            @test = 2
          end
        end
      end.new
    end

    it "only calls code within on_linux" do
      f.brew { f.install }
      expect(f.test).to eq(2)
    end
  end

  describe "#on_system" do
    let(:f) do
      Class.new(Testball) do
        attr_reader :foo
        attr_reader :bar

        def install
          @foo = 0
          @bar = 0
          on_system :linux, macos: :monterey do
            @foo = 1
          end
          on_system :linux, macos: :big_sur_or_older do
            @bar = 1
          end
        end
      end.new
    end

    it "doesn't call code on Ventura", :needs_macos do
      Homebrew::SimulateSystem.with os: :ventura do
        f.brew { f.install }
        expect(f.foo).to eq(0)
        expect(f.bar).to eq(0)
      end
    end

    it "calls code on Linux", :needs_linux do
      Homebrew::SimulateSystem.with os: :linux do
        f.brew { f.install }
        expect(f.foo).to eq(1)
        expect(f.bar).to eq(1)
      end
    end

    it "calls code within `on_system :linux, macos: :monterey` on Monterey", :needs_macos do
      Homebrew::SimulateSystem.with os: :monterey do
        f.brew { f.install }
        expect(f.foo).to eq(1)
        expect(f.bar).to eq(0)
      end
    end

    it "calls code within `on_system :linux, macos: :big_sur_or_older` on Big Sur", :needs_macos do
      Homebrew::SimulateSystem.with os: :big_sur do
        f.brew { f.install }
        expect(f.foo).to eq(0)
        expect(f.bar).to eq(1)
      end
    end

    it "calls code within `on_system :linux, macos: :big_sur_or_older` on Catalina", :needs_macos do
      Homebrew::SimulateSystem.with os: :catalina do
        f.brew { f.install }
        expect(f.foo).to eq(0)
        expect(f.bar).to eq(1)
      end
    end
  end

  describe "on_{os_version} blocks", :needs_macos do
    let(:f) do
      Class.new(Testball) do
        attr_reader :test

        def install
          @test = 0
          on_monterey :or_newer do
            @test = 1
          end
          on_big_sur do
            @test = 2
          end
          on_catalina :or_older do
            @test = 3
          end
        end
      end.new
    end

    it "only calls code within `on_monterey`" do
      Homebrew::SimulateSystem.with os: :monterey do
        f.brew { f.install }
        expect(f.test).to eq(1)
      end
    end

    it "only calls code within `on_monterey :or_newer`" do
      Homebrew::SimulateSystem.with os: :ventura do
        f.brew { f.install }
        expect(f.test).to eq(1)
      end
    end

    it "only calls code within `on_big_sur`" do
      Homebrew::SimulateSystem.with os: :big_sur do
        f.brew { f.install }
        expect(f.test).to eq(2)
      end
    end

    it "only calls code within `on_catalina`" do
      Homebrew::SimulateSystem.with os: :catalina do
        f.brew { f.install }
        expect(f.test).to eq(3)
      end
    end

    it "only calls code within `on_catalina :or_older`" do
      Homebrew::SimulateSystem.with os: :mojave do
        f.brew { f.install }
        expect(f.test).to eq(3)
      end
    end
  end

  describe "#on_arm" do
    before do
      allow(Hardware::CPU).to receive(:type).and_return(:arm)
    end

    let(:f) do
      Class.new(Testball) do
        attr_reader :test

        def install
          @test = 0
          on_arm do
            @test = 1
          end
          on_intel do
            @test = 2
          end
        end
      end.new
    end

    it "only calls code within on_arm" do
      f.brew { f.install }
      expect(f.test).to eq(1)
    end
  end

  describe "#on_intel" do
    before do
      allow(Hardware::CPU).to receive(:type).and_return(:intel)
    end

    let(:f) do
      Class.new(Testball) do
        attr_reader :test

        def install
          @test = 0
          on_arm do
            @test = 1
          end
          on_intel do
            @test = 2
          end
        end
      end.new
    end

    it "only calls code within on_intel" do
      f.brew { f.install }
      expect(f.test).to eq(2)
    end
  end

  describe "#generate_completions_from_executable" do
    let(:f) do
      Class.new(Testball) do
        def install
          bin.mkpath
          (bin/"foo").write <<-EOF
            echo completion
          EOF

          FileUtils.chmod "+x", bin/"foo"

          generate_completions_from_executable(bin/"foo", "test")
        end
      end.new
    end

    it "generates completion scripts" do
      f.brew { f.install }
      expect(f.bash_completion/"foo").to be_a_file
      expect(f.zsh_completion/"_foo").to be_a_file
      expect(f.fish_completion/"foo.fish").to be_a_file
    end
  end

  describe "{allow,deny}_network_access" do
    phases = [:build, :postinstall, :test].freeze
    actions = %w[allow deny].freeze
    phases.each do |phase|
      actions.each do |action|
        it "can #{action} network access for #{phase}" do
          f = Class.new(Testball) do
            send(:"#{action}_network_access!", phase)
          end

          expect(f.network_access_allowed?(phase)).to be(action == "allow")
        end
      end
    end

    actions.each do |action|
      it "can #{action} network access for all phases" do
        f = Class.new(Testball) do
          send(:"#{action}_network_access!")
        end

        phases.each do |phase|
          expect(f.network_access_allowed?(phase)).to be(action == "allow")
        end
      end
    end
  end

  describe "#network_access_allowed?" do
    it "throws an error when passed an invalid symbol" do
      f = Testball.new
      expect { f.network_access_allowed?(:foo) }.to raise_error(ArgumentError)
    end
  end

  describe "#specified_path" do
    let(:klass) do
      Class.new(described_class) do
        url "https://brew.sh/foo-1.0.tar.gz"
      end
    end

    let(:name) { "formula_name" }
    let(:path) { Formulary.core_path(name) }
    let(:spec) { :stable }
    let(:alias_name) { "baz@1" }
    let(:alias_path) { CoreTap.instance.alias_dir/alias_name }
    let(:f) { klass.new(name, path, spec) }
    let(:f_alias) { klass.new(name, path, spec, alias_path:) }

    context "when loading from a formula file" do
      it "returns the formula file path" do
        expect(f.specified_path).to eq(path)
      end
    end

    context "when loaded from an alias" do
      it "returns the alias path" do
        expect(f_alias.specified_path).to eq(alias_path)
      end
    end

    context "when loaded from the API" do
      before do
        allow(f).to receive(:loaded_from_api?).and_return(true)
      end

      it "returns the API path" do
        expect(f.specified_path).to eq(Homebrew::API::Formula.cached_json_file_path)
      end
    end
  end
end
