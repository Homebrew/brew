# typed: strict
# frozen_string_literal: true

require "cmd/uninstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::UninstallCmd do
  it_behaves_like "parseable arguments"

  it "uninstalls a given Formula and Cask path", :cask, :integration_test do
    tap = CoreCaskTap.instance
    cask_file = tap.cask_dir/"l/local-caffeine.rb"
    cask_file.dirname.mkpath
    FileUtils.cp cask_path("local-caffeine"), cask_file
    tap.clear_cache
    appdir = mktmpdir

    setup_test_formula "testball", tab_attributes: { installed_on_request: true }

    expect(HOMEBREW_CELLAR/"testball").to exist
    expect { brew "uninstall", "--force", "testball" }
      .to output(/Uninstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(HOMEBREW_CELLAR/"testball").not_to exist

    Dir.chdir(tap.path) do
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
      ENV["HOMEBREW_REQUIRE_TAP_TRUST"] = "1"
      ENV["HOMEBREW_NO_INSTALL_FROM_API"] = nil
      brew_env = { "HOMEBREW_SORBET_RUNTIME" => nil, "HOMEBREW_SORBET_RECURSIVE" => nil }
      expect do
        brew "install", "--cask", "--no-ask", "--appdir=#{appdir}", "./Casks/l/local-caffeine.rb", brew_env
      end
        .to output(/local-caffeine was successfully installed/).to_stdout
        .and be_a_success

      expect { brew "uninstall", "--cask", "./Casks/l/local-caffeine.rb", brew_env }
        .to output(/Uninstalling Cask local-caffeine/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    expect(appdir/"Caffeine.app").not_to exist
    expect(Cask::Caskroom.cask_installed?("local-caffeine")).to be(false)
  ensure
    FileUtils.rm_rf tap.path if tap
  end

  it "catches cask uninstall errors and sets Homebrew.failed" do
    allow(Cask::Uninstall).to receive(:uninstall_casks).and_raise(Cask::CaskError.new("test cask error"))
    allow(Cask::Uninstall).to receive(:check_dependent_casks)
    allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    allow(Homebrew::Cleanup).to receive(:autoremove)

    cask = Cask::Cask.new("test-cask")
    cmd = described_class.new(["test-cask"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([cask])

    expect { cmd.run }
      .to output(/test cask error/).to_stderr

    expect(Homebrew).to have_failed
  ensure
    Homebrew.failed = false
  end

  it "untrusts uninstalled casks" do
    cask = Cask::Cask.new("test-cask")
    allow(cask).to receive(:full_name).and_return("thirdparty/foo/test-cask")
    cmd = described_class.new(["thirdparty/foo/test-cask"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([cask])
    allow(Cask::Uninstall).to receive(:check_dependent_casks)
    allow(Cask::Uninstall).to receive(:uninstall_casks)
    allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    allow(Homebrew::Cleanup).to receive(:autoremove)

    expect(Homebrew::Trust).to receive(:untrust!)
      .with(:cask, "thirdparty/foo/test-cask")

    cmd.run
  end

  it "does not read an untrusted installed cask when uninstalling", :cask, :trust_store do
    tap = Tap.fetch("untrusted", "tap")
    full_name = "untrusted/tap/local-caffeine"
    cask_file = tap.cask_dir/"local-caffeine.rb"
    cask_file.dirname.mkpath
    FileUtils.cp cask_path("local-caffeine"), cask_file
    tap.clear_cache

    cask = with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      Cask::CaskLoader.load(full_name).tap { |cask| Cask::Installer.new(cask).install }
    end
    cask_file.write <<~RUBY
      raise "untrusted tap cask evaluated"
    RUBY
    installed_caskfile = cask.installed_caskfile
    (installed_caskfile.dirname/"local-caffeine.rb").write <<~RUBY
      raise "untrusted installed cask evaluated"
    RUBY
    installed_caskfile.unlink
    allow(Homebrew::Cleanup).to receive(:autoremove)

    original_argv = ARGV.dup
    begin
      ARGV.replace(["--cask", "--force", full_name])
      with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1", HOMEBREW_NO_REQUIRE_TAP_TRUST: nil) do
        expect { described_class.new(["--cask", "--force", full_name]).run }
          .to output(/Uninstalling Cask local-caffeine/).to_stdout
          .and output(/Skipping loading untrusted Cask #{full_name}; uninstalling recorded artifacts only/).to_stderr
          .and not_to_output(/untrusted .* cask evaluated/).to_stderr
      end
    ensure
      ARGV.replace(original_argv)
      FileUtils.rm_rf tap.path.parent
    end

    expect(Pathname(cask.config.appdir).join("Caffeine.app")).not_to exist
    expect(cask).not_to be_installed
  end

  it "reads installed JSON cask metadata when uninstalling from an untrusted tap", :cask, :trust_store do
    tap = Tap.fetch("untrusted", "json")
    full_name = "untrusted/json/local-caffeine"
    cask_file = tap.cask_dir/"local-caffeine.rb"
    cask_file.dirname.mkpath
    FileUtils.cp cask_path("local-caffeine"), cask_file
    tap.clear_cache

    cask = with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      Cask::CaskLoader.load(full_name).tap { |cask| Cask::Installer.new(cask).install }
    end
    cask_file.write <<~RUBY
      raise "untrusted tap cask evaluated"
    RUBY
    (cask.installed_caskfile.dirname/"local-caffeine.rb").write <<~RUBY
      raise "untrusted installed cask evaluated"
    RUBY
    allow(Homebrew::Cleanup).to receive(:autoremove)

    original_argv = ARGV.dup
    begin
      ARGV.replace(["--cask", "--force", full_name])
      with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1", HOMEBREW_NO_REQUIRE_TAP_TRUST: nil) do
        expect { described_class.new(["--cask", "--force", full_name]).run }
          .to output(/Uninstalling Cask local-caffeine/).to_stdout
          .and not_to_output(/Skipping loading untrusted Cask/).to_stderr
          .and not_to_output(/untrusted .* cask evaluated/).to_stderr
      end
    ensure
      ARGV.replace(original_argv)
      FileUtils.rm_rf tap.path.parent
    end

    expect(Pathname(cask.config.appdir).join("Caffeine.app")).not_to exist
    expect(cask).not_to be_installed
  end
end
