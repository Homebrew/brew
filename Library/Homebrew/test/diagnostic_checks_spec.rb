# typed: false
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  specify "#inject_file_list" do
    expect(checks.inject_file_list([], "foo:\n")).to eq("foo:\n")
    expect(checks.inject_file_list(%w[/a /b], "foo:\n")).to eq("foo:\n  /a\n  /b\n")
  end

  specify "#check_for_installed_developer_tools uses installation instructions" do
    allow(DevelopmentTools).to receive_messages(installed?: false, installation_instructions: "Install build tools.")

    expect(checks.check_for_installed_developer_tools).to eq <<~EOS
      No developer tools installed.
      Install build tools.
    EOS
  end

  specify "#check_access_directories" do
    skip "User is root so everything is writable." if Process.euid.zero?
    begin
      dirs = [
        HOMEBREW_CACHE,
        HOMEBREW_CELLAR,
        HOMEBREW_REPOSITORY,
        HOMEBREW_LOGS,
        HOMEBREW_LOCKS,
      ]
      modes = {}
      dirs.each do |dir|
        modes[dir] = dir.stat.mode & 0777
        dir.chmod 0555
        expect(checks.check_access_directories).to match(dir.to_s)
      end
    ensure
      modes.each do |dir, mode|
        dir.chmod mode
      end
    end
  end

  specify "#check_user_path_1" do
    bin = HOMEBREW_PREFIX/"bin"
    sep = File::PATH_SEPARATOR
    # ensure /usr/bin is before HOMEBREW_PREFIX/bin in the PATH
    ENV["PATH"] = "/usr/bin#{sep}#{bin}#{sep}" +
                  ENV["PATH"].gsub(%r{(?:^|#{sep})(?:/usr/bin|#{bin})}, "")

    # ensure there's at least one file with the same name in both /usr/bin/ and
    # HOMEBREW_PREFIX/bin/
    (bin/File.basename(Dir["/usr/bin/*"].first)).mkpath

    expect(checks.check_user_path_1)
      .to match("/usr/bin occurs before #{HOMEBREW_PREFIX}/bin")
  end

  specify "#check_user_path_2" do
    ENV["PATH"] = ENV["PATH"].gsub \
      %r{(?:^|#{File::PATH_SEPARATOR})#{HOMEBREW_PREFIX}/bin}o, ""

    expect(checks.check_user_path_1).to be_nil
    expect(checks.check_user_path_2)
      .to match("Homebrew's \"bin\" was not found in your PATH.")
  end

  specify "#check_user_path_3" do
    sbin = HOMEBREW_PREFIX/"sbin"
    (sbin/"something").mkpath

    homebrew_path =
      "#{HOMEBREW_PREFIX}/bin#{File::PATH_SEPARATOR}" +
      ENV["HOMEBREW_PATH"].gsub(/(?:^|#{Regexp.escape(File::PATH_SEPARATOR)})#{Regexp.escape(sbin)}/, "")
    stub_const("ORIGINAL_PATHS", PATH.new(homebrew_path).filter_map { |path| Pathname.new(path).expand_path })

    expect(checks.check_user_path_1).to be_nil
    expect(checks.check_user_path_2).to be_nil
    expect(checks.check_user_path_3)
      .to match("Homebrew's \"sbin\" was not found in your PATH")
  ensure
    FileUtils.rm_rf(sbin)
  end

  specify "#check_for_symlinked_cellar" do
    FileUtils.rm_r(HOMEBREW_CELLAR)

    mktmpdir do |path|
      FileUtils.ln_s path, HOMEBREW_CELLAR

      expect(checks.check_for_symlinked_cellar).to match(path)
    end
  ensure
    HOMEBREW_CELLAR.unlink
    HOMEBREW_CELLAR.mkpath
  end

  specify "#check_homebrew_repository_git_hooks" do
    mktmpdir do |path|
      stub_const("HOMEBREW_REPOSITORY", path)

      hook = path/".git/hooks/post-checkout"
      hook.dirname.mkpath
      hook.write("#!/bin/sh\n")
      gitconfig = path/".gitconfig"
      gitconfig.write("[safe]\n")

      expect(checks.check_homebrew_repository_git_hooks).to eq <<~EOS
        Git hooks or a repository-local `.gitconfig` were found in your Homebrew repository.
        Homebrew does not use these, and they can break Homebrew operations.
        Remove them with:
          rm -rf "#{path}/.git/hooks" "#{path}/.gitconfig"

        Paths found:
          #{hook}
          #{gitconfig}
      EOS
    end
  end

  specify "#check_homebrew_repository_git_hooks ignores sample hooks" do
    mktmpdir do |path|
      stub_const("HOMEBREW_REPOSITORY", path)

      hook = path/".git/hooks/post-checkout.sample"
      hook.dirname.mkpath
      hook.write("#!/bin/sh\n")

      expect(checks.check_homebrew_repository_git_hooks).to be_nil
    end
  end

  specify "#check_untrusted_taps" do
    foo_tap = instance_double(Tap, name: "thirdparty/foo")
    bar_tap = instance_double(Tap, name: "thirdparty/bar")
    foo_rack = HOMEBREW_CELLAR/"foo-formula"
    bar_rack = HOMEBREW_CELLAR/"bar-formula"
    foo_keg = instance_double(Keg, tab: instance_double(Tab, tap: foo_tap))
    bar_keg = instance_double(Keg, tab: instance_double(Tab, tap: bar_tap))
    foo_cask = instance_double(Cask::Cask, token: "foo-cask", tab: instance_double(Cask::Tab, tap: foo_tap))
    bar_cask = instance_double(Cask::Cask, token: "bar-cask", tab: instance_double(Cask::Tab, tap: bar_tap))
    allow(Homebrew::Trust).to receive(:wholly_untrusted_taps).and_return([foo_tap, bar_tap])
    allow(Formula).to receive(:racks).and_return([foo_rack, bar_rack])
    allow(Keg).to receive(:from_rack).with(foo_rack).and_return(foo_keg)
    allow(Keg).to receive(:from_rack).with(bar_rack).and_return(bar_keg)
    allow(Cask::Caskroom).to receive(:casks).and_return([foo_cask, bar_cask])

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      check_untrusted_taps = checks.check_untrusted_taps
      expect(check_untrusted_taps).to eq <<~EOS
        The following taps are not trusted:
          thirdparty/foo
          thirdparty/bar

        Homebrew is currently ignoring formulae, casks and commands from these taps because tap trust is required.
        Prefer trusting only the specific formulae, casks or commands you need.
        Trust installed formulae from these taps with:
          brew trust --formula thirdparty/bar/bar-formula
          brew trust --formula thirdparty/foo/foo-formula
        Trust installed casks from these taps with:
          brew trust --cask thirdparty/bar/bar-cask
          brew trust --cask thirdparty/foo/foo-cask
        Trust other specific commands with:
          brew trust --command <user>/<tap>/<command>
        Whole-tap trust is broader and includes all current and future formulae,
        casks and commands from the listed taps. Trust whole taps with:
          brew trust thirdparty/foo thirdparty/bar
        Untap them with:
          brew untap thirdparty/foo thirdparty/bar
        To disable trust checks:
          export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
        This is not recommended and will be removed in a later release.
        For more information, see:
          #{Formatter.url("https://docs.brew.sh/Tap-Trust")}
      EOS

      expect(check_untrusted_taps)
        .not_to include(
          "brew trust --formula <user>/<tap>/<formula>",
          "brew trust --cask <user>/<tap>/<cask>",
        )
    end
  end

  specify "#check_untrusted_taps requires trust by default" do
    tap = instance_double(Tap, name: "thirdparty/foo")
    allow(Homebrew::Trust).to receive(:wholly_untrusted_taps).and_return([tap])
    allow(Formula).to receive(:racks).and_return([])
    allow(Cask::Caskroom).to receive(:casks).and_return([])

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: nil, HOMEBREW_NO_REQUIRE_TAP_TRUST: nil) do
      check_untrusted_taps = checks.check_untrusted_taps
      expect(check_untrusted_taps).to eq <<~EOS
        The following taps are not trusted:
          thirdparty/foo

        Homebrew is currently ignoring formulae, casks and commands from these taps because tap trust is required.
        Untap them with:
          brew untap thirdparty/foo
        Trust specific formulae, casks and commands with:
          brew trust --formula <user>/<tap>/<formula>
          brew trust --cask <user>/<tap>/<cask>
          brew trust --command <user>/<tap>/<command>
        Whole-tap trust is broader and includes all current and future formulae,
        casks and commands from the listed taps. Trust whole taps with:
          brew trust thirdparty/foo
        To disable trust checks:
          export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
        This is not recommended and will be removed in a later release.
        For more information, see:
          #{Formatter.url("https://docs.brew.sh/Tap-Trust")}
      EOS
    end
  end

  specify "#check_untrusted_taps hides trust checks opt-out with HOMEBREW_NO_ENV_HINTS" do
    tap = instance_double(Tap, name: "thirdparty/foo")
    allow(Homebrew::Trust).to receive(:wholly_untrusted_taps).and_return([tap])
    allow(Formula).to receive(:racks).and_return([])
    allow(Cask::Caskroom).to receive(:casks).and_return([])

    with_env(HOMEBREW_NO_ENV_HINTS: "1") do
      check_untrusted_taps = checks.check_untrusted_taps
      expect(check_untrusted_taps).to include(Formatter.url("https://docs.brew.sh/Tap-Trust"))
      expect(check_untrusted_taps).not_to include("export HOMEBREW_NO_REQUIRE_TAP_TRUST=1")
    end
  end

  specify "#check_untrusted_taps skips when tap trust is explicitly disabled" do
    with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect(Homebrew::Trust).not_to receive(:wholly_untrusted_taps)

      expect(checks.check_untrusted_taps).to be_nil
    end
  end

  specify "#check_tmpdir" do
    ENV["TMPDIR"] = "/i/don/t/exis/t"
    expect(checks.check_tmpdir).to match("doesn't exist")
  end

  specify "#check_for_nix_homebrew" do
    stub_const("HOMEBREW_REPOSITORY", HOMEBREW_PREFIX/"Library/.homebrew-is-managed-by-nix")

    expect(checks.check_for_nix_homebrew)
      .to include("This is a Tier 3 configuration", "https://github.com/zhaofengli/nix-homebrew/issues")
  end

  specify "#check_for_external_cmd_name_conflict" do
    mktmpdir do |path1|
      mktmpdir do |path2|
        [path1, path2].each do |path|
          cmd = "#{path}/brew-foo"
          FileUtils.touch cmd
          FileUtils.chmod 0755, cmd
        end

        allow(Commands).to receive(:tap_cmd_directories).and_return([path1, path2])

        expect(checks.check_for_external_cmd_name_conflict)
          .to match("brew-foo")
      end
    end
  end

  specify "#check_homebrew_prefix" do
    allow(Homebrew).to receive(:default_prefix?).and_return(false)
    expect(checks.check_homebrew_prefix)
      .to match("Your Homebrew's prefix is not #{Homebrew::DEFAULT_PREFIX}")
  end

  specify "#check_for_unnecessary_core_tap" do
    ENV.delete("HOMEBREW_DEVELOPER")

    expect_any_instance_of(CoreTap).to receive(:installed?).and_return(true)

    expect(checks.check_for_unnecessary_core_tap).to match("You have an unnecessary local Core tap")
  end

  specify "#check_for_unnecessary_cask_tap" do
    ENV.delete("HOMEBREW_DEVELOPER")

    expect_any_instance_of(CoreCaskTap).to receive(:installed?).and_return(true)

    expect(checks.check_for_unnecessary_cask_tap).to match("unnecessary local Cask tap")
  end

  specify "#check_cask_corrupt_dirs" do
    allow(Cask::Caskroom).to receive(:corrupt_cask_dirs).and_return(["google-chrome", "docker-desktop"])

    expect(checks.check_cask_corrupt_dirs).to eq <<~EOS
      Some directories in the Caskroom do not have valid metadata.
        #{Cask::Caskroom.path}/google-chrome
        #{Cask::Caskroom.path}/docker-desktop
      The following casks cannot be upgraded as-is.
      To fix this, run:
        brew reinstall --cask --force google-chrome
        brew reinstall --cask --force docker-desktop
    EOS
  end
end
