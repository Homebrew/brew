# frozen_string_literal: true

require "cask"

RSpec.describe Cask::Tab, :cask do
  matcher :be_installed_as_dependency do
    match do |actual|
      actual.installed_as_dependency == true
    end
  end

  matcher :be_installed_on_request do
    match do |actual|
      actual.installed_on_request == true
    end
  end

  matcher :be_loaded_from_api do
    match do |actual|
      actual.loaded_from_api == true
    end
  end

  matcher :have_uninstall_flight_blocks do
    match do |actual|
      actual.uninstall_flight_blocks == true
    end
  end

  subject(:tab) do
    described_class.new(
      "homebrew_version"        => HOMEBREW_VERSION,
      "loaded_from_api"         => false,
      "uninstall_flight_blocks" => true,
      "installed_as_dependency" => false,
      "installed_on_request"    => true,
      "time"                    => time,
      "runtime_dependencies"    => {
        "cask" => [{ "full_name" => "bar", "version" => "2.0", "declared_directly" => false }],
      },
      "source"                  => {
        "path"         => CoreCaskTap.instance.path.to_s,
        "tap"          => CoreCaskTap.instance.to_s,
        "tap_git_head" => "8b79aa759500f0ffdf65a23e12950cbe3bf8fe17",
        "version"      => "1.2.3",
      },
      "arch"                    => Hardware::CPU.arch,
      "uninstall_artifacts"     => [{ "app" => ["Foo.app"] }],
      "built_on"                => DevelopmentTools.build_system_info,
    )
  end

  let(:time) { Time.now.to_i }

  let(:f) { formula { url "foo-1.0" } }
  let(:f_tab_path) { f.prefix/"INSTALL_RECEIPT.json" }
  let(:f_tab_content) { (TEST_FIXTURE_DIR/"receipt.json").read }

  specify "defaults" do
    stub_const("HOMEBREW_VERSION", "4.3.7")

    tab = described_class.empty

    expect(tab.homebrew_version).to eq(HOMEBREW_VERSION)
    expect(tab).not_to be_installed_as_dependency
    expect(tab).not_to be_installed_on_request
    expect(tab).not_to be_loaded_from_api
    expect(tab).not_to have_uninstall_flight_blocks
    expect(tab.tap).to be_nil
    expect(tab.time).to be_nil
    expect(tab.runtime_dependencies).to be_nil
    expect(tab.source["path"]).to be_nil
  end

  specify "#runtime_dependencies" do
    tab = described_class.new
    expect(tab.runtime_dependencies).to be_nil

    tab.runtime_dependencies = {}
    expect(tab.runtime_dependencies).not_to be_nil

    tab.runtime_dependencies = {
      "cask" => [{ "full_name" => "bar", "version" => "2.0", "declared_directly" => false }],
    }
    expect(tab.runtime_dependencies).not_to be_nil
  end

  describe "::runtime_deps_hash" do
    specify "with no dependencies" do
      cask = Cask::CaskLoader.load("local-transmission")

      expect(described_class.runtime_deps_hash(cask)).to eq({})
    end

    specify "with cask dependencies" do
      cask = Cask::CaskLoader.load("with-depends-on-cask")

      expected_hash = {
        cask: [
          { "full_name"=>"local-transmission-zip", "version"=>"2.61", "declared_directly"=>true },
        ],
      }
      expect(described_class.runtime_deps_hash(cask)).to eq(expected_hash)
    end

    it "ignores macos symbol dependencies" do
      cask = Cask::CaskLoader.load("with-depends-on-macos-symbol")

      expect(described_class.runtime_deps_hash(cask)).to eq({})
    end

    it "ignores macos array dependencies" do
      cask = Cask::CaskLoader.load("with-depends-on-macos-array")

      expect(described_class.runtime_deps_hash(cask)).to eq({})
    end

    it "ignores arch dependencies" do
      cask = Cask::CaskLoader.load("with-depends-on-arch")

      expect(described_class.runtime_deps_hash(cask)).to eq({})
    end

    specify "with all types of dependencies" do
      cask = Cask::CaskLoader.load("with-depends-on-everything")

      unar = Class.new(Formula) do
        url "my_url"
        version "1.2"
      end.new("unar", Pathname.new(__FILE__).expand_path, :stable)
      expect(Formulary).to receive(:factory).with("unar").and_return(unar)

      expected_hash = {
        cask:    [
          { "full_name"=>"local-caffeine", "version"=>"1.2.3", "declared_directly"=>true },
          { "full_name"=>"with-depends-on-cask", "version"=>"1.2.3", "declared_directly"=>true },
          { "full_name"=>"local-transmission-zip", "version"=>"2.61", "declared_directly"=>false },
        ],
        formula: [
          { "full_name"=>"unar", "version"=>"1.2", "revision"=>0, "pkg_version"=>"1.2", "declared_directly"=>true },
        ],
      }

      runtime_deps_hash = described_class.runtime_deps_hash(cask)
      tab = described_class.new
      tab.runtime_dependencies = runtime_deps_hash
      expect(tab.runtime_dependencies).to eql(expected_hash)
    end
  end

  specify "other attributes" do
    expect(tab.tap.name).to eq("homebrew/cask")
    expect(tab.time).to eq(time)
    expect(tab).not_to be_loaded_from_api
    expect(tab).to have_uninstall_flight_blocks
    expect(tab).not_to be_installed_as_dependency
    expect(tab).to be_installed_on_request
    expect(tab).not_to be_loaded_from_api
  end

  describe "::from_file" do
    it "parses a cask Tab from a file" do
      path = Pathname.new("#{TEST_FIXTURE_DIR}/cask_receipt.json")
      tab = described_class.from_file(path)
      source_path = "/opt/homebrew/Library/Taps/homebrew/homebrew-cask/Casks/f/foo.rb"
      runtime_dependencies = {
        "cask"    => [
          {
            "full_name"         => "bar",
            "version"           => "2.0",
            "declared_directly" => true,
          },
        ],
        "formula" => [
          {
            "full_name"         => "baz",
            "version"           => "3.0",
            "revision"          => 0,
            "pkg_version"       => "3.0",
            "declared_directly" => true,
          },
        ],
        "macos"   => {
          ">=" => [
            "12",
          ],
        },
      }

      expect(tab).not_to be_loaded_from_api
      expect(tab).to have_uninstall_flight_blocks
      expect(tab).not_to be_installed_as_dependency
      expect(tab).to be_installed_on_request
      expect(tab.time).to eq(Time.at(1_719_289_256).to_i)
      expect(tab.runtime_dependencies).to eq(runtime_dependencies)
      expect(tab.source["path"]).to eq(source_path)
      expect(tab.version).to eq("1.2.3")
      expect(tab.tap.name).to eq("homebrew/cask")
    end
  end

  describe "::from_file_content" do
    it "parses a cask Tab from a file" do
      path = Pathname.new("#{TEST_FIXTURE_DIR}/cask_receipt.json")
      tab = described_class.from_file_content(path.read, path)
      source_path = "/opt/homebrew/Library/Taps/homebrew/homebrew-cask/Casks/f/foo.rb"
      runtime_dependencies = {
        "cask"    => [
          {
            "full_name"         => "bar",
            "version"           => "2.0",
            "declared_directly" => true,
          },
        ],
        "formula" => [
          {
            "full_name"         => "baz",
            "version"           => "3.0",
            "revision"          => 0,
            "pkg_version"       => "3.0",
            "declared_directly" => true,
          },
        ],
        "macos"   => {
          ">=" => [
            "12",
          ],
        },
      }

      expect(tab).not_to be_loaded_from_api
      expect(tab).to have_uninstall_flight_blocks
      expect(tab).not_to be_installed_as_dependency
      expect(tab).to be_installed_on_request
      expect(tab.tabfile).to eq(path)
      expect(tab.time).to eq(Time.at(1_719_289_256).to_i)
      expect(tab.runtime_dependencies).to eq(runtime_dependencies)
      expect(tab.source["path"]).to eq(source_path)
      expect(tab.version).to eq("1.2.3")
      expect(tab.tap.name).to eq("homebrew/cask")
    end

    it "raises a parse exception message including the Tab filename" do
      expect { described_class.from_file_content("''", "cask_receipt.json") }.to raise_error(
        JSON::ParserError,
        /receipt.json:/,
      )
    end
  end

  describe "::create" do
    it "creates a cask Tab" do
      cask = Cask::CaskLoader.load("local-caffeine")
      expected_artifacts = [
        { app: ["Caffeine.app"] },
        { zap: [{ trash: "#{TEST_FIXTURE_DIR}/cask/caffeine/org.example.caffeine.plist" }] },
      ]

      tab = described_class.create(cask)
      expect(tab).not_to be_loaded_from_api
      expect(tab).not_to have_uninstall_flight_blocks
      expect(tab).not_to be_installed_as_dependency
      expect(tab).not_to be_installed_on_request
      expect(tab.source).to eq({
        "path"         => "#{CoreCaskTap.instance.path}/Casks/local-caffeine.rb",
        "tap"          => CoreCaskTap.instance.name,
        "tap_git_head" => nil,
        "version"      => "1.2.3",
      })
      expect(tab.runtime_dependencies).to eq({})
      expect(tab.uninstall_artifacts).to eq(expected_artifacts)
    end
  end

  describe "::for_cask" do
    let(:cask) { Cask::CaskLoader.load("local-transmission") }
    let(:cask_tab_path) { cask.metadata_main_container_path/AbstractTab::FILENAME }
    let(:cask_tab_content) { (TEST_FIXTURE_DIR/"cask_receipt.json").read }

    it "creates a Tab for a given cask" do
      tab = described_class.for_cask(cask)
      expect(tab.source["path"]).to eq(cask.sourcefile_path.to_s)
    end

    it "creates a Tab for a given cask with existing Tab" do
      cask_tab_path.dirname.mkpath
      cask_tab_path.write cask_tab_content

      tab = described_class.for_cask(cask)
      expect(tab.tabfile).to eq(cask_tab_path)
    end

    it "can create a Tab for a non-existent cask" do
      cask_tab_path.dirname.mkpath

      tab = described_class.for_cask(cask)
      expect(tab.tabfile).to be_nil
    end
  end

  specify "#to_json" do
    json_tab = described_class.new(JSON.parse(tab.to_json))
    expect(json_tab.homebrew_version).to eq(tab.homebrew_version)
    expect(json_tab.loaded_from_api).to eq(tab.loaded_from_api)
    expect(json_tab.uninstall_flight_blocks).to eq(tab.uninstall_flight_blocks)
    expect(json_tab.installed_as_dependency).to eq(tab.installed_as_dependency)
    expect(json_tab.installed_on_request).to eq(tab.installed_on_request)
    expect(json_tab.time).to eq(tab.time)
    expect(json_tab.runtime_dependencies).to eq(tab.runtime_dependencies)
    expect(json_tab.source["path"]).to eq(tab.source["path"])
    expect(json_tab.tap).to eq(tab.tap)
    expect(json_tab.source["tap_git_head"]).to eq(tab.source["tap_git_head"])
    expect(json_tab.version).to eq(tab.version)
    expect(json_tab.arch).to eq(tab.arch.to_s)
    expect(json_tab.uninstall_artifacts).to eq(tab.uninstall_artifacts)
    expect(json_tab.built_on["os"]).to eq(tab.built_on["os"])
  end

  describe "#to_s" do
    let(:time_string) { Time.at(1_720_189_863).strftime("%Y-%m-%d at %H:%M:%S") }

    it "returns install information for a Tab with a time that was loaded from the API" do
      tab = described_class.new(
        loaded_from_api: true,
        time:            1_720_189_863,
      )
      output = "Installed using the formulae.brew.sh API on #{time_string}"
      expect(tab.to_s).to eq(output)
    end

    it "returns install information for a Tab with a time that was not loaded from the API" do
      tab = described_class.new(
        loaded_from_api: false,
        time:            1_720_189_863,
      )
      output = "Installed on #{time_string}"
      expect(tab.to_s).to eq(output)
    end

    it "returns install information for a Tab without a time that was loaded from the API" do
      tab = described_class.new(
        loaded_from_api: true,
        time:            nil,
      )
      output = "Installed using the formulae.brew.sh API"
      expect(tab.to_s).to eq(output)
    end

    it "returns install information for a Tab without a time that was not loaded from the API" do
      tab = described_class.new(
        loaded_from_api: false,
        time:            nil,
      )
      output = "Installed"
      expect(tab.to_s).to eq(output)
    end
  end
end
