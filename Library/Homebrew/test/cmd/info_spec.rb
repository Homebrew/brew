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

    expect { info.send(:info_formula, formula) }
      .to output(
        /==> Dependencies\nRequired \(1\): .*bar.*\nRecursive Runtime \(2\): 1 .*✔, 1 .*✘\nDependents: 1/,
      ).to_stdout
      .and not_to_output(/^Dependencies: /).to_stdout
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
end
