# frozen_string_literal: true

require "diagnostic"

describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  specify "#inject_file_list" do
    expect(checks.inject_file_list([], "foo:\n")).to eq("foo:\n")
    expect(checks.inject_file_list(%w[/a /b], "foo:\n")).to eq("foo:\n  /a\n  /b\n")
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
    stub_const("ORIGINAL_PATHS", PATH.new(homebrew_path).map { |path| Pathname.new(path).expand_path }.compact)

    expect(checks.check_user_path_1).to be_nil
    expect(checks.check_user_path_2).to be_nil
    expect(checks.check_user_path_3)
      .to match("Homebrew's \"sbin\" was not found in your PATH")
  ensure
    sbin.rmtree
  end

  specify "#check_for_symlinked_cellar" do
    HOMEBREW_CELLAR.rmtree

    mktmpdir do |path|
      FileUtils.ln_s path, HOMEBREW_CELLAR

      expect(checks.check_for_symlinked_cellar).to match(path)
    end
  ensure
    HOMEBREW_CELLAR.unlink
    HOMEBREW_CELLAR.mkpath
  end

  specify "#check_tmpdir" do
    ENV["TMPDIR"] = "/i/don/t/exis/t"
    expect(checks.check_tmpdir).to match("doesn't exist")
  end

  specify "#check_for_external_cmd_name_conflict" do
    mktmpdir do |path1|
      mktmpdir do |path2|
        [path1, path2].each do |path|
          cmd = "#{path}/brew-foo"
          FileUtils.touch cmd
          FileUtils.chmod 0755, cmd
        end

        allow(Tap).to receive(:cmd_directories).and_return([path1, path2])

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
    ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")

    expect_any_instance_of(CoreTap).to receive(:installed?).and_return(true)

    expect(checks.check_for_unnecessary_core_tap).to match("You have an unnecessary local Core tap")
  end

  specify "#check_for_unnecessary_cask_tap" do
    ENV.delete("HOMEBREW_DEVELOPER")
    ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")

    expect_any_instance_of(CoreCaskTap).to receive(:installed?).and_return(true)

    expect(checks.check_for_unnecessary_cask_tap).to match("unnecessary local Cask tap")
  end
end
