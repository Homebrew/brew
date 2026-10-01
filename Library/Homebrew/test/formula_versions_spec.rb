# typed: true
# frozen_string_literal: true

require "formula_versions"

RSpec.describe FormulaVersions do
  let(:host_macos) do
    Module.new.tap do |macos|
      macos.define_singleton_method(:version) { MacOSVersion.new("15") }
      macos.define_singleton_method(:full_version) { MacOSVersion.new("15.7") }
      macos.define_singleton_method(:sdk_for_formula) do |_formula, _version = nil, **options|
        options.fetch(:check_only_runtime_requirements) ? "runtime" : "all"
      end
      xcode = Module.new.tap { |mod| mod.define_singleton_method(:version) { Version.new("16.4") } }
      macos.const_set(:Xcode, xcode)
    end
  end

  it "includes an earlier lifetime of a deleted and re-added formula in complete history" do
    current = formula("readded") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/readded-2.0.tar.gz"
    end

    Dir.mktmpdir do |dir|
      repository = Pathname(dir)
      path = repository/"Formula/readded.rb"
      path.dirname.mkpath
      allow(current).to receive(:tap_path).and_return(path)
      allow(current.tap!).to receive(:path).and_return(repository)
      git = ["git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.test",
             "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null"]
      Utils.safe_popen_read(*git, "init", "--quiet")
      path.write("first lifetime\n")
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Add formula")
      first_revision = Utils.safe_popen_read(*git, "rev-parse", "--short", "HEAD").strip
      path.unlink
      Utils.safe_popen_read(*git, "commit", "--quiet", "-am", "Remove formula")
      path.write("second lifetime\n")
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Restore formula")
      revisions = []

      described_class.new(current).rev_list("HEAD", all_history: true) { |rev, _path| revisions << rev }

      expect(revisions).to include(first_revision)
    end
  end

  it "uses the simulated golden_gate version for historical macOS resource branches" do
    current = formula("legacy-macos") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-macos-2.0.tar.gz"
    end
    versions = described_class.new(current, simulated_target: true)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyMacos < Formula
        url "https://brew.sh/legacy-macos-1.0.tar.gz"
        resource "helper" do
          if MacOS.version <= :lion
            url "https://brew.sh/helper-1.0.tar.gz"
          else
            url "https://brew.sh/helper-2.0.tar.gz"
          end
        end
      end
    RUBY
    allow(Homebrew::SimulateSystem).to receive(:current_os).and_return(:golden_gate)
    hide_const("MacOS")

    result = versions.formula_at_revision("abc123") { |old| old.resource("helper")&.version&.to_s }

    expect(result).to eq "2.0"
  end

  it "uses the simulated big_sur version for historical macOS resource branches" do
    current = formula("legacy-macos") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-macos-2.0.tar.gz"
    end
    versions = described_class.new(current, simulated_target: true)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyMacos < Formula
        url "https://brew.sh/legacy-macos-1.0.tar.gz"
        resource "helper" do
          if MacOS.version < :ventura
            url "https://brew.sh/helper-1.0.tar.gz"
          else
            url "https://brew.sh/helper-2.0.tar.gz"
          end
        end
      end
    RUBY
    allow(Homebrew::SimulateSystem).to receive(:current_os).and_return(:big_sur)
    hide_const("MacOS")

    result = versions.formula_at_revision("abc123") { |old| old.resource("helper")&.version&.to_s }

    expect(result).to eq "1.0"
  end

  it "preserves resources in historical Linux or retired macOS blocks" do
    current = formula("legacy-system") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-system-2.0.tar.gz"
    end
    contents = <<~RUBY
      class LegacySystem < Formula
        url "https://brew.sh/legacy-system-1.0.tar.gz"
        on_system :linux, macos: :catalina_or_older do
          resource "helper" do
            url "https://brew.sh/helper-1.0.tar.gz"
          end
        end
      end
    RUBY
    results = [:linux, :golden_gate].map do |target|
      Homebrew::SimulateSystem.with(os: target) do
        versions = described_class.new(current)
        allow(versions).to receive(:file_contents_at_revision).and_return(contents)
        versions.formula_at_revision("abc123") { |old| old.resources.map(&:name) }
      end
    end

    expect(results).to eq [["helper"], []]
  end

  it "answers historical Linux macOS queries as older than every release" do
    current = formula("legacy-macos") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-macos-2.0.tar.gz"
    end
    versions = described_class.new(current, simulated_target: true)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyMacos < Formula
        url "https://brew.sh/legacy-macos-1.0.tar.gz"
        if MacOS.version <= :lion && MacOS.full_version < :golden_gate && MacOS.version != MacOS.version &&
           !MacOS::Xcode.installed? && MacOS::CLT.version < "11" && MacOS.sdk_path.nil? && !MacOS.sdk_root_needed?
          version "1.1"
        end
      end
    RUBY
    stub_const("MacOS", host_macos)

    result = Homebrew::SimulateSystem.with(os: :linux) do
      versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }
    end

    expect(result).to eq "1.1"
  end

  it "holds host-derived macOS queries in advisory walks" do
    current = formula("legacy-macos") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-macos-2.0.tar.gz"
    end
    queries = {
      linux:       ["MacOS.languages", "MacOS.prefer_64_bit?", "MacOS.version.to_sym"],
      golden_gate: ["MacOS.full_version", "MacOS::Xcode.version", "MacOS.sdk_path", "MacOS.prefer_64_bit?"],
    }
    stub_const("MacOS", host_macos)
    results = queries.flat_map do |target, sources|
      sources.map do |source|
        Homebrew::SimulateSystem.with(os: target) do
          versions = described_class.new(current, simulated_target: true)
          allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
            class LegacyMacos < Formula
              url "https://brew.sh/legacy-macos-1.0.tar.gz"
              version "1.1" if #{source}
            end
          RUBY
          [versions.formula_at_revision("abc123", &:pkg_version), versions.load_error&.class]
        end
      end
    end

    expect(results).to eq Array.new(7) { [nil, FormulaSpecificationError] }
  end

  it "holds historical formulae with unknown macOS release symbols or float comparisons in resource branches" do
    current = formula("legacy-macos") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-macos-2.0.tar.gz"
    end
    targets = [:golden_gate, :big_sur, :linux]
    comparisons = ["< :unknown_release", "== :unknown_release", "!= :unknown_release", "< 10.6", "== 10.6"]
    results = comparisons.flat_map do |comparison|
      contents = <<~RUBY
        class LegacyMacos < Formula
          url "https://brew.sh/legacy-macos-1.0.tar.gz"
          resource "helper" do
            if MacOS.version #{comparison}
              url "https://brew.sh/helper-1.0.tar.gz"
            else
              url "https://brew.sh/helper-2.0.tar.gz"
            end
          end
        end
      RUBY
      targets.map do |target|
        Homebrew::SimulateSystem.with(os: target) do
          versions = described_class.new(current, simulated_target: true)
          allow(versions).to receive(:file_contents_at_revision).and_return(contents)
          result = versions.formula_at_revision("abc123") { |old| old.resource("helper")&.version&.to_s }
          [result, versions.load_error&.class]
        end
      end
    end

    expect(results).to eq Array.new(15) { [nil, FormulaSpecificationError] }
  end

  it "matches retired or_newer and exact on_system conditions against the simulated target" do
    current = formula("legacy-system") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-system-2.0.tar.gz"
    end
    targets = [:linux, :golden_gate]
    results = [:catalina_or_newer, :catalina].flat_map do |macos|
      targets.map do |target|
        Homebrew::SimulateSystem.with(os: target) do
          versions = described_class.new(current)
          allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
            class LegacySystem < Formula
              url "https://brew.sh/legacy-system-1.0.tar.gz"
              on_system :linux, macos: #{macos.inspect} do
                resource "helper" do
                  url "https://brew.sh/helper-1.0.tar.gz"
                end
              end
            end
          RUBY
          versions.formula_at_revision("abc123") { |old| old.resources.map(&:name) }
        end
      end
    end

    expect(results).to eq [["helper"], ["helper"], ["helper"], []]
  end

  it "holds historical formulae with invalid on_system arguments" do
    current = formula("legacy-system") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-system-2.0.tar.gz"
    end
    targets = [:linux, :golden_gate]
    arguments = [
      [:windows, :catalina_or_older], [:linux, :catalina_or_invalid],
      [:windows, :ventura_or_older], [:linux, :ventura_or_invalid], [:linux, :panther_or_older]
    ]
    results = arguments.flat_map do |linux, macos|
      contents = <<~RUBY
        class LegacySystem < Formula
          url "https://brew.sh/legacy-system-1.0.tar.gz"
          on_system #{linux.inspect}, macos: #{macos.inspect} do
            resource "helper" do
              url "https://brew.sh/helper-1.0.tar.gz"
            end
          end
        end
      RUBY
      targets.map do |target|
        Homebrew::SimulateSystem.with(os: target) do
          versions = described_class.new(current)
          allow(versions).to receive(:file_contents_at_revision).and_return(contents)
          result = versions.formula_at_revision("abc123") { |old| old.resources.map(&:name) }
          [result, versions.load_error&.class]
        end
      end
    end

    expect(results).to eq Array.new(10) { [nil, FormulaSpecificationError] }
  end

  it "exposes legacy build option queries only on historical build options" do
    current = formula("legacy-options") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-options-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyOptions < Formula
        url "https://brew.sh/legacy-options-1.0.tar.gz"
        option "with-helper"
        version "1.1" if build.include? "with-helper"
      end
    RUBY

    result = versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }

    expect([result, current.build.respond_to?(:include?)]).to eq ["1.0", false]
  end

  it "applies undated and reason-free historical lifecycle calls immediately" do
    current = formula("legacy-lifecycle") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-lifecycle-2.0.tar.gz"
    end
    calls = [
      "deprecate! because: :unmaintained", "disable! because: :unmaintained", "deprecate!",
      'deprecate! date: "2020-01-01"', 'disable! date: "2999-01-01"',
      'deprecate! because: :unmaintained, replacement_formula: "other"'
    ]
    results = calls.map do |call|
      versions = described_class.new(current)
      allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
        class LegacyLifecycle < Formula
          url "https://brew.sh/legacy-lifecycle-1.0.tar.gz"
          #{call}
        end
      RUBY
      versions.formula_at_revision("abc123") do |old|
        [old.deprecated?, old.deprecation_reason, old.disabled?, old.disable_reason]
      end || versions.load_error&.class
    end

    expect(results).to eq [
      [true, :unmaintained, false, nil], [false, nil, true, :unmaintained], [true, nil, false, nil],
      [true, nil, false, nil], [true, nil, false, nil], FormulaSpecificationError
    ]
  end

  it "ignores obsolete bottle prefix and C++ check metadata historically" do
    current = formula("legacy-lifecycle") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-lifecycle-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyLifecycle < Formula
        url "https://brew.sh/legacy-lifecycle-1.0.tar.gz"
        cxxstdlib_check :skip
        bottle do
          prefix "/usr/local"
        end
      end
    RUBY

    result = versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }

    expect(result).to eq "1.0"
  end

  it "preserves dated lifecycle metadata" do
    current = formula("legacy-lifecycle") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-lifecycle-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyLifecycle < Formula
        url "https://brew.sh/legacy-lifecycle-1.0.tar.gz"
        deprecate! date: "2020-01-01", because: :unmaintained
      end
    RUBY

    result = versions.formula_at_revision("abc123", &:deprecated?)

    expect(result).to be true
  end

  it "keeps the host MacOS API outside advisory walks" do
    current = formula("legacy-host") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-host-2.0.tar.gz"
    end
    stub_const("MacOS", host_macos)
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~'RUBY')
      class LegacyHost < Formula
        url "https://brew.sh/legacy-host-1.0.tar.gz"
        sdk = MacOS.sdk_for_formula(nil, nil, check_only_runtime_requirements: true)
        version "#{MacOS.full_version}-#{MacOS::Xcode.version}-#{MacOS.version.to_sym}-#{sdk}"
      end
    RUBY

    result = versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }

    expect(result).to eq "15.7-16.4-sequoia-runtime"
  end

  it "restores the host MacOS context after advisory loads, failed loads and consumer errors" do
    current = formula("legacy-reset") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-reset-2.0.tar.gz"
    end
    loadable = <<~RUBY
      class LegacyReset < Formula
        url "https://brew.sh/legacy-reset-1.0.tar.gz"
      end
    RUBY
    unloadable = loadable.sub("end", "  uses_From_macos \"zlib\"\nend")
    consumers = [[loadable, ->(_old) { true }], [unloadable, ->(_old) { true }],
                 [loadable, ->(_old) { raise ArgumentError, "consumer failure" }]]
    states = consumers.map do |contents, consumer|
      versions = described_class.new(current, simulated_target: true)
      allow(versions).to receive(:file_contents_at_revision).and_return(contents)
      begin
        versions.formula_at_revision("abc123", &consumer)
      rescue ArgumentError
        nil
      end
      FormulaVersions::LegacyMacOS.simulated_target
    end

    expect(states).to eq [false, false, false]
  end

  it "switches between host and simulated target answers across loads" do
    current = formula("legacy-context") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-context-2.0.tar.gz"
    end
    stub_const("MacOS", host_macos)
    contents = <<~'RUBY'
      class LegacyContext < Formula
        url "https://brew.sh/legacy-context-1.0.tar.gz"
        resource "#{MacOS.version.class.name.split("::").last}-#{MacOS.version}" do
          url "https://brew.sh/helper-1.0.tar.gz"
        end
      end
    RUBY
    load = lambda do |target|
      run = lambda do
        versions = described_class.new(current, simulated_target: !target.nil?)
        allow(versions).to receive(:file_contents_at_revision).and_return(contents)
        versions.formula_at_revision("abc123") { |old| old.resources.map(&:name) }
      end
      target ? Homebrew::SimulateSystem.with(os: target, &run) : run.call
    end
    # `sequoia` matches the stubbed macOS host and `linux` a Linux host, so
    # `SimulateSystem.simulating?` is false for one advisory load on either.
    targets = [nil, :sequoia, :linux, :golden_gate, nil]
    expected = %w[MacOSVersion-15 LegacyMacOSVersion-15 LegacyMacOSVersion- LegacyMacOSVersion-27 MacOSVersion-15]

    results = [targets, targets.reverse].map { |order| order.flat_map { |target| load.call(target) } }

    expect(results).to eq [expected, expected.reverse]
  end

  it "loads ScriptFileFormula metadata without restoring the removed install helper globally" do
    current = formula("legacy-script") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-script-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyScript < ScriptFileFormula
        url "https://brew.sh/legacy-script-1.0.tar.gz"
      end
    RUBY

    result = versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }

    expect([result, Object.const_defined?(:ScriptFileFormula)]).to eq ["1.0", false]
  end

  it "loads a historical strict Subversion head without changing the stable source" do
    current = formula("legacy-head") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-head-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyHead < Formula
        url "https://brew.sh/legacy-head-1.0.tar.gz"
        head "https://svn.example.test/repo", using: StrictSubversionDownloadStrategy
      end
    RUBY

    result = versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }

    expect(result).to eq "1.0"
  end

  it "continues holding an unknown historical DSL spelling" do
    current = formula("legacy-typo") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-typo-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyTypo < Formula
        url "https://brew.sh/legacy-typo-1.0.tar.gz"
        uses_From_macos "libxslt"
      end
    RUBY

    result = versions.formula_at_revision("abc123", &:pkg_version)

    expect([result, versions.load_error&.class]).to eq [nil, NoMethodError]
  end

  it "loads historical formulae that use legacy bottle syntax" do
    current = formula("legacy-bottle") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-bottle-2.0.tar.gz"
    end
    versions = described_class.new(current)
    digest = "a" * 64
    contents = <<~RUBY
      # frozen_string_literal: true

      class LegacyBottle < Formula
        desc "legacy".frozen?.to_s
        url "https://brew.sh/legacy-bottle-1.0.tar.gz"

        bottle do
          cellar :any_skip_relocation
          revision 1
          sha256 "#{digest}" => :big_sur
        end
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision).and_return(contents)

    result = versions.formula_at_revision("abc123") do |historical|
      tag = Utils::Bottles::Tag.from_symbol(:big_sur)
      tag_spec = historical.bottle_specification.tag_specification_for(tag)
      [historical.bottle_specification.class, historical.desc, historical.pkg_version.to_s,
       tag_spec&.checksum&.hexdigest, tag_spec&.cellar]
    end

    expect(result).to eq [FormulaVersions::LegacyBottleSpecification, "true", "1.0", digest, :any_skip_relocation]
  end

  it "loads deprecated install steps without emitting annotations or losing historical metadata" do
    ENV["GITHUB_ACTIONS"] = "true"
    ENV.delete("HOMEBREW_TESTS")
    current = formula("legacy-install-steps") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-install-steps-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyInstallSteps < Formula
        url "https://brew.sh/legacy-install-steps-1.0.tar.gz"
        post_install_steps do
          gtk_update_icon_cache
        end
        revision 2
        resource "helper" do
          url "https://brew.sh/helper-1.2.tar.gz"
        end
      end
    RUBY
    result = []

    expect do
      versions.formula_at_revision("abc123") do |historical|
        result = [historical.pkg_version.to_s, historical.resource("helper")&.version&.to_s]
      end
    end.not_to output.to_stderr
    expect(result).to eq ["1.0_2", "1.2"]
  end

  it "ignores the removed devel spec while preserving the stable historical build" do
    current = formula("legacy-devel") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-devel-2.0.tar.gz"
    end
    versions = described_class.new(current)
    contents = <<~RUBY
      class LegacyDevel < Formula
        url "https://brew.sh/legacy-devel-1.0.tar.gz"
        revision 1

        devel do
          url "https://brew.sh/legacy-devel-1.5.tar.gz"
          obsolete_devel_only_stanza
        end
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision).and_return(contents)

    result = versions.formula_at_revision("abc123") do |historical|
      [historical.stable&.url, historical.pkg_version.to_s]
    end

    expect([result, Formula.respond_to?(:devel)])
      .to eq [["https://brew.sh/legacy-devel-1.0.tar.gz", "1.0_1"], false]
  end

  it "does not infer an absent path from an invalid revision" do
    current = formula("invalid-revision") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/invalid-revision-1.0.tar.gz"
    end
    Dir.mktmpdir do |dir|
      allow(current.tap!).to receive(:path).and_return(Pathname(dir))
      Utils.safe_popen_read("git", "-C", dir, "init", "--quiet")

      expect { described_class.new(current).path_absent_at_revision?("missing-revision", "Formula/missing.rb") }
        .to raise_error(ErrorDuringExecution)
    end
  end

  it "loads legacy checksums without changing historical sources or normal resource loading" do
    current = formula("legacy-checksums") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-checksums-2.0.tar.gz"
    end
    versions = described_class.new(current)
    contents = <<~RUBY
      class LegacyChecksums < Formula
        url "https://brew.sh/legacy-checksums-1.0.tar.gz"
        sha1 "#{"a" * 40}"
        md5 "#{"a" * 32}"
        revision 2

        stable do
          sha1 "#{"a" * 40}"
          md5 "#{"a" * 32}"
          resource "helper" do
            url "https://brew.sh/helper-1.2.tar.gz"
            sha1 "#{"b" * 40}"
            md5 "#{"b" * 32}"
          end
        end

        bottle do
          revision 3
          sha1 "#{"c" * 40}" => :yosemite
          md5 "#{"c" * 32}" => :yosemite
        end
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision).and_return(contents)

    result = versions.formula_at_revision("abc123") do |historical|
      [historical.pkg_version.to_s, historical.stable&.url,
       historical.resource("helper")&.version&.to_s, historical.resource("helper")&.url]
    end

    expect([result, Formula.respond_to?(:sha1), Resource.new.respond_to?(:sha1),
            SoftwareSpec.new.respond_to?(:sha1), BottleSpecification.new.respond_to?(:sha1)]).to eq [
              ["1.0_2", "https://brew.sh/legacy-checksums-1.0.tar.gz", "1.2", "https://brew.sh/helper-1.2.tar.gz"],
              false, false, false, false
            ]
  end

  it "ignores removed service and bottle metadata only in historical formulae" do
    current = formula("legacy-metadata") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-metadata-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyMetadata < Formula
        url "https://brew.sh/legacy-metadata-1.0.tar.gz"
        bottle :unneeded
        plist_options startup: true
      end
    RUBY

    result = versions.formula_at_revision("abc123") { |historical| historical.pkg_version.to_s }

    expect([result, Formula.respond_to?(:plist_options)]).to eq ["1.0", false]
  end

  it "preserves historical patch URLs, apply paths and advisory references with legacy checksums" do
    current = formula("legacy-patches") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/legacy-patches-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class LegacyPatches < Formula
        url "https://brew.sh/legacy-patches-1.0.tar.gz"
        patch :p0 do
          url "https://brew.sh/patches.tar.gz"
          sha1 "#{"a" * 40}"
          apply "CVE-2024-1234.patch"
        end
        resource "helper" do
          url "https://brew.sh/helper-1.2.tar.gz"
          patch do
            url "https://brew.sh/CVE-2024-5678.patch"
            md5 "#{"b" * 32}"
          end
        end
      end
    RUBY

    result = versions.formula_at_revision("abc123") do |old|
      resource = old.resource("helper")
      raise "Expected historical resource" unless resource

      patch = resource.patches.fetch(0)
      [old.pkg_version.to_s, old.serialized_patches, patch.is_a?(ExternalPatch) && patch.resolves]
    end

    expect([result, Resource::Patch.new.respond_to?(:sha1)]).to eq [
      ["1.0", [{ "strip" => "p0", "url" => "https://brew.sh/patches.tar.gz", "sha256" => nil,
                  "apply" => ["CVE-2024-1234.patch"],
                  "resolves" => [{ "type" => "security", "id" => "CVE-2024-1234" }] }], ["CVE-2024-5678"]], false
    ]
  end

  it "retains the original load error and clears it after a successful or cached load" do
    current = formula("broken-history") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/broken-history-2.0.tar.gz"
    end
    versions = described_class.new(current)
    contents = <<~RUBY
      class BrokenHistory < Formula
        url "https://brew.sh/broken-history-1.0.tar.gz"
        unsupported_source_rewrite
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision)
      .and_return(contents, contents.sub("unsupported_source_rewrite", ""), contents)
    results = []
    %w[broken valid broken valid].each do |revision|
      value = versions.formula_at_revision(revision) { |old| old.pkg_version.to_s }
      results << [value, versions.load_error&.class, versions.load_error&.message]
    end

    expect(results).to match [
      [nil, NameError, /unsupported_source_rewrite/], ["1.0", nil, nil],
      [nil, NameError, /unsupported_source_rewrite/], ["1.0", nil, nil]
    ]
  end

  it "holds a historical formula that calls odie without terminating the caller" do
    current = formula("exiting-history") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/exiting-history-2.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(versions).to receive(:file_contents_at_revision).and_return(<<~RUBY)
      class ExitingHistory < Formula
        url "https://brew.sh/exiting-history-1.0.tar.gz"
        odie "historical option conflict"
      end
    RUBY

    results = Array.new(2) do
      value = versions.formula_at_revision("abc123") { |old| old.pkg_version.to_s }
      [value, versions.load_error&.class, versions.load_error&.message]
    end

    expect([results, Homebrew.failed?]).to match [
      Array.new(2) { [nil, FormulaSpecificationError, "historical option conflict"] }, false
    ]
  end

  it "does not swallow an exit requested by a caller after a successful historical load" do
    current = formula("caller-exit") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/caller-exit-1.0.tar.gz"
    end
    versions = described_class.new(current)
    allow(Formulary).to receive(:from_contents).and_return(current)
    allow(versions).to receive(:file_contents_at_revision).and_return("")

    expect { versions.formula_at_revision("abc123") { exit 1 } }.to raise_error(SystemExit)
  end

  it "loads historical formulae that use current bottle syntax" do
    digest = "b" * 64
    current = formula("current-bottle") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/current-bottle-2.0.tar.gz"

      bottle do
        sha256 cellar: :any, big_sur: digest
      end
    end
    versions = described_class.new(current)
    contents = <<~RUBY
      class CurrentBottle < Formula
        url "https://brew.sh/current-bottle-2.0.tar.gz"

        bottle do
          sha256 cellar: :any, big_sur: "#{digest}"
        end
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision).and_return(contents)

    result = versions.formula_at_revision("abc123") do |historical|
      tag = Utils::Bottles::Tag.from_symbol(:big_sur)
      tag_spec = historical.bottle_specification.tag_specification_for(tag)
      [historical.bottle_specification.class, tag_spec&.checksum&.hexdigest, tag_spec&.cellar,
       historical.bottle_specification == current.bottle_specification]
    end

    expect(result).to eq [FormulaVersions::LegacyBottleSpecification, digest, :any, true]
  end

  it "preserves historical source line numbers" do
    current = formula("source-lines") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/source-lines-2.0.tar.gz"
    end
    versions = described_class.new(current)
    contents = <<~RUBY
      class SourceLines < Formula
        url "https://brew.sh/source-lines-1.0.tar.gz"
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision).and_return(contents)
    loaded_contents = T.let("", String)
    allow(Formulary).to receive(:from_contents) do |_name, _path, loaded, **_options|
      loaded_contents = loaded
      current
    end

    versions.formula_at_revision("abc123") { nil }

    expect(loaded_contents.lines.index { |line| line.include?("class SourceLines") }).to eq 0
  end

  it "loads historical sources with embedded documentation" do
    current = formula("embedded-docs") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/embedded-docs-2.0.tar.gz"
    end
    versions = described_class.new(current)
    contents = <<~RUBY
      =begin
      Historical documentation.
      =end
      class EmbeddedDocs < Formula
        url "https://brew.sh/embedded-docs-1.0.tar.gz"
      end
    RUBY
    allow(versions).to receive(:file_contents_at_revision).and_return(contents)

    result = versions.formula_at_revision("abc123") { |historical| historical.class.superclass }

    expect(result).to eq described_class.legacy_formula_class
  end

  describe "#formula_at_revision error handling" do
    subject(:versions) { described_class.new(current) }

    let(:current) do
      formula("history-errors") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/history-errors-2.0.tar.gz"
      end
    end

    before do
      allow(versions).to receive(:file_contents_at_revision).and_return("")
    end

    it "skips unexpected standard errors while loading" do
      allow(Formulary).to receive(:from_contents).and_raise("boom")

      expect(versions.formula_at_revision("abc123") { raise "unreachable" }).to be_nil
    end

    it "skips unexpected script errors while loading" do
      allow(Formulary).to receive(:from_contents).and_raise(NotImplementedError, "boom")

      expect(versions.formula_at_revision("abc123") { raise "unreachable" }).to be_nil
    end

    it "does not skip macOS version errors while loading" do
      allow(Formulary).to receive(:from_contents).and_raise(MacOSVersion::Error.new(:unsupported))

      expect { versions.formula_at_revision("abc123") { raise "unreachable" } }
        .to raise_error(MacOSVersion::Error)
    end

    it "does not skip untrusted taps while loading" do
      allow(Formulary).to receive(:from_contents).and_raise(Homebrew::UntrustedTapError, "boom")

      expect { versions.formula_at_revision("abc123") { raise "unreachable" } }
        .to raise_error(Homebrew::UntrustedTapError, "boom")
    end

    it "does not skip disabled formula loading" do
      allow(Homebrew::EnvConfig).to receive(:disable_load_formula?).and_return(true)

      expect { versions.formula_at_revision("abc123") { raise "unreachable" } }
        .to raise_error(RuntimeError, /HOMEBREW_DISABLE_LOAD_FORMULA/)
    end

    it "does not skip errors from the history consumer" do
      allow(Formulary).to receive(:from_contents).and_return(current)

      expect { versions.formula_at_revision("abc123") { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")
    end

    it "does not skip process exits while loading" do
      allow(Formulary).to receive(:from_contents).and_raise(SystemExit, "boom")

      expect { versions.formula_at_revision("abc123") { raise "unreachable" } }
        .to raise_error(SystemExit, "boom")
    end
  end
end
