# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/install-bundler-gems"
require "bundler"
require "rubygems/package"

RSpec.describe Homebrew::DevCmd::InstallBundlerGems do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "install-bundler-gems"

  it "resets Bootsnap after cleaning gems" do
    bundle = "/tmp/bundle"
    allow(Utils::GemSetup).to receive(:setup_gem_environment!)
    allow(Utils::GemSetup).to receive_messages(valid_gem_groups: [], user_gem_groups: [], user_vendor_version: 10)
    allow(Utils::GemSetup).to receive(:find_in_path).with("bundle").and_return("/tmp")
    allow(IO).to receive(:popen).with([bundle, "check"], err: [:child, :out]).and_return("")
    allow(Utils::GemSetup).to receive(:system).with(bundle, "clean", out: :err).and_return(true)
    allow(Utils::GemSetup).to receive(:write_user_gem_groups)
    expect(Homebrew::Bootsnap).to receive(:reset!)

    Kernel.system("true")
    with_env(HOMEBREW_TESTS: nil) { Utils::GemSetup.install_bundler_gems! }
  end

  it "detects an outdated vendor version" do
    allow(Utils::GemSetup).to receive(:user_vendor_version).and_return(9)

    expect(Utils::GemSetup.vendor_version_current?).to be(false)
  end

  it "recognises the current vendor version" do
    allow(Utils::GemSetup).to receive(:user_vendor_version).and_return(10)

    expect(Utils::GemSetup.vendor_version_current?).to be(true)
  end

  describe "vendor version marker" do
    # Keep each Sorbet signature with its let declaration.
    # rubocop:disable RSpec/ScatteredLet
    sig { returns(Pathname) }
    let(:gem_dir) { mktmpdir }
    sig { returns(Pathname) }
    let(:version_file) { Pathname(gem_dir)/".homebrew_vendor_version" }
    sig { returns(Bundler::Definition) }
    let(:definition) do
      instance_double(
        Bundler::Definition,
        resolve:             instance_double(Bundler::SpecSet, materialize: []),
        locked_dependencies: [],
      )
    end
    # rubocop:enable RSpec/ScatteredLet

    before do
      stub_const("Utils::GemSetup::VENDOR_VERSION_FILE", version_file)
      allow(Gem).to receive(:dir).and_return(gem_dir)
      allow(Utils::GemSetup).to receive_messages(
        setup_gem_environment!: nil,
        valid_gem_groups:       %w[marker_failure marker_success],
        user_gem_groups:        [],
        user_vendor_version:    9,
        bundler_definition:     definition,
        find_in_path:           "/tmp",
        write_user_gem_groups:  nil,
      )
      allow(IO).to receive(:popen).with(["/tmp/bundle", "check"], err: [:child, :out])
                                  .and_return("Install missing gems")
      allow(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)
      allow(Homebrew::Bootsnap).to receive(:reset!)
      Kernel.system("true")
    end

    it "writes the vendor version after a successful install" do
      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["marker_success"])
      end

      expect(version_file.read).to eq("10")
    end

    it "does not write the vendor version after a failed install" do
      allow(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(false)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["marker_failure"], only_warn_on_failure: true)
      end

      expect(version_file.exist?).to be(false)
    end
  end

  describe "native extension integrity" do
    # Keep each Sorbet signature with its let declaration.
    # rubocop:disable RSpec/ScatteredLet
    sig { returns(Pathname) }
    let(:gem_dir) { mktmpdir }
    sig { returns(String) }
    let(:full_name) { "json-3.1.0" }
    sig { returns(Pathname) }
    let(:extension_dir) { Pathname(gem_dir)/"extensions"/full_name }
    sig { returns(Pathname) }
    let(:gem_lib_dir) { Pathname(gem_dir)/"gems"/full_name/"lib" }
    sig { returns(Pathname) }
    let(:version_file) { Pathname(gem_dir)/".homebrew_vendor_version" }
    sig { returns(Gem::Specification) }
    let(:spec) do
      instance_double(
        Gem::Specification,
        name:               "json",
        full_name:,
        extensions:         ["ext/json/ext/generator/extconf.rb", "ext/json/ext/parser/extconf.rb"],
        extension_dir:      extension_dir.to_s,
        full_require_paths: [extension_dir.to_s, gem_lib_dir.to_s],
      )
    end
    sig { returns(Bundler::Definition) }
    let(:definition) do
      instance_double(
        Bundler::Definition,
        resolve:             instance_double(Bundler::SpecSet, materialize: [spec]),
        locked_dependencies: [],
      )
    end
    # rubocop:enable RSpec/ScatteredLet

    before do
      stub_const("Utils::GemSetup::VENDOR_VERSION_FILE", version_file)
      allow(Gem).to receive(:dir).and_return(gem_dir)

      spec_file = Pathname(gem_dir)/"specifications/#{full_name}.gemspec"
      cache_file = Pathname(gem_dir)/"cache/#{full_name}.gem"
      gem_file = gem_lib_dir/"json.rb"
      [spec_file, cache_file, gem_file].each do |path|
        path.dirname.mkpath
        path.write("")
      end

      allow(Utils::GemSetup).to receive_messages(
        setup_gem_environment!: nil,
        valid_gem_groups:       %w[
          extensions_in_lib missing_extension missing_cache missing_cache_json missing_json_extension
          missing_cache_intact missing_package_file
        ],
        user_gem_groups:        [],
        user_vendor_version:    9,
        bundler_definition:     definition,
        find_in_path:           "/tmp",
        write_user_gem_groups:  nil,
      )
      allow(IO).to receive(:popen).with(["/tmp/bundle", "check"], err: [:child, :out]).and_return("")
      allow(Gem::Package).to receive(:new).with(cache_file.to_s)
                                          .and_return(instance_double(Gem::Package, contents: ["lib/json.rb"]))
      allow(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "clean", out: :err).and_return(true)
      allow(Homebrew::Bootsnap).to receive(:reset!)
      Kernel.system("true")
    end

    it "reinstalls gems if any declared native extension is missing" do
      [extension_dir, gem_lib_dir].each do |path|
        extension_file = path/"json/ext/generator.#{RbConfig::CONFIG.fetch("DLEXT")}"
        extension_file.dirname.mkpath
        extension_file.write("")
      end

      expect(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["missing_extension"])
      end
    end

    it "reinstalls gems if a JSON extension is missing despite other native extensions" do
      generator = extension_dir/"json/ext/generator.#{RbConfig::CONFIG.fetch("DLEXT")}"
      unrelated_extension = gem_lib_dir/"unrelated.#{RbConfig::CONFIG.fetch("DLEXT")}"
      [generator, unrelated_extension].each do |path|
        path.dirname.mkpath
        path.write("")
      end

      expect(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["missing_json_extension"])
      end
    end

    it "accepts native extensions copied into the gem's lib directory" do
      %w[generator parser].each do |name|
        extension_file = gem_lib_dir/"json/ext/#{name}.#{RbConfig::CONFIG.fetch("DLEXT")}"
        extension_file.dirname.mkpath
        extension_file.write("")
      end

      expect(Utils::GemSetup).not_to receive(:system).with("/tmp/bundle", "install", out: :err)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["extensions_in_lib"])
      end
    end

    it "accepts JSON extensions split between the extension directory and gem lib directory" do
      extension_dir_file = extension_dir/"json/ext/generator.#{RbConfig::CONFIG.fetch("DLEXT")}"
      gem_lib_file = gem_lib_dir/"json/ext/parser.#{RbConfig::CONFIG.fetch("DLEXT")}"
      [extension_dir_file, gem_lib_file].each do |path|
        path.dirname.mkpath
        path.write("")
      end

      expect(Utils::GemSetup).not_to receive(:system).with("/tmp/bundle", "install", out: :err)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["extensions_in_lib"])
      end
    end

    it "checks native extensions when the gem package cache is missing" do
      (Pathname(gem_dir)/"cache/#{full_name}.gem").unlink
      allow(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)
      expect(File).to receive(:file?).at_least(:once).and_call_original

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["missing_cache"])
      end
    end

    it "does not reinstall intact gems if the package cache is missing" do
      (Pathname(gem_dir)/"cache/#{full_name}.gem").unlink
      %w[generator parser].each do |name|
        extension_file = gem_lib_dir/"json/ext/#{name}.#{RbConfig::CONFIG.fetch("DLEXT")}"
        extension_file.dirname.mkpath
        extension_file.write("")
      end

      expect(Utils::GemSetup).not_to receive(:system).with("/tmp/bundle", "install", out: :err)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["missing_cache_intact"])
      end
    end

    it "reinstalls JSON if its library file and package cache are missing" do
      (Pathname(gem_dir)/"cache/#{full_name}.gem").unlink
      (gem_lib_dir/"json.rb").unlink
      %w[generator parser].each do |name|
        extension_file = gem_lib_dir/"json/ext/#{name}.#{RbConfig::CONFIG.fetch("DLEXT")}"
        extension_file.dirname.mkpath
        extension_file.write("")
      end

      expect(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["missing_cache_json"])
      end
    end

    it "reinstalls gems if a packaged file is missing" do
      (gem_lib_dir/"json.rb").unlink
      %w[generator parser].each do |name|
        extension_file = gem_lib_dir/"json/ext/#{name}.#{RbConfig::CONFIG.fetch("DLEXT")}"
        extension_file.dirname.mkpath
        extension_file.write("")
      end

      expect(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)

      with_env(HOMEBREW_TESTS: nil) do
        Utils::GemSetup.install_bundler_gems!(groups: ["missing_package_file"])
      end
    end
  end
end
