# typed: false
# frozen_string_literal: true

require "cmd/info"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Info do
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

  it "prints as json with the --json=v1 flag", :integration_test do
    setup_test_formula "testball"

    expect { brew "info", "testball", "--json=v1" }
      .to output(a_json_string).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints as json with the --json=v2 flag", :integration_test do
    setup_test_formula "testball"

    expect { brew "info", "testball", "--json=v2" }
      .to output(a_json_string).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
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
    expect(info).to receive(:info_formula).with(formula)
    expect(info).to receive(:info_cask).with(cask)

    expect { info.run }
      .to output("\n").to_stdout
      .and not_to_output.to_stderr
  end

  it "prints quiet formula information in the slim inventory format" do
    info = described_class.new([])
    formula = formula("testball") do
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

  it "uses slim formula information when quiet is passed", :integration_test do
    setup_test_formula "testball"
    info = described_class.new(["--quiet", "testball"])

    expect(info).to receive(:info_formula_summary).with(kind_of(Formula))
    expect { info.run }
      .to not_to_output.to_stderr
  end

  it "prints inline summary information for formulae" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      option "with-foo", "Build with foo"
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Installs from source: yes/).to_stdout
      .and not_to_output(/Metadata/).to_stdout
      .and not_to_output(/supports macOS and Linux/).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints required, recursive runtime, and dependent counts in the dependencies section" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/^Dependents \(2\): another-dependent, some-dependent$/).to_stdout
      .and not_to_output(/^Dependents: /).to_stdout
      .and not_to_output.to_stderr
  end

  it "summarises recursive runtime dependencies as all installed when none are missing" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a tab-listed dep with an installed rack as satisfied when the dep formula is not outdated" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*✔/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a tab-listed dep with an installed rack as outdated when the dep formula is outdated" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*↑/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an installed dep on an uninstalled formula as satisfied" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*✔/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks an outdated installed dep on an uninstalled formula as upgradable" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*↑/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a missing dep on an uninstalled formula as unsatisfied" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      url "https://brew.sh/testball-0.1.tar.gz"
      desc "Some test"

      depends_on "bar"
    end

    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "marks a dep absent from the installed keg's tab as unsatisfied" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Required \(1\): .*bar.*✘/).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits build dependencies when a formula would pour from a bottle" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
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
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      depends_on :linux
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(/Requirements\nRequired: .*Linux/).to_stdout
      .and not_to_output(/supports Linux/).to_stdout
      .and not_to_output.to_stderr
  end

  it "hides source install metadata for formulae that only run on another OS" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    info = described_class.new([])
    formula = formula("testball") do
      url "https://brew.sh/testball-0.1.tar.gz"
      homepage "https://brew.sh/testball"
      desc "Some test"

      if OS.mac?
        depends_on :linux
      else
        depends_on macos: :sonoma
      end
    end
    allow(info).to receive(:github_info).with(formula).and_return("https://example.com/testball.rb")
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to not_to_output(/Installs from source: yes/).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints a Binaries section listing executables in bin and sbin with --verbose" do
    info = described_class.new(["--verbose"])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to output(a_string_including("==> Binaries\nanother\ndaemon\ntestball\n")).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints a Binaries section from the bottle manifest when the formula is not installed with --verbose" do
    info = described_class.new(["--verbose"])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

    expect { info.send(:info_formula, formula) }
      .to not_to_output(/==> Binaries/).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits the Binaries section when no executables are installed" do
    info = described_class.new(["--verbose"])
    formula = formula("testball") do
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
    allow(formula).to receive(:core_formula?).and_return(false)

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
      formula = instance_double(
        Formula,
        any_version_installed?: true,
        pinned?:                true,
        pinned_version:         "1.0",
      )

      mktmpdir do |dir|
        pin_path = Pathname(dir/"testball")
        pin_path.write("pin")
        pin_time = Time.at(1_720_189_900)
        File.utime(pin_time, pin_time, pin_path)
        allow(FormulaPin).to receive(:new).with(formula).and_return(instance_double(FormulaPin, path: pin_path))

        expect(described_class.metadata_lines(formula)).to eq([
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

  describe "#github_info" do
    let(:tap) { CoreTap.instance }

    it "returns the local path for a formula whose file lives outside its tap" do
      # Simulates a formula that was removed from its tap but is still installed,
      # so it gets loaded from the keg's `.brew/` directory by `FromKegLoader`.
      keg_formula_path = HOMEBREW_CELLAR/"testball/0.1/.brew/testball.rb"
      formula_instance = formula("testball", path: keg_formula_path, tap:) do
        url "https://brew.sh/testball-0.1.tar.gz"
      end

      expect(described_class.new([]).send(:github_info, formula_instance))
        .to eq(keg_formula_path.to_s)
    end

    it "returns a GitHub URL for a formula whose file lives inside its tap" do
      formula_path = tap.new_formula_path("testball")
      formula_instance = formula("testball", path: formula_path, tap:) do
        url "https://brew.sh/testball-0.1.tar.gz"
      end

      expect(described_class.new([]).send(:github_info, formula_instance))
        .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/" \
               "#{formula_path.relative_path_from(tap.path)}")
    end
  end
end
