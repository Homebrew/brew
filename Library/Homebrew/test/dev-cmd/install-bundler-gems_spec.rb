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

  it "rechecks an outdated bundle on developer startup" do
    allow(Utils::GemSetup).to receive(:user_vendor_version).and_return(9)

    ENV["HOMEBREW_DEVELOPER"] = nil
    ENV["HOMEBREW_DEV_CMD_RUN"] = "1"

    expect(Utils::GemSetup.initial_gem_install_required?(gems_vendored: true)).to be(true)
  end

  it "does not reinstall a vendored bundle outside developer mode" do
    allow(Utils::GemSetup).to receive(:user_vendor_version).and_return(9)

    ENV["HOMEBREW_DEVELOPER"] = nil
    ENV["HOMEBREW_DEV_CMD_RUN"] = nil

    expect(Utils::GemSetup.initial_gem_install_required?(gems_vendored: true)).to be(false)
  end

  it "reinstalls gems with missing native extensions" do
    gem_dir = mktmpdir
    full_name = "json-3.1.0"
    version_file = Pathname(gem_dir)/".homebrew_vendor_version"
    stub_const("Utils::GemSetup::VENDOR_VERSION_FILE", version_file)
    allow(Gem).to receive(:dir).and_return(gem_dir)

    spec_file = Pathname(gem_dir)/"specifications/#{full_name}.gemspec"
    cache_file = Pathname(gem_dir)/"cache/#{full_name}.gem"
    gem_file = Pathname(gem_dir)/"gems/#{full_name}/lib/json.rb"
    [spec_file, cache_file, gem_file].each do |path|
      path.dirname.mkpath
      path.write("")
    end

    spec = instance_double(
      Gem::Specification,
      full_name:,
      extensions: ["ext/json/ext/generator/extconf.rb"],
      extension_dir: (Pathname(gem_dir)/"extensions"/full_name).to_s,
    )
    definition = instance_double(
      Bundler::Definition,
      resolve:             instance_double(Bundler::SpecSet, materialize: [spec]),
      locked_dependencies: [],
    )

    allow(Utils::GemSetup).to receive_messages(
      setup_gem_environment!: nil,
      valid_gem_groups:       ["tests"],
      user_gem_groups:        [],
      user_vendor_version:    8,
      bundler_definition:     definition,
      find_in_path:           "/tmp",
      write_user_gem_groups:  nil,
    )
    allow(IO).to receive(:popen).with(["/tmp/bundle", "check"], err: [:child, :out]).and_return("")
    allow(Gem::Package).to receive(:new).with(cache_file.to_s)
                                        .and_return(instance_double(Gem::Package, contents: ["lib/json.rb"]))
    allow(Homebrew::Bootsnap).to receive(:reset!)
    expect(Utils::GemSetup).to receive(:system).with("/tmp/bundle", "install", out: :err).and_return(true)

    Kernel.system("true")
    with_env(HOMEBREW_TESTS: nil) do
      Utils::GemSetup.install_bundler_gems!(groups: ["tests"])
    end
  end
end
