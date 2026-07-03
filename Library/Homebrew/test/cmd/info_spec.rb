# typed: false
# frozen_string_literal: true

require "cmd/info"
require "cmd/shared_examples/args_parse"

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

  it "prints as json with the --json=v2 flag", :integration_test do
    setup_test_formula "testball"

    expect { brew "info", "testball", "--json=v2" }
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

  it "does not include eval-all casks in formula JSON" do
    formula = installed_info_formula

    allow(Formula).to receive(:all).and_return([formula])
    allow(Homebrew::EnvConfig).to receive(:tap_trust_configured?).and_return(true)
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
    expect { info.send(:info_formula_summary, formula) }
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

    expect { info.send(:info_formula, formula) }
      .to output(/Installs from source: yes/).to_stdout
      .and not_to_output(/Metadata/).to_stdout
      .and not_to_output(/supports macOS and Linux/).to_stdout
      .and not_to_output.to_stderr
  end

  it "shows a conflict by its resolved full name" do
    info = described_class.new([])
    formula = formula("testball") do
      url "https://brew.sh/testball-0.1.tar.gz"
      conflicts_with "other"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    other = formula("other") { url "https://brew.sh/other-0.1.tar.gz" }
    allow(other).to receive(:full_name).and_return("someuser/tap/other")
    allow(Formulary).to receive(:factory).with("other").and_return(other)

    expect { info.send(:info_formula, formula) }
      .to output(%r{Conflicts with:\n  someuser/tap/other}).to_stdout
  end

  it "omits a stale conflict that resolves to the formula itself" do
    info = described_class.new([])
    formula = formula("testball") do
      url "https://brew.sh/testball-0.1.tar.gz"
      conflicts_with "testball"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(Formulary).to receive(:factory).with("testball").and_return(formula)

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
      .to output(/==> .*testball.*\(disabled\):/).to_stdout
      .and not_to_output.to_stderr
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
    installed = formula("testball") { url "https://brew.sh/testball-0.1.tar.gz" }
    allow(installed).to receive_messages(tap: Tap.fetch("ataraxy-labs/tap"), full_name: "ataraxy-labs/tap/testball")
    allow(Formulary).to receive(:factory).with("ataraxy-labs/tap/testball").and_return(installed)
    allow(info).to receive(:github_info).and_return("https://example.com/testball.rb")
    allow(info.args.named).to receive_messages(
      downcased_unique_named:                ["testball", "homebrew/core/testball"],
      to_formulae_and_casks_and_unavailable: [core, core],
    )

    expect { info.send(:print_info) }
      .to output(%r{ataraxy-labs/tap/testball.*homebrew/core/testball.*Not installed}m).to_stdout
  end

  it "reports an unavailable name without raising" do
    info = described_class.new([])
    error = FormulaOrCaskUnavailableError.new("nonexistent-formula")
    allow(info.args.named).to receive_messages(
      downcased_unique_named:                ["nonexistent-formula"],
      to_formulae_and_casks_and_unavailable: [error],
    )

    expect { info.send(:print_info) }
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
    shadowing = formula("testball") { url "https://brew.sh/testball-0.1.tar.gz" }
    allow(shadowing).to receive_messages(tap: Tap.fetch("ataraxy-labs/tap"), full_name: "ataraxy-labs/tap/testball")
    allow(Formulary).to receive(:factory).with("ataraxy-labs/tap/testball").and_return(shadowing)

    expect { info.send(:info_formula, formula) }
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

    expect(info.send(:installed_resolution, formula)).to eq([keg_formula, shadowing_tap])
  end

  it "resolves the keg's own name when it differs from the formula (installed via alias)" do
    info = described_class.new([])
    formula = installed_info_formula
    tab = instance_double(Tab, tap: Tap.fetch("stripe/stripe-cli"))
    keg = instance_double(Keg, name: "stripe", tab:)
    allow(formula).to receive_messages(tap: Tap.fetch("homebrew/core"), installed_kegs: [keg])
    keg_formula = formula("stripe") { url "https://brew.sh/stripe-1.0.tar.gz" }
    allow(Formulary).to receive(:factory).with("stripe/stripe-cli/stripe").and_return(keg_formula)

    expect(info.send(:installed_resolution, formula)).to eq([keg_formula, Tap.fetch("homebrew/core")])
  end

  it "returns the original formula and no shadowing tap when the install receipt has no tap" do
    info = described_class.new([])
    formula = installed_info_formula

    keg_path = HOMEBREW_CELLAR/"testball/0.1"
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    expect(info.send(:installed_resolution, formula)).to eq([formula, nil])
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
    expect(info.send(:installed_resolution, formula)).to eq([formula, nil])
  end

  it "warns about a shadowing tap when info_formula is given one" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.send(:info_formula, formula, shadowed_by: Tap.fetch("homebrew/core")) }
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
    expect(info.send(:formula_qualified_by_user?, formula, qualified)).to be(true)
  end

  it "treats a bare unqualified input as not user-qualified" do
    info = described_class.new([])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end

    expect(info.send(:formula_qualified_by_user?, formula, Set.new)).to be(false)
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
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])
    allow(direct_dependency).to receive(:satisfied?).and_return(true)

    expected_output = Regexp.new(
      "==> Dependencies\nRequired \\(1\\): .*bar.*\n" \
      "Recursive Runtime \\(2\\): 1 installed .*✔, 1 missing .*✘\nDependents: 1",
    )
    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
      .to output(/^Dependents \(2\): another-dependent, some-dependent$/).to_stdout
      .and not_to_output(/^Dependents: /).to_stdout
      .and not_to_output.to_stderr
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
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])
    allow(direct_dependency).to receive(:satisfied?).and_return(true)

    expect { info.send(:info_formula, formula) }
      .to output(/Recursive Runtime \(1\): all installed .*✔/).to_stdout
      .and not_to_output(/missing/).to_stdout
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

    expect { info.send(:info_formula, formula) }
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
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.send(:info_formula, formula) }
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
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): bar\n/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a dep absent from the installed keg's tab as unsatisfied when its rack is also missing" do
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
    allow(formula).to receive_messages(core_formula?: false, missing_library_linkage: [[], Set.new])

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*✘/).to_stdout
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
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
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive_messages(core_formula?: false, outdated?: true)

    keg_path = HOMEBREW_CELLAR/"testball/0.0.1"
    keg_path.mkpath
    tab = Tab.empty
    tab.tabfile = keg_path/AbstractTab::FILENAME
    tab.write

    expect { info.send(:info_formula, formula) }
      .to output(/\A==> testball: 0\.0\.1 → stable 0\.1\n/).to_stdout
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

    expect { info.send(:info_formula, formula) }
      .to output(/Requirements\nRequired: .*Linux/).to_stdout
      .and not_to_output(/supports Linux/).to_stdout
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
      .to output(a_string_including("==> Binaries\nanother\ndaemon\ntestball\n")).to_stdout
      .and not_to_output.to_stderr
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
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

    expect { info.send(:info_formula, formula) }
      .to not_to_output(/==> Binaries/).to_stdout
      .and not_to_output.to_stderr
  end

  describe "::installation_status" do
    it "prints on-request installs explicitly" do
      expect(described_class.installation_status(instance_double(Tab, installed_on_request: true)))
        .to eq("Installed (on request)")
    end

    it "treats non-requested installs as dependency installs" do
      expect(described_class.installation_status(instance_double(Tab, installed_on_request: false)))
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

        expect(described_class.metadata_lines(test_formula)).to eq([
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

        expect(described_class.metadata_lines(cask)).to eq([
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

      expect { info.send(:info_formula, main_formula) }
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

      expect { info.send(:info_formula, main_formula) }
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

      expect { info.send(:info_formula, main_formula) }
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

      expect { info.send(:info_formula, main_formula) }
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

      sibling_keg = HOMEBREW_CELLAR/"testball@0.9/0.9"
      sibling_keg.mkpath
      sibling_tab = Tab.empty
      sibling_tab.tabfile = sibling_keg/AbstractTab::FILENAME
      sibling_tab.write

      allow(main_formula).to receive(:versioned_formulae).and_return([versioned])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.send(:info_formula, main_formula) }
        .to output(Regexp.new(
                     "==> Installed Kegs and Versions\n" \
                     ".*testball\\b.*\\s+1\\.0\\s+\\(.*\\)\n" \
                     ".*testball@0\\.9\\b.*\\s+0\\.9\\s+\\(",
                   )).to_stdout
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

      expect { info.send(:info_formula, main_formula) }
        .to output(Regexp.new(
                     "==> Installed Kegs and Versions\n" \
                     ".*testball\\b.*\\s+1\\.0 → 2\\.0\\s+\\(.*\\)\n" \
                     ".*testball\\b.*\\s+0\\.9\\s+\\(",
                   )).to_stdout
        .and not_to_output(/0\.9 →/).to_stdout
        .and not_to_output.to_stderr
    end

    it "marks the currently linked version with `*`" do
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

      allow(main_formula).to receive_messages(versioned_formulae: [versioned], linked?: true,
                                              linked_version: PkgVersion.parse("1.0"))
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.send(:info_formula, main_formula) }
        .to output(/.*testball\b.*\s+1\.0\s+\(.*\)\s+\[Linked\]/).to_stdout
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

      expect { info.send(:info_formula, versioned) }
        .to output(Regexp.new(
                     "==> Installed Kegs and Versions\n" \
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

      expect { info.send(:info_formula, main_formula) }
        .to output(/==> Installed Kegs and Versions\n.*testball\b.*\s+1\.0\s+\(/).to_stdout
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

      expect { info.send(:info_formula, versioned) }
        .to output(/==> Installed Kegs and Versions\n.*testball\b.*\s+1\.0\s+\(/).to_stdout
        .and not_to_output(/testball@0\.9 \(0\.9\)/).to_stdout
        .and not_to_output.to_stderr
    end

    it "lists every installed keg of a formula, newest first" do
      info = described_class.new([])
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

      allow(main_formula).to receive(:versioned_formulae).and_return([])
      allow(info).to receive(:github_info).with(main_formula).and_return("https://example.com/testball.rb")

      expect { info.send(:info_formula, main_formula) }
        .to output(Regexp.new(
                     "==> Installed Kegs and Versions\n" \
                     ".*testball\\b.*\\s+1\\.0\\b.*\\(.*\\)\n" \
                     ".*testball\\b.*\\s+0\\.10\\s+\\(.*\\)\n" \
                     ".*testball\\b.*\\s+0\\.9\\s+\\(",
                   )).to_stdout
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

      expect { info.send(:info_formula, main_formula) }
        .to not_to_output(/==> Installed Kegs and Versions\b/).to_stdout
        .and not_to_output.to_stderr
    end
  end

  describe "#github_info" do
    let(:tap) { CoreTap.instance }

    it "returns the local path for a formula whose file lives outside its tap" do
      # Simulates a formula that was removed from its tap but is still installed,
      # so it gets loaded from the keg's `.brew/` directory by `FromKegLoader`.
      keg_formula_path = HOMEBREW_CELLAR/"testball/0.1/.brew/testball.rb"
      formula_instance = formula("testball", path: keg_formula_path, tap:) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
      end

      expect(described_class.new([]).send(:github_info, formula_instance))
        .to eq(keg_formula_path.to_s)
    end

    it "returns a GitHub URL for a formula whose file lives inside its tap" do
      formula_path = tap.new_formula_path("testball")
      formula_instance = formula("testball", path: formula_path, tap:) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/testball-0.1.tar.gz"
      end

      expect(described_class.new([]).send(:github_info, formula_instance))
        .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/" \
               "#{formula_path.relative_path_from(tap.path)}")
    end
  end
end
