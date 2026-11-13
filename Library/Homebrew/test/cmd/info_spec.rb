# typed: false
# frozen_string_literal: true

require "cmd/info"
require "cmd/shared_examples/args_parse"
require "cask/info"

RSpec.describe Homebrew::Cmd::Info do
  before do
    allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)
  end

  RSpec::Matchers.define :a_json_string do
    match do |actual|
      JSON.parse(actual)
      true
    rescue JSON::ParserError
      false
    end
  end

  def installed_info_formula
    test_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end
    (HOMEBREW_CELLAR/"testball/0.1").mkpath
    test_formula
  end

  def installed_info_cask
    cask = Cask::Cask.new("local-transmission") do
      version "2.61"
      name "Transmission"
      desc "BitTorrent client"
      url "https://example.com/local-transmission.zip"
    end
    allow(cask).to receive(:installed_version).and_return("2.61")
    cask
  end

  it_behaves_like "parseable arguments"

  it "formats the common package summary" do
    test_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://example.com/testball-1.0.tar.gz"
      desc "Test formula"
      homepage "https://example.com/"
      license "MIT"
    end
    allow(Utils::InfoDisplay).to receive(:metadata_lines).with(test_formula).and_return(["Pinned: 1.0"])
    expect(Utils::InfoDisplay.package_summary(
             formula_or_cask:     test_formula,
             title:               Utils::InfoDisplay::Title.new(
               name:    "testball",
               version: "1.0",
               stable:  true,
             ),
             shadowed_by:         "homebrew/core",
             aliases:             ["tball"],
             old_names:           ["old-testball"],
             conflicts:           ["other"],
             installation_status: ["Installed (on request)"],
             source_url:          "https://github.com/user/repo/blob/HEAD/Formula/t/testball.rb",
             tap:                 Tap.fetch("example/tools"),
             license:             test_formula.license,
             installed_versions:  [],
             verbose:             false,
           )).to eq(
             [
               "==> testball: stable 1.0",
               Formatter.warning("`testball` shadows `homebrew/core/testball`.", label: "Warning"),
               "Test formula",
               Formatter.url("https://example.com/"),
               "Aliases: tball",
               "Old Names: old-testball",
               "Conflicts with:\n  other",
               "Installed (on request)",
               "From: #{Formatter.url("https://github.com/user/repo/blob/HEAD/Formula/t/testball.rb")}",
               "Tap: example/tools",
               "License: MIT",
               "Pinned: 1.0",
             ].join("\n"),
           )
  end

  context "when an installed cask is no longer available", :no_api do
    before do
      (Cask::Caskroom.path/"removed-cask/1.0").mkpath
      path = Cask::Caskroom.path/"removed-cask/.metadata/1.0/20250101000000.000/Casks/removed-cask.rb"
      path.dirname.mkpath
      path.write <<~RUBY
        cask "removed-cask" do
          version "1.0"
          sha256 :no_check
          url "https://example.com/removed-cask-1.0.zip"
          homepage "https://example.com/"
        end
      RUBY
    end

    test_each([[], ["--json=v2"], ["--sizes"]]) do |flags|
      it "shows the installed cask with #{flags.inspect}" do
        expect { described_class.new(["--cask", "removed-cask", *flags]).run }
          .to output(/removed-cask/).to_stdout
      end
    end
  end

  it "prints as json with the --json=v1 flag" do
    test_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end
    info = described_class.new(["--json=v1", "testball"])
    allow(info.args.named).to receive(:to_formulae).and_return([test_formula])

    expect { info.run }
      .to output(a_json_string).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints Formula and Cask JSON with the --json=v2 flag", :cask, :integration_test do
    setup_test_formula "testball"

    expect { brew "info", "testball", "local-caffeine", "--json=v2" }
      .to output(a_json_string).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "does not include installed casks in formula JSON" do
    formula = installed_info_formula

    allow(Formula).to receive(:installed).and_return([formula])
    expect(Cask::Caskroom).not_to receive(:casks)

    output = +""
    expect { described_class.new(["--json=v2", "--installed", "--formula"]).run }
      .to output(satisfy { |s|
        output << s
        true
      }).to_stdout
        .and not_to_output.to_stderr

    json = JSON.parse(output)
    expect(json["formulae"].length).to eq(1)
    expect(json["casks"]).to be_empty
  end

  it "does not include casks in formula JSON for all packages" do
    formula = installed_info_formula

    allow(Formula).to receive(:all).and_return([formula])
    expect(Cask::Cask).not_to receive(:all)

    output = +""
    expect { described_class.new(["--json=v2", "--formula"]).run }
      .to output(satisfy { |s|
        output << s
        true
      }).to_stdout
        .and not_to_output.to_stderr

    json = JSON.parse(output)
    expect(json["formulae"].length).to eq(1)
    expect(json["casks"]).to be_empty
  end

  it "prints installed formulae in a human-readable inventory" do
    mktmpdir do |dir|
      tabfile = dir/AbstractTab::FILENAME
      tabfile.write("{}")
      formula = installed_info_formula

      allow(Formula).to receive(:installed).and_return([formula])
      allow(Tab).to receive(:for_formula).with(formula).and_return(
        Tab.new(installed_on_request: true, source: { "tap" => "homebrew/core" }, tabfile:),
      )
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      expected_output = <<~EOS
        ==> testball: Some test
        Formula from homebrew/core
        Installed: 0.1 (on request)
      EOS
      expect { described_class.new(["--installed"]).run }
        .to output(expected_output).to_stdout
        .and not_to_output.to_stderr
    end
  end

  it "prints installed casks in a human-readable inventory" do
    mktmpdir do |dir|
      tabfile = dir/AbstractTab::FILENAME
      tabfile.write("{}")
      cask = installed_info_cask

      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(
        Cask::Tab.new(installed_on_request: false, source: { "tap" => "homebrew/cask" }, tabfile:),
      )

      expected_output = <<~EOS
        ==> local-transmission: (Transmission) BitTorrent client
        Cask from homebrew/cask
        Installed: 2.61 (dependency)
      EOS
      expect { described_class.new(["--installed"]).run }
        .to output(expected_output).to_stdout
        .and not_to_output.to_stderr
    end
  end

  it "omits missing cask descriptions from the installed inventory" do
    mktmpdir do |dir|
      tabfile = dir/AbstractTab::FILENAME
      tabfile.write("{}")
      cask = Cask::Cask.new("no-description") do
        version "1.0"
        name "No Description"
        url "https://example.com/no-description.zip"
      end
      allow(cask).to receive(:installed_version).and_return("1.0")

      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(
        Cask::Tab.new(source: { "tap" => "homebrew/cask" }, tabfile:),
      )

      expected_output = <<~EOS
        ==> no-description
        Cask from homebrew/cask
        Installed: 1.0
      EOS
      expect { described_class.new(["--installed"]).run }
        .to output(expected_output).to_stdout
        .and not_to_output.to_stderr
    end
  end

  it "omits install reason when receipt intent is unavailable" do
    mktmpdir do |dir|
      tabfile = dir/AbstractTab::FILENAME
      tabfile.write("{}")
      formula = installed_info_formula
      cask = installed_info_cask

      allow(Formula).to receive(:installed).and_return([formula])
      allow(Tab).to receive(:for_formula).with(formula).and_return(
        Tab.new(source: { "tap" => "homebrew/core" }, tabfile:),
      )
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(
        Cask::Tab.new(source: { "tap" => "homebrew/cask" }, tabfile:),
      )

      expected_output = <<~EOS
        ==> testball: Some test
        Formula from homebrew/core
        Installed: 0.1

        ==> local-transmission: (Transmission) BitTorrent client
        Cask from homebrew/cask
        Installed: 2.61
      EOS
      expect { described_class.new(["--installed"]).run }
        .to output(expected_output).to_stdout
        .and not_to_output.to_stderr
    end
  end

  it "marks installed formulae in interactive inventory output" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    mktmpdir do |dir|
      tabfile = dir/AbstractTab::FILENAME
      tabfile.write("{}")
      formula = installed_info_formula

      allow(Formula).to receive(:installed).and_return([formula])
      allow(Tab).to receive(:for_formula).with(formula).and_return(
        Tab.new(installed_on_request: true, source: { "tap" => "homebrew/core" }, tabfile:),
      )
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      expect { described_class.new(["--installed"]).run }
        .to output(/testball .*✔.*: Some test/).to_stdout
        .and not_to_output.to_stderr
    end
  end

  it "prints verbose installed inventory as full info" do
    info = described_class.new(["--verbose", "--installed"])
    formula = installed_info_formula
    cask = installed_info_cask

    allow(Formula).to receive(:installed).and_return([formula])
    allow(Cask::Caskroom).to receive(:casks).and_return([cask])
    expect(info).to receive(:info_formula).with(formula, shadowed_by: nil)
    expect(info).to receive(:info_cask).with(cask)

    expect { info.run }
      .to output("\n").to_stdout
      .and not_to_output.to_stderr
  end

  it "uses matching casks in each verbose inventory summary" do
    casks = %w[example example@dev].map do |token|
      cask = Cask::Cask.new(token) { version "1.0" }
      (Cask::Caskroom.path/token/"1.0").mkpath
      allow(cask).to receive_messages(installed?: true, installed_version: "1.0", outdated?: false)
      cask
    end
    allow(Cask::Tab).to receive(:for_cask).and_return(Cask::Tab.empty)
    allow(Cask::Info).to receive(:repo_url).and_return(nil)
    expect(Cask::Caskroom).to receive(:casks).with(no_args).once.and_return(casks)
    expect(Cask::Caskroom).to receive(:casks).with(tokens: contain_exactly("example", "example@dev"))
                                             .twice.and_return(casks)

    expect { described_class.new(["--installed", "--cask", "--verbose"]).run }.to output(<<~EOS).to_stdout
      ==> example: 1.0
      Installed (as dependency)
      ==> Installed Versions
      example     1.0 (0B)
        Caskroom: #{Cask::Caskroom.path}/example/1.0
      example@dev 1.0 (0B)
        Caskroom: #{Cask::Caskroom.path}/example@dev/1.0

      ==> example@dev: 1.0
      Installed (as dependency)
      ==> Installed Versions
      example     1.0 (0B)
        Caskroom: #{Cask::Caskroom.path}/example/1.0
      example@dev 1.0 (0B)
        Caskroom: #{Cask::Caskroom.path}/example@dev/1.0
    EOS
  end

  it "prints quiet formula information in the slim inventory format" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")

    expected_output = <<~EOS
      ==> testball: Some test
      Formula from https://example.com/testball.rb
      Not installed
    EOS
    expect { info.info_formula_summary(formula) }
      .to output(expected_output).to_stdout
      .and not_to_output.to_stderr
  end

  it "uses slim formula information when quiet is passed" do
    test_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end
    info = described_class.new(["--quiet", "testball"])
    allow(info.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([test_formula])

    expect(info).to receive(:info_formula_summary).with(test_formula)
    expect { info.run }
      .to not_to_output.to_stderr
  end

  describe "complete formula information" do
    let(:test_formula) do
      formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/testball-1.0.tar.gz"
        homepage "https://example.com/testball"
        desc "A test formula"
        license "MIT"
      end
    end
    let(:keg_path) { HOMEBREW_CELLAR/"testball/1.0" }

    before do
      (keg_path/"bin").mkpath
      (keg_path/"bin/testball").write("#!/bin/sh\n")
      (keg_path/"bin/testball").chmod(0755)
      tab = Tab.empty
      tab.tabfile = keg_path/AbstractTab::FILENAME
      tab.write

      allow(info).to receive(:github_info).with(test_formula).and_return("https://example.com/testball.rb")
      allow(test_formula).to receive_messages(
        core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false, versioned_formulae: [],
      )
      allow_any_instance_of(Keg).to receive(:abv).and_return("2 files, 1.1KB")
    end

    context "without --verbose" do
      let(:info) { described_class.new([]) }

      it "prints the complete output" do
        expected_output = <<~EOS
          ==> testball: stable 1.0
          A test formula
          https://example.com/testball
          Installed (as dependency)
          From: https://example.com/testball.rb
          License: MIT
          ==> Installed Versions
          testball 1.0 (2 files, 1.1KB)
        EOS
        expect { info.info_formula(test_formula) }
          .to output(expected_output).to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "with --verbose" do
      let(:info) { described_class.new(["--verbose"]) }

      it "prints the complete output" do
        expected_output = <<~EOS
          ==> testball: stable 1.0
          A test formula
          https://example.com/testball
          Installed (as dependency)
          From: https://example.com/testball.rb
          License: MIT
          ==> Installed Kegs and Versions
          testball 1.0 (2 files, 1.1KB)
            Cellar: #{keg_path}
            Built from source
          ==> Binaries
          testball
        EOS
        expect { info.info_formula(test_formula) }
          .to output(expected_output).to_stdout
          .and not_to_output.to_stderr
      end
    end
  end

  it "prints inline summary information for formulae" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      option "with-foo", "Build with foo"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Installs from source: yes/).to_stdout
      .and not_to_output(/Metadata/).to_stdout
      .and not_to_output(/supports macOS and Linux/).to_stdout
      .and not_to_output.to_stderr
  end

  it "shows deprecation before formula aliases and conflicts" do
    info = described_class.new([])
    test_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://example.com/testball-1.0.tar.gz"
      homepage "https://example.com/testball"
      desc "A test formula"
      conflicts_with "other"
    end
    allow(test_formula).to receive_messages(aliases: ["alias"], oldnames: [], core_formula?: false)
    allow(DeprecateDisable).to receive(:message).with(test_formula) { +"deprecated!\nReplacement:\n  example\n" }
    allow(info).to receive(:github_info).with(test_formula).and_return("https://example.com/testball.rb")

    expected_output = <<~EOS
      ==> testball: stable 1.0
      A test formula
      https://example.com/testball
      Deprecated!
      Replacement:
        example
      Aliases: alias
      Conflicts with:
        other
      Not installed
      From: https://example.com/testball.rb
    EOS
    expect { info.info_formula(test_formula) }.to output(expected_output).to_stdout
  end

  test_each([
    ["macOS", true, false, MacOSRequirement],
    ["Linux", false, true, LinuxRequirement],
    ["generic OS", false, false, nil],
  ]) do |(os, macos, linux, requirement_class)|
    it "shows build dependencies for an uninstalled formula without a bottle on #{os}" do
      info = described_class.new([])
      formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
        depends_on "builddep" => :build
      end
      allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
      allow(Homebrew::SimulateSystem).to receive_messages(simulating_or_running_on_macos?: macos,
                                                          simulating_or_running_on_linux?: linux)
      allow(formula).to receive(:requirements).and_return(requirement_class ? [requirement_class.new] : [])

      expect { info.info_formula(formula) }
        .to output(/Build \(1\): builddep/).to_stdout
    end
  end

  it "shows a conflict by its resolved full name" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      conflicts_with "other"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    other = formula("other") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/other-0.1.tar.gz"
    end
    allow(other).to receive(:full_name).and_return("someuser/tap/other")
    allow(Formulary).to receive(:factory).with("other").and_return(other)

    expect { info.info_formula(formula) }
      .to output(%r{Conflicts with:\n  someuser/tap/other}).to_stdout
  end

  it "omits a stale conflict that resolves to the formula itself" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      conflicts_with "testball"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(Formulary).to receive(:factory).with("testball").and_return(formula)

    expect { info.info_formula(formula) }
      .not_to output(/Conflicts with:/).to_stdout
  end

  it "marks a deprecated formula with `(deprecated)` in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
      deprecate! date: "2024-01-01", because: :versioned_formula
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/==> .*testball.*\(deprecated\):/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a disabled formula with `(disabled)` in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
      disable! date: "2024-01-01", because: :unmaintained
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/==> .*testball.*\(disabled\):/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an installed formula removed from its tap with `(removed from tap)` in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    allow_any_instance_of(Keg).to receive(:deleted_formula?).and_return(true)

    info = described_class.new([])
    formula = installed_info_formula
    (HOMEBREW_CELLAR/"testball/0.1"/AbstractTab::FILENAME).write({ source: { tap: "homebrew/core" } }.to_json)
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/==> .*testball.*\(removed from tap\):/).to_stdout
      .and not_to_output.to_stderr
  end

  it "does not mark a formula as removed from tap when its keg came from another tap" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    allow_any_instance_of(Keg).to receive(:deleted_formula?).and_return(true)

    info = described_class.new([])
    formula = installed_info_formula
    (HOMEBREW_CELLAR/"testball/0.1"/AbstractTab::FILENAME).write({ source: { tap: "alice/tools" } }.to_json)
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .not_to output(/removed from tap/).to_stdout
  end

  it "does not mark an installed formula without a tap as removed from tap" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    allow_any_instance_of(Keg).to receive(:deleted_formula?).and_return(true)

    info = described_class.new([])
    formula = installed_info_formula
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new],
                                       tap: nil, versioned_formulae: [])

    expect { info.info_formula(formula) }
      .not_to output(/removed from tap/).to_stdout
  end

  it "shows separate blocks for an unqualified and a qualified input that resolve to the same shadowed formula" do
    info = described_class.new([])
    core = installed_info_formula
    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.source["tap"] = "ataraxy-labs/tap"
    tab.write
    allow(core).to receive(:tap).and_return(Tap.fetch("homebrew/core"))
    installed = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(installed).to receive_messages(tap: Tap.fetch("ataraxy-labs/tap"), full_name: "ataraxy-labs/tap/testball")
    allow(Formulary).to receive(:factory).with("ataraxy-labs/tap/testball").and_return(installed)
    allow(info).to receive(:github_info).and_return("https://example.com/testball.rb")
    allow(info.args.named).to receive_messages(
      downcased_unique_named:                ["testball", "homebrew/core/testball"],
      to_formulae_and_casks_and_unavailable: [core, core],
    )

    expect { info.print_info }
      .to output(%r{ataraxy-labs/tap/testball.*homebrew/core/testball.*Not installed}m).to_stdout
  end

  it "reports an unavailable name without raising" do
    info = described_class.new([])
    error = FormulaOrCaskUnavailableError.new("nonexistent-formula")
    allow(info.args.named).to receive_messages(
      downcased_unique_named:                ["nonexistent-formula"],
      to_formulae_and_casks_and_unavailable: [error],
    )

    expect { info.print_info }
      .to output(/No available formula or cask with the name "nonexistent-formula"/).to_stderr
  end

  it "qualifies the name, reports not installed and shows the shadowing keg when the keg belongs to another tap" do
    info = described_class.new([])
    formula = installed_info_formula
    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.source["tap"] = "ataraxy-labs/tap"
    tab.write
    allow(formula).to receive(:tap).and_return(Tap.fetch("homebrew/core"))
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    shadowing = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(shadowing).to receive_messages(tap: Tap.fetch("ataraxy-labs/tap"), full_name: "ataraxy-labs/tap/testball")
    allow(Formulary).to receive(:factory).with("ataraxy-labs/tap/testball").and_return(shadowing)

    expect { info.info_formula(formula) }
      .to output(%r{homebrew/core/testball.*Not installed.*ataraxy-labs/tap/testball}m).to_stdout
  end

  it "reloads the formula from the install receipt's tap and reports the shadowing tap" do
    info = described_class.new([])
    formula = installed_info_formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.source["tap"] = "ataraxy-labs/tap"
    tab.write

    shadowing_tap = Tap.fetch("homebrew/core")
    allow(formula).to receive(:tap).and_return(shadowing_tap)
    keg_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(Formulary).to receive(:factory).with("ataraxy-labs/tap/testball").and_return(keg_formula)

    expect(info.installed_resolution(formula)).to eq([keg_formula, shadowing_tap])
  end

  it "resolves the keg's own name when it differs from the formula (installed via alias)" do
    info = described_class.new([])
    formula = installed_info_formula
    tab = instance_double(Tab, tap: Tap.fetch("stripe/stripe-cli"))
    keg = instance_double(Keg, name: "stripe", tab:)
    allow(formula).to receive_messages(tap: Tap.fetch("homebrew/core"), installed_kegs: [keg])
    keg_formula = formula("stripe") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/stripe-1.0.tar.gz"
    end
    allow(Formulary).to receive(:factory).with("stripe/stripe-cli/stripe").and_return(keg_formula)

    expect(info.installed_resolution(formula)).to eq([keg_formula, Tap.fetch("homebrew/core")])
  end

  it "returns the original formula and no shadowing tap when the install receipt has no tap" do
    info = described_class.new([])
    formula = installed_info_formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    expect(info.installed_resolution(formula)).to eq([formula, nil])
  end

  it "returns the original formula and no shadowing tap when the install receipt's tap matches" do
    info = described_class.new([])
    formula = installed_info_formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.source["tap"] = "homebrew/core"
    tab.write

    allow(formula).to receive(:tap).and_return(Tap.fetch("homebrew/core"))
    expect(info.installed_resolution(formula)).to eq([formula, nil])
  end

  it "warns about a shadowing tap when info_formula is given one" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula, shadowed_by: Tap.fetch("homebrew/core")) }
      .to output(%r{Warning: `testball` shadows `homebrew/core/testball`}).to_stdout
      .and not_to_output.to_stderr
  end

  it "treats a `tap/name` input as user-qualified" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(formula).to receive(:tap).and_return(Tap.fetch("homebrew/core"))

    qualified = Set["homebrew/core/testball"]
    expect(info.formula_qualified_by_user?(formula, qualified)).to be(true)
  end

  it "treats a bare unqualified input as not user-qualified" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end

    expect(info.formula_qualified_by_user?(formula, Set.new)).to be(false)
  end

  it "--json swaps an unqualified-input formula to its installed tap" do
    info = described_class.new(["--json", "testball"])
    shadowed_formula = installed_info_formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.source["tap"] = "ataraxy-labs/tap"
    tab.write

    allow(shadowed_formula).to receive(:tap).and_return(Tap.fetch("homebrew/core"))
    installed_formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(installed_formula).to receive(:tap).and_return(Tap.fetch("ataraxy-labs/tap"))
    allow(info.args.named).to receive(:to_formulae).and_return([shadowed_formula])
    allow(Formulary).to receive(:factory).with("ataraxy-labs/tap/testball").and_return(installed_formula)

    output = +""
    expect { info.run }.to output(satisfy { |s|
      output << s
      true
    }).to_stdout
    expect(JSON.parse(output).first["tap"]).to eq("ataraxy-labs/tap")
  end

  it "--json honours a tap-qualified input without swapping" do
    info = described_class.new(["--json", "homebrew/core/testball"])
    formula = installed_info_formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.source["tap"] = "ataraxy-labs/tap"
    tab.write

    allow(formula).to receive(:tap).and_return(Tap.fetch("homebrew/core"))
    allow(info.args.named).to receive(:to_formulae).and_return([formula])

    output = +""
    expect { info.run }.to output(satisfy { |s|
      output << s
      true
    }).to_stdout
    expect(JSON.parse(output).first["tap"]).to eq("homebrew/core")
  end

  it "prints required, recursive runtime, and dependent counts in the dependencies section" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      depends_on "bar"
    end
    direct_dependency = formula.deps.required.first

    # Simulate an installed keg with tab runtime dependencies
    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [
      { "full_name" => "installed-dep", "version" => "1.0" },
      { "full_name" => "missing-dep", "version" => "2.0" },
    ]
    tab.write

    # Create a rack for the installed dependency
    installed_dep_path = HOMEBREW_CELLAR/"installed-dep/1.0"
    installed_dep_path.mkpath
    installed_dep_tab = Tab.empty
    installed_dep_tab.tabfile = installed_dep_path/AbstractTab::FILENAME
    installed_dep_tab.write

    # Create a dependent keg whose tab references testball
    dependent_keg_path = HOMEBREW_CELLAR/"some-dependent/1.0"
    dependent_keg_path.mkpath
    dependent_tab = Tab.empty
    dependent_tab.tabfile = dependent_keg_path/AbstractTab::FILENAME
    dependent_tab.runtime_dependencies = [
      { "full_name" => "testball", "version" => "0.1" },
    ]
    dependent_tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false)
    allow(direct_dependency).to receive(:satisfied?).and_return(true)

    expected_output = Regexp.new(
      "==> Dependencies\nRequired \\(1\\): .*bar.*\n" \
      "Recursive Runtime \\(2\\): 1 installed .*✔, 1 missing .*✘\nDependents: 1",
    )
    expect { info.info_formula(formula) }
      .to output(expected_output).to_stdout
      .and not_to_output(/^Dependencies: /).to_stdout
      .and not_to_output.to_stderr
  end

  it "lists installed dependents inline under Dependencies with --verbose" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new(["--verbose"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    %w[some-dependent another-dependent].each do |dependent_name|
      dependent_keg_path = HOMEBREW_CELLAR/"#{dependent_name}/1.0"
      dependent_keg_path.mkpath
      dependent_tab = Tab.empty
      dependent_tab.tabfile = dependent_keg_path/AbstractTab::FILENAME
      dependent_tab.runtime_dependencies = [
        { "full_name" => "testball", "version" => "0.1" },
      ]
      dependent_tab.write
    end

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/^Dependents \(2\): another-dependent, some-dependent$/).to_stdout
      .and not_to_output(/^Dependents: /).to_stdout
      .and not_to_output.to_stderr
  end

  it "lists installed dependents whose receipts use another name of the formula" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new(["--verbose"])
    formula = formula("testball@2") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-2.0.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/1.0"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    {
      "alias-dependent"     => "testball",
      "oldname-dependent"   => "old-testball",
      "qualified-dependent" => "homebrew/core/testball",
      "other-dependent"     => "other-formula",
    }.each do |dependent_name, dependency_name|
      dependent_keg_path = HOMEBREW_CELLAR/"#{dependent_name}/1.0"
      dependent_keg_path.mkpath
      dependent_tab = Tab.empty
      dependent_tab.tabfile = dependent_keg_path/AbstractTab::FILENAME
      dependent_tab.runtime_dependencies = [
        { "full_name" => dependency_name, "version" => "1.0" },
      ]
      dependent_tab.write
    end

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(aliases: ["testball"], core_formula?: false,
                                       missing_library_linkage: [[], Set.new], oldnames: ["old-testball"])

    expect { info.info_formula(formula) }
      .to output(/^Dependents \(3\): alias-dependent, oldname-dependent, qualified-dependent$/).to_stdout
      .and not_to_output.to_stderr
  end

  it "falls back to formula definitions only for installed dependents whose receipts have no list" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new(["--verbose"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end
    stub_formula_loader formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    { "no-list-dependent" => nil, "stale-list-dependent" => [] }.each do |dependent_name, runtime_dependencies|
      stub_formula_loader(formula(dependent_name) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/#{dependent_name}-1.0.tar.gz"

        depends_on "testball"
      end)

      dependent_keg_path = HOMEBREW_CELLAR/"#{dependent_name}/1.0"
      dependent_keg_path.mkpath
      dependent_tab = Tab.empty
      dependent_tab.tabfile = dependent_keg_path/AbstractTab::FILENAME
      dependent_tab.runtime_dependencies = runtime_dependencies
      dependent_tab.write
    end

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/^Dependents \(1\): no-list-dependent$/).to_stdout
      .and not_to_output.to_stderr
  end

  it "skips installed dependents whose receipts have no list when their formula lookup is ambiguous" do
    keg_path = HOMEBREW_CELLAR/"ambiguous-dependent/1.0"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    allow(Formulary).to receive(:loader_for).and_call_original
    allow(Formulary).to receive(:loader_for).with("ambiguous-dependent", any_args)
                                            .and_raise(TapFormulaAmbiguityError.new("ambiguous-dependent", []))

    expect(described_class.installed_dependent_names(["testball"])).to be_empty
  end

  it "skips installed dependents with malformed receipts" do
    malformed_keg_path = HOMEBREW_CELLAR/"malformed-dependent/1.0"
    malformed_keg_path.mkpath
    (malformed_keg_path/AbstractTab::FILENAME).write("{")

    dependent_keg_path = HOMEBREW_CELLAR/"valid-dependent/1.0"
    dependent_keg_path.mkpath
    dependent_tab = Tab.empty
    dependent_tab.tabfile = dependent_keg_path/AbstractTab::FILENAME
    dependent_tab.runtime_dependencies = [{ "full_name" => "testball" }]
    dependent_tab.write

    expect(described_class.installed_dependent_names(["testball"])).to eq(["valid-dependent"])
  end

  it "uses formula dependencies without rereading the receipt when the list is missing" do
    rack = HOMEBREW_CELLAR/"dependent"
    keg_path = rack/"1.0"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    keg = Keg.new(keg_path)
    dependent_formula = formula("dependent", path: keg_path/"dependent.rb") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/dependent-1.0.tar.gz"
    end

    allow(Formula).to receive(:racks).and_return([rack])
    allow(Keg).to receive(:from_rack).with(rack).and_return(keg)
    allow(keg).to receive(:to_formula).and_return(dependent_formula)
    allow(dependent_formula).to receive_messages(declared_runtime_dependencies:   [Dependency.new("testball")],
                                                 undeclared_runtime_dependencies: [])
    expect(dependent_formula).to receive(:runtime_dependencies)
      .with(keg:)
      .and_call_original

    expect(described_class.installed_dependent_names(["testball"])).to eq(["dependent"])
  end

  it "skips installed kegs from untrusted taps whose receipts have no list", :trust_store do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new(["--verbose"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.path/"Formula/untrusted.rb"
    formula_path.dirname.mkpath
    formula_path.write <<~RUBY
      class Untrusted < Formula
        url "https://brew.sh/untrusted-1.0.tar.gz"
      end
    RUBY

    untrusted_keg_path = HOMEBREW_CELLAR/"untrusted/1.0"
    untrusted_keg_path.mkpath
    untrusted_tab = Tab.empty
    untrusted_tab.tabfile = untrusted_keg_path/AbstractTab::FILENAME
    untrusted_tab.tap = tap
    untrusted_tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/^==> Installed Kegs and Versions$/).to_stdout
      .and not_to_output(/^Dependents/).to_stdout
      .and not_to_output.to_stderr
  ensure
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "summarises recursive runtime dependencies as all installed when none are missing" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      depends_on "bar"
    end
    direct_dependency = formula.deps.required.first

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [{ "full_name" => "installed-dep", "version" => "1.0" }]
    tab.write

    installed_dep_path = HOMEBREW_CELLAR/"installed-dep/1.0"
    installed_dep_path.mkpath
    installed_dep_tab = Tab.empty
    installed_dep_tab.tabfile = installed_dep_path/AbstractTab::FILENAME
    installed_dep_tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false)
    allow(direct_dependency).to receive(:satisfied?).and_return(true)

    expect { info.info_formula(formula) }
      .to output(/Recursive Runtime \(1\): all installed .*✔/).to_stdout
      .and not_to_output(/missing/).to_stdout
      .and not_to_output.to_stderr
  end

  it "counts recursive runtime dependencies of the latest version when the formula is outdated" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = %w[installed-dep missing-dep dropped-dep].map do |name|
      { "full_name" => name, "version" => "1.0" }
    end
    tab.write

    %w[installed-dep dropped-dep].each { (HOMEBREW_CELLAR/it/"1.0").mkpath }

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: true)
    latest_runtime_deps = %w[installed-dep missing-dep new-dep].map { Dependency.new(it) }
    allow(formula).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false)
                                                    .and_return(latest_runtime_deps)

    expect { info.info_formula(formula) }
      .to output(/Recursive Runtime \(3\): 1 installed .*✔.*, 2 not installed\n/).to_stdout
      .and not_to_output(/✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "counts recursive runtime dependencies of the latest version when the outdated keg's tab has none" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = []
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: true)
    allow(formula).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false)
                                                    .and_return([Dependency.new("new-dep")])

    expect { info.info_formula(formula) }
      .to output(/==> Dependencies\nRecursive Runtime \(1\): 0 installed .*✔.*, 1 not installed\n/).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits recursive runtime dependencies when those of the latest version cannot be determined" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [{ "full_name" => "old-dep", "version" => "1.0" }]
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: true)
    allow(formula).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false).and_return([])

    expect { info.info_formula(formula) }
      .to not_to_output(/Recursive Runtime/).to_stdout
      .and not_to_output.to_stderr
  end

  it "lists missing libraries when there are no dependencies to show" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [{ "full_name" => "old-dep", "version" => "1.0" }]
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [["libfoo.1.dylib"], Set.new],
                                       outdated?: true)
    allow(formula).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false).and_return([])

    expect { info.info_formula(formula) }
      .to output(/==> Dependencies\nMissing libraries \(1\): .*libfoo\.1\.dylib/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a tab-listed dep with no installed rack as unsatisfied" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [{ "full_name" => "bar", "version" => "1.0", "pkg_version" => "1.0" }]
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a tab-listed dep with an installed rack as satisfied when the dep formula is not outdated" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end
    direct_dependency = formula.deps.required.first

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [{ "full_name" => "bar", "version" => "1.0", "pkg_version" => "1.0" }]
    tab.write

    bar_keg_path = HOMEBREW_CELLAR/"bar/1.0"
    bar_keg_path.mkpath
    bar_tab = Tab.empty
    bar_tab.tabfile = bar_keg_path/AbstractTab::FILENAME
    bar_tab.write

    bar_formula = instance_double(Formula, outdated?: false)
    allow(direct_dependency).to receive(:to_formula).and_return(bar_formula)

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false)

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*✔/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a tab-listed dep with an installed rack as outdated when the dep formula is outdated" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end
    direct_dependency = formula.deps.required.first

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = [{ "full_name" => "bar", "version" => "1.0", "pkg_version" => "1.0" }]
    tab.write

    bar_keg_path = HOMEBREW_CELLAR/"bar/1.0"
    bar_keg_path.mkpath
    bar_tab = Tab.empty
    bar_tab.tabfile = bar_keg_path/AbstractTab::FILENAME
    bar_tab.write

    bar_formula = instance_double(Formula, outdated?: true)
    allow(direct_dependency).to receive(:to_formula).and_return(bar_formula)

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false)

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*↑/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an installed dep on an uninstalled formula as satisfied" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end
    direct_dependency = formula.deps.required.first

    bar_keg_path = HOMEBREW_CELLAR/"bar/1.0"
    bar_keg_path.mkpath
    bar_tab = Tab.empty
    bar_tab.tabfile = bar_keg_path/AbstractTab::FILENAME
    bar_tab.write

    bar_formula = instance_double(Formula, outdated?: false)
    allow(direct_dependency).to receive(:to_formula).and_return(bar_formula)

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*✔/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an outdated installed dep on an uninstalled formula as upgradable" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end
    direct_dependency = formula.deps.required.first

    bar_keg_path = HOMEBREW_CELLAR/"bar/1.0"
    bar_keg_path.mkpath
    bar_tab = Tab.empty
    bar_tab.tabfile = bar_keg_path/AbstractTab::FILENAME
    bar_tab.write

    bar_formula = instance_double(Formula, outdated?: true)
    allow(direct_dependency).to receive(:to_formula).and_return(bar_formula)

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*↑/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an aliased dep as installed when the underlying rack exists under a different name" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "pkg-config"
    end
    direct_dependency = formula.deps.required.first

    pkgconf_keg_path = HOMEBREW_CELLAR/"pkgconf/2.5.1"
    pkgconf_keg_path.mkpath
    pkgconf_tab = Tab.empty
    pkgconf_tab.tabfile = pkgconf_keg_path/AbstractTab::FILENAME
    pkgconf_tab.write

    pkgconf_formula = instance_double(Formula, any_version_installed?: true, outdated?: false)
    allow(direct_dependency).to receive(:to_formula).and_return(pkgconf_formula)

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*pkg-config.*✔/).to_stdout
      .and not_to_output.to_stderr
  end

  it "does not mark a missing dep on an uninstalled formula" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): bar\n/).to_stdout
      .and not_to_output.to_stderr
  end

  it "does not mark a dep absent from the installed keg's tab as unsatisfied when the formula is outdated" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = []
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: true)

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): bar\n/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a dep absent from the installed keg's tab as unsatisfied when the formula is up to date" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = []
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false)

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "never marks a missing recommended or optional dependency with a red X" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar" => :recommended
      depends_on "baz" => :optional
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new], outdated?: false)

    expect { info.info_formula(formula) }
      .to output(/Recommended \(1\): bar\nOptional \(1\): baz\n/).to_stdout
      .and not_to_output(/✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a dep absent from the installed keg's tab as installed when its rack exists" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.runtime_dependencies = []
    tab.write

    bar_keg_path = HOMEBREW_CELLAR/"bar/1.0"
    bar_keg_path.mkpath
    bar_tab = Tab.empty
    bar_tab.tabfile = bar_keg_path/AbstractTab::FILENAME
    bar_tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(/Required \(1\): .*bar.*↑/).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits build dependencies when a formula would pour from a bottle" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      depends_on "bar" => :build
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(
      core_formula?:          false,
      recursive_dependencies: [],
      stable:                 instance_double(
        SoftwareSpec,
        version:  Version.new("0.1"),
        bottled?: true,
      ),
      pour_bottle?:           true,
    )

    expect { info.info_formula(formula) }
      .to not_to_output(/Build \(1\): .*bar.*/).to_stdout
      .and not_to_output(/==> Dependencies/).to_stdout
      .and not_to_output.to_stderr
  end

  it "shows the installed and stable versions in the headline when outdated" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
      revision 1
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, outdated?: true)

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    expect { info.info_formula(formula) }
      .to output(/\A==> testball: 0\.1 → stable 0\.1_1\n/).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints Linux requirements through the requirements section" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(
      core_formula?: false,
      requirements:  Requirements.new(LinuxRequirement.new),
    )

    expect { info.info_formula(formula) }
      .to output(/Requirements\nRequired: .*Linux/).to_stdout
      .and not_to_output(/supports Linux/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an unsatisfied architecture requirement on an uninstalled formula" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end
    requirement = ArchRequirement.new([:arm64])
    allow(requirement).to receive(:satisfied?).and_return(false)
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(
      core_formula?: false,
      requirements:  Requirements.new(requirement),
    )

    expect { info.info_formula(formula) }
      .to output(/Required: .*arm64 architecture.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an unsatisfied OS requirement on an uninstalled formula" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end
    other_os_requirement = OS.mac? ? LinuxRequirement.new : MacOSRequirement.new
    other_os = OS.mac? ? "Linux" : "macOS"
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(
      core_formula?: false,
      requirements:  Requirements.new(other_os_requirement),
    )

    expect { info.info_formula(formula) }
      .to output(/Required: .*#{other_os}.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "keeps a satisfied requirement marked on an uninstalled formula" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end
    requirement = ArchRequirement.new([:arm64])
    allow(requirement).to receive(:satisfied?).and_return(true)
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(
      core_formula?: false,
      requirements:  Requirements.new(requirement),
    )

    expect { info.info_formula(formula) }
      .to output(/Required: .*arm64 architecture.*✔/).to_stdout
      .and not_to_output.to_stderr
  end

  it "hides source install metadata for formulae that only run on another OS" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end
    os_requirement = OS.mac? ? LinuxRequirement.new : MacOSRequirement.new([:sonoma])
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(
      core_formula?: false,
      requirements:  Requirements.new(os_requirement),
    )

    expect { info.info_formula(formula) }
      .to not_to_output(/Installs from source: yes/).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints a Binaries section listing executables in bin and sbin with --verbose" do
    info = described_class.new(["--verbose"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    (keg_path/"bin").mkpath
    (keg_path/"sbin").mkpath
    ["bin/testball", "bin/another", "sbin/daemon"].each do |rel|
      file = keg_path/rel
      file.write("#!/bin/sh\n")
      file.chmod(0755)
    end
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to output(a_string_including("==> Binaries\nanother\ndaemon\ntestball\n")).to_stdout
      .and not_to_output.to_stderr
  end

  describe "shadowed executables" do
    let(:testball) do
      formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
      end
    end
    let(:shadowed_text) do
      "The following testball executables are shadowed by commands in /usr/local/bin:\ntestball\n"
    end

    before do
      keg_path = HOMEBREW_CELLAR/"testball/0.1"
      (keg_path/"bin").mkpath
      %w[testball another].each do |name|
        file = keg_path/"bin"/name
        file.write("#!/bin/sh\n")
        file.chmod(0755)
      end
      tab = Tab.empty
      tab.tabfile = keg_path/AbstractTab::FILENAME
      tab.write
      testball.opt_prefix.parent.mkpath
      FileUtils.ln_s(keg_path, testball.opt_prefix)

      shadower = Pathname.new("/usr/local/bin/testball")
      allow(shadower).to receive(:realpath).and_return(shadower)
      allow_any_instance_of(Object).to receive(:which).and_call_original
      allow_any_instance_of(Object).to receive(:which).with("testball", ORIGINAL_PATHS).and_return(shadower)
      allow(testball).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])
    end

    it "lists them in the Caveats without --verbose" do
      info = described_class.new([])
      allow(info).to receive(:github_info).with(testball).and_return("https://example.com/testball.rb")

      expect { info.info_formula(testball) }
        .to output(a_string_including("==> Caveats\n#{shadowed_text}")).to_stdout
        .and not_to_output.to_stderr
    end

    it "moves them from the Caveats into the Binaries section with --verbose" do
      info = described_class.new(["--verbose"])
      allow(info).to receive(:github_info).with(testball).and_return("https://example.com/testball.rb")

      expect { info.info_formula(testball) }
        .to output(a_string_including("==> Binaries\nanother\n\n#{shadowed_text}")).to_stdout
        .and not_to_output(/==> Caveats/).to_stdout
        .and not_to_output.to_stderr
    end
  end

  it "prints a Binaries section from the bottle manifest when the formula is not installed with --verbose" do
    info = described_class.new(["--verbose"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    bottle = instance_double(
      Bottle,
      path_exec_files: ["bin/testball", "bin/another", "sbin/daemon"],
      bottle_size:     nil,
      installed_size:  nil,
    )
    allow(bottle).to receive(:fetch_tab)
    allow(formula).to receive_messages(bottle:, core_formula?: false)
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")

    expect { info.info_formula(formula) }
      .to output(a_string_including("==> Binaries\nanother\ndaemon\ntestball\n")).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits the Binaries section without --verbose" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    (keg_path/"bin").mkpath
    binary = keg_path/"bin/testball"
    binary.write("#!/bin/sh\n")
    binary.chmod(0755)
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to not_to_output(/==> Binaries/).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits the Binaries section when no executables are installed" do
    info = described_class.new(["--verbose"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"
    end

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    (keg_path/"lib").mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.info_formula(formula) }
      .to not_to_output(/==> Binaries/).to_stdout
      .and not_to_output.to_stderr
  end

  describe "::installation_status" do
    it "prints on-request installs explicitly" do
      expect(Utils::InfoDisplay.installation_status(instance_double(Tab, installed_on_request: true)))
        .to eq("Installed (on request)")
    end

    it "treats non-requested installs as dependency installs" do
      expect(Utils::InfoDisplay.installation_status(instance_double(Tab, installed_on_request: false)))
        .to eq("Installed (as dependency)")
    end
  end

  describe "::metadata_lines" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "returns summary lines for pinned formulae" do
      test_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0"
      end
      allow(test_formula).to receive_messages(any_version_installed?: true, pinned?: true, pinned_version: "1.0")

      mktmpdir do |dir|
        pin_path = Pathname(dir/"testball")
        pin_path.write("pin")
        pin_time = Time.at(1_720_189_900)
        File.utime(pin_time, pin_time, pin_path)
        allow(FormulaPin).to receive(:new).with(test_formula).and_return(instance_double(FormulaPin, path: pin_path))

        expect(Utils::InfoDisplay.metadata_lines(test_formula)).to eq([
          "Pinned: 1.0 on #{pin_time.strftime("%Y-%m-%d at %H:%M:%S")}",
        ])
      end
    end

    it "returns summary lines for pinned casks" do
      cask = Cask::Cask.new("test-cask") do
        version "1.0"
        url "https://brew.sh/test-cask.zip"
      end
      allow(cask).to receive_messages(pinned?: true, pinned_version: "1.0")

      mktmpdir do |dir|
        pin_path = Pathname(dir/"test-cask")
        pin_path.write("pin")
        pin_time = Time.at(1_720_189_900)
        File.utime(pin_time, pin_time, pin_path)
        allow(cask).to receive(:pin_path).and_return(pin_path)

        expect(Utils::InfoDisplay.metadata_lines(cask)).to eq([
          "Pinned: 1.0 on #{pin_time.strftime("%Y-%m-%d at %H:%M:%S")}",
        ])
      end
    end
  end

  describe "::github_remote_path" do
    let(:remote) { "https://github.com/Homebrew/homebrew-core" }

    specify "returns correct URLs" do
      expect(described_class.new([]).github_remote_path(remote, "Formula/git.rb"))
        .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/git.rb")

      expect(described_class.new([]).github_remote_path("#{remote}.git", "Formula/git.rb"))
        .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/git.rb")

      expect(described_class.new([]).github_remote_path("git@github.com:user/repo", "foo.rb"))
        .to eq("https://github.com/user/repo/blob/HEAD/foo.rb")

      expect(described_class.new([]).github_remote_path("https://mywebsite.com", "foo/bar.rb"))
        .to eq("https://mywebsite.com/foo/bar.rb")
    end
  end

  describe "Aliases and Old Names rows" do
    it "lists aliases on their own row when the formula has any" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end
      allow(main_formula).to receive_messages(aliases: ["testball@1.0", "tball", "googleball"], oldnames: [])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to output(/^Aliases: testball@1\.0, tball, googleball$/).to_stdout
        .and not_to_output(/^Old Names:/).to_stdout
        .and not_to_output.to_stderr
    end

    it "renders aliases and old names on separate rows when both exist" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end
      allow(main_formula).to receive_messages(aliases: ["testball@1.0", "tball"], oldnames: ["foo", "bar"])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to output(/^Aliases: testball@1\.0, tball\nOld Names: foo, bar$/).to_stdout
        .and not_to_output.to_stderr
    end

    it "renders only an Old Names row when there are no aliases" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end
      allow(main_formula).to receive_messages(aliases: [], oldnames: ["foo"])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to output(/^Old Names: foo$/).to_stdout
        .and not_to_output(/^Aliases:/).to_stdout
        .and not_to_output.to_stderr
    end

    it "omits both rows when there are none" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end
      allow(main_formula).to receive_messages(aliases: [], oldnames: [])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to not_to_output(/^Aliases:/).to_stdout
        .and not_to_output(/^Old Names:/).to_stdout
        .and not_to_output.to_stderr
    end
  end

  describe "Installed section" do
    it "lists this formula alongside installed sibling versioned formulae" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end
      versioned = formula("testball@0.9") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.9.tar.gz"
        keg_only :versioned_formula
      end

      main_keg = HOMEBREW_CELLAR/"testball/1.0"
      main_keg.mkpath
      main_tab = Tab.empty
      main_tab.tabfile = main_keg/AbstractTab::FILENAME
      main_tab.write
      (HOMEBREW_LINKED_KEGS/"testball").parent.mkpath
      FileUtils.ln_s(main_keg, HOMEBREW_LINKED_KEGS/"testball")

      sibling_keg = HOMEBREW_CELLAR/"testball@0.9/0.9"
      sibling_keg.mkpath
      sibling_tab = Tab.empty
      sibling_tab.tabfile = sibling_keg/AbstractTab::FILENAME
      sibling_tab.write

      allow(main_formula).to receive_messages(versioned_formulae: [versioned], outdated?: false)
      allow(versioned).to receive(:outdated?).and_return(false)
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")
      allow_any_instance_of(Keg).to receive(:abv).and_return("1 file, 1KB")

      expect { info.info_formula(main_formula) }
        .to output(<<~EOS).to_stdout
          ==> testball: stable 1.0
          Installed (as dependency)
          From: https://example.com/testball.rb
          ==> Installed Versions
          testball     1.0 (1 file, 1KB) [Linked]
          testball@0.9 0.9 (1 file, 1KB)
        EOS
                          .and not_to_output.to_stderr
    end

    it "shows installed → latest only on the newest installed keg of an outdated formula" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-2.0.tar.gz"
        version "2.0"
      end

      ["1.0", "0.9"].each do |version|
        keg_path = HOMEBREW_CELLAR/"testball/#{version}"
        keg_path.mkpath
        tab = Tab.empty
        tab.tabfile = keg_path/AbstractTab::FILENAME
        tab.write
      end

      allow(main_formula).to receive_messages(versioned_formulae: [], outdated?: true)
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")
      allow_any_instance_of(Keg).to receive(:abv).and_return("1 file, 1KB")

      expect { info.info_formula(main_formula) }
        .to output(<<~EOS).to_stdout
          ==> testball: 1.0 → stable 2.0
          Installed (as dependency)
          From: https://example.com/testball.rb
          ==> Installed Versions
          testball 1.0 → 2.0 (1 file, 1KB)
        EOS
                          .and not_to_output.to_stderr
    end

    it "hides older non-linked kegs by default" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end

      ["1.0", "0.9"].each do |version|
        keg_path = HOMEBREW_CELLAR/"testball/#{version}"
        keg_path.mkpath
        tab = Tab.empty
        tab.tabfile = keg_path/AbstractTab::FILENAME
        tab.write
      end

      allow(main_formula).to receive(:versioned_formulae).and_return([])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to output(/==> Installed Versions\n.*testball\b.*\s+1\.0\s+\(/).to_stdout
        .and not_to_output(/\s+0\.9\s+\(/).to_stdout
        .and not_to_output.to_stderr
    end

    it "includes the unversioned parent when run on a versioned formula" do
      info = described_class.new([])
      versioned = formula("testball@0.9") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.9.tar.gz"
        keg_only :versioned_formula
      end
      parent = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end

      versioned_keg = HOMEBREW_CELLAR/"testball@0.9/0.9"
      versioned_keg.mkpath
      versioned_tab = Tab.empty
      versioned_tab.tabfile = versioned_keg/AbstractTab::FILENAME
      versioned_tab.write

      parent_keg = HOMEBREW_CELLAR/"testball/1.0"
      (parent_keg/"bin").mkpath
      parent_tab = Tab.empty
      parent_tab.tabfile = parent_keg/AbstractTab::FILENAME
      parent_tab.write

      allow(versioned).to receive(:versioned_formulae).and_return([])
      allow(Formulary).to receive(:factory).with("testball").and_return(parent)
      allow(info).to receive(:github_info).with(versioned).and_return("https://example.com/testball.rb")

      expect { info.info_formula(versioned) }
        .to output(Regexp.new(
                     "==> Installed Versions\n" \
                     ".*testball\\b.*\\s+1\\.0\\s+\\(.*\\)\n" \
                     ".*testball@0\\.9\\b.*\\s+0\\.9\\s+\\(",
                   )).to_stdout
        .and not_to_output.to_stderr
    end

    it "renders the section even when only the current formula is installed" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end

      keg_path = HOMEBREW_CELLAR/"testball/1.0"
      keg_path.mkpath
      tab = Tab.empty
      tab.tabfile = keg_path/AbstractTab::FILENAME
      tab.write

      allow(main_formula).to receive(:versioned_formulae).and_return([])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to output(/==> Installed Versions\n.*testball\b.*\s+1\.0\s+\(/).to_stdout
        .and not_to_output.to_stderr
    end

    it "renders the section when the queried formula is uninstalled but a sibling is installed" do
      info = described_class.new([])
      versioned = formula("testball@0.9") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.9.tar.gz"
        keg_only :versioned_formula
      end
      parent = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end

      parent_keg = HOMEBREW_CELLAR/"testball/1.0"
      parent_keg.mkpath
      parent_tab = Tab.empty
      parent_tab.tabfile = parent_keg/AbstractTab::FILENAME
      parent_tab.write

      allow(versioned).to receive(:versioned_formulae).and_return([])
      allow(Formulary).to receive(:factory).with("testball").and_return(parent)
      allow(info).to receive(:github_info).with(versioned).and_return("https://example.com/testball.rb")

      expect { info.info_formula(versioned) }
        .to output(/==> Installed Versions\n.*testball\b.*\s+1\.0\s+\(/).to_stdout
        .and not_to_output(/testball@0\.9 \(0\.9\)/).to_stdout
        .and not_to_output.to_stderr
    end

    it "lists every installed keg of a formula, newest first, with --verbose" do
      info = described_class.new(["--verbose"])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end

      ["0.9", "1.0", "0.10"].each do |version|
        keg_path = HOMEBREW_CELLAR/"testball/#{version}"
        keg_path.mkpath
        tab = Tab.empty
        tab.tabfile = keg_path/AbstractTab::FILENAME
        tab.write
      end

      allow(main_formula).to receive_messages(versioned_formulae: [], outdated?: false)
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")
      allow_any_instance_of(Keg).to receive(:abv).and_return("1 file, 1KB")

      expect { info.info_formula(main_formula) }
        .to output(<<~EOS).to_stdout
          ==> testball: stable 1.0
          Installed (as dependency)
          From: https://example.com/testball.rb
          ==> Installed Kegs and Versions
          testball 1.0  (1 file, 1KB)
            Cellar: #{HOMEBREW_CELLAR}/testball/1.0
            Built from source
          testball 0.10 (1 file, 1KB)
            Cellar: #{HOMEBREW_CELLAR}/testball/0.10
            Built from source
          testball 0.9  (1 file, 1KB)
            Cellar: #{HOMEBREW_CELLAR}/testball/0.9
            Built from source
        EOS
                          .and not_to_output.to_stderr
    end

    it "omits the section when nothing in the family is installed" do
      info = described_class.new([])
      main_formula = formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-1.0.tar.gz"
      end
      allow(main_formula).to receive(:versioned_formulae).and_return([])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.info_formula(main_formula) }
        .to not_to_output(/==> Installed Versions\b/).to_stdout
        .and not_to_output.to_stderr
    end
  end

  describe "#github_info" do
    let(:tap) { CoreTap.instance }

    it "returns the local path for an installed cask whose file lives outside its tap" do
      cask_tap = CoreCaskTap.instance
      cask_path = Cask::Caskroom.path/"removed-cask/.metadata/1.0/20250101000000.000/Casks/removed-cask.rb"
      cask = Cask::Cask.new("removed-cask", tap: cask_tap, sourcefile_path: cask_path)
      allow(cask_tap).to receive(:remote).and_return(cask_tap.default_remote)

      expect(described_class.new([]).github_info(cask)).to eq(cask_path.to_s)
    end

    it "returns the local path for a formula whose file lives outside its tap" do
      # Simulates a formula that was removed from its tap but is still installed,
      # so it gets loaded from the keg's `.brew/` directory by `FromKegLoader`.
      keg_formula_path = HOMEBREW_CELLAR/"testball/0.1/.brew/testball.rb"
      formula_instance = formula("testball", path: keg_formula_path, tap:) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
      end

      expect(described_class.new([]).github_info(formula_instance))
        .to eq(keg_formula_path.to_s)
    end

    it "returns a GitHub URL for a formula whose file lives inside its tap" do
      formula_path = tap.new_formula_path("testball")
      formula_path.dirname.mkpath
      formula_path.write ""
      system "git", "-C", tap.path, "init", "--quiet"
      system "git", "-C", tap.path, "remote", "add", "origin", tap.default_remote
      system "git", "-C", tap.path, "add", formula_path
      formula_instance = formula("testball", path: formula_path, tap:) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
      end

      expect(described_class.new([]).github_info(formula_instance))
        .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/" \
               "#{formula_path.relative_path_from(tap.path)}")
    end

    it "returns a GitHub URL for an API formula without a local tap" do
      formula_instance = formula("testball", path: tap.new_formula_path("testball"), tap:) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
      end
      allow(formula_instance).to receive(:loaded_from_api?).and_return(true)
      allow(Utils).to receive(:popen_read).and_raise("Git should not be spawned for API formulae")
      allow(SystemCommand).to receive(:quiet_system).and_raise("Git should not be spawned for API formulae")

      expect(described_class.new([]).github_info(formula_instance))
        .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/" \
               "#{formula_instance.path.relative_path_from(tap.path)}")
    end

    context "when a local formula is untracked" do
      let(:formula_path) { tap.formula_dir/"t/testball.rb" }

      before do
        formula_path.dirname.mkpath
        formula_path.write <<~RUBY
          class Testball < Formula
            url "https://brew.sh/testball-0.1.tar.gz"
          end
        RUBY
        system "git", "-C", tap.path, "init", "--quiet"
        system "git", "-C", tap.path, "remote", "add", "origin", tap.default_remote
      end

      it "returns the local path when the formula is not installed" do
        expect(described_class.new([]).github_info(Formulary.from_path(formula_path)))
          .to eq(formula_path.to_s)
      end

      it "identifies the same installed file with and without the API" do
        keg_path = HOMEBREW_CELLAR/"testball/0.1"
        (keg_path/".brew").mkpath
        (keg_path/".brew/testball.rb").write(formula_path.read)
        (keg_path/AbstractTab::FILENAME).write({ source: { tap: tap.name } }.to_json)
        (HOMEBREW_PREFIX/"opt/testball").make_relative_symlink(keg_path)
        allow(Homebrew::API).to receive_messages(formula_names: [], formula_aliases: {}, formula_renames: {},
                                                 formula_tap_migrations: {}, formula_name?: false)

        expect([nil, "1"].map do |no_api|
          ENV["HOMEBREW_NO_INSTALL_FROM_API"] = no_api
          tap.clear_cache
          formula = Formulary.from_keg(Keg.new(keg_path))
          Pathname(described_class.new([]).github_info(formula)).realpath
        end).to eq([keg_path/".brew/testball.rb"] * 2)
      end

      it "queries the index once for multiple formulae in a tap" do
        (formula_path.dirname/"testball2.rb").write(formula_path.read.sub("Testball", "Testball2"))
        info = described_class.new([])
        allow(Utils).to receive(:popen_read).and_call_original

        expect(Utils).to receive(:popen_read).with(Utils::Git.git, "-C", tap.path, "ls-files", "-z")
                                             .once.and_call_original

        %w[testball testball2].each do |name|
          info.github_info(Formulary.from_path(formula_path.dirname/"#{name}.rb"))
        end
      end

      test_each(["homebrew/foo", nil]) do |installed_tap|
        it "returns the selected formula's path when the installed tap is #{installed_tap.inspect}" do
          ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
          keg_path = HOMEBREW_CELLAR/"testball/0.1"
          (keg_path/".brew").mkpath
          (keg_path/".brew/testball.rb").write(formula_path.read)
          (keg_path/AbstractTab::FILENAME).write({ source: { tap: installed_tap } }.to_json)
          (HOMEBREW_PREFIX/"opt/testball").make_relative_symlink(keg_path)

          expect(described_class.new(["homebrew/core/testball"])
                                .github_info(Formulary.factory("homebrew/core/testball")))
            .to eq(formula_path.to_s)
        end
      end
    end
  end
end
