# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
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

  describe "#formula_tap_url" do
    let(:tap) do
      instance_double(Tap, remote: "https://github.com/Homebrew/homebrew-core",
                           path:   Pathname.new("/tap/path"))
    end

    it "returns nil when tap is nil" do
      formula = instance_double(Formula, tap: nil)
      expect(checks.formula_tap_url(formula)).to be_nil
    end

    it "returns nil when tap remote is blank" do
      tap_no_remote = instance_double(Tap, remote: nil)
      formula = instance_double(Formula, tap: tap_no_remote)
      expect(checks.formula_tap_url(formula)).to be_nil
    end

    it "returns URL when tap has remote" do
      formula = instance_double(Formula, tap: tap, path: Pathname.new("/tap/path/Formula/w/wget.rb"))
      expect(checks.formula_tap_url(formula))
        .to eq "https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/w/wget.rb"
    end
  end

  describe "#cask_tap_url" do
    let(:tap) do
      instance_double(Tap, remote: "https://github.com/Homebrew/homebrew-cask")
    end

    before do
      allow(tap).to receive(:relative_cask_path).with("firefox").and_return("Casks/f/firefox.rb")
    end

    it "returns nil when tap is nil" do
      cask = instance_double(Cask::Cask, tap: nil)
      expect(checks.cask_tap_url(cask)).to be_nil
    end

    it "returns nil when tap remote is blank" do
      tap_no_remote = instance_double(Tap, remote: nil)
      cask = instance_double(Cask::Cask, tap: tap_no_remote)
      expect(checks.cask_tap_url(cask)).to be_nil
    end

    it "returns URL using remote and relative_cask_path" do
      cask = instance_double(Cask::Cask, tap: tap, token: "firefox")
      expect(checks.cask_tap_url(cask))
        .to eq "https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/f/firefox.rb"
    end
  end

  describe "#check_deprecated_disabled" do
    let(:tap) do
      instance_double(Tap, remote: "https://github.com/Homebrew/homebrew-core",
                           path:   Pathname.new("/tap/path"))
    end
    let(:head_spec) { instance_double(HeadSoftwareSpec, url: "https://github.com/example/repo.git") }

    it "returns nil when no formulae are deprecated or disabled" do
      allow(Formula).to receive(:installed).and_return([])
      expect(checks.check_deprecated_disabled).to be_nil
    end

    it "includes deprecated formula with homepage URL" do
      formula = instance_double(Formula, deprecated?: true, disabled?: false,
                                full_name: "deprecated-formula",
                                homepage: "https://example.com/deprecated",
                                head: nil, tap: tap,
                                path: Pathname.new("/tap/path/Formula/d/deprecated-formula.rb"))
      allow(Formula).to receive(:installed).and_return([formula])

      result = checks.check_deprecated_disabled
      expect(result).to match("deprecated-formula")
      expect(result).to match("https://example.com/deprecated")
    end

    it "falls back to head URL when homepage is nil" do
      formula = instance_double(Formula, deprecated?: false, disabled?: true,
                                full_name: "disabled-head-formula",
                                homepage: nil, head: head_spec, tap: tap,
                                path: Pathname.new("/tap/path/Formula/d/disabled-head-formula.rb"))
      allow(Formula).to receive(:installed).and_return([formula])

      result = checks.check_deprecated_disabled
      expect(result).to match("disabled-head-formula")
      expect(result).to match("https://github.com/example/repo.git")
    end

    it "falls back to tap URL when homepage and head are nil" do
      formula = instance_double(Formula, deprecated?: false, disabled?: true,
                                full_name: "disabled-formula",
                                homepage: nil, head: nil, tap: tap,
                                path: Pathname.new("/tap/path/Formula/d/disabled-formula.rb"))
      allow(Formula).to receive(:installed).and_return([formula])

      result = checks.check_deprecated_disabled
      expect(result).to match("disabled-formula")
      expect(result).to match("https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/d/disabled-formula.rb")
    end
  end

  describe "#check_cask_deprecated_disabled" do
    let(:tap) do
      instance_double(Tap, remote: "https://github.com/Homebrew/homebrew-cask")
    end

    before do
      allow(tap).to receive(:relative_cask_path).with("deprecated-cask").and_return("Casks/d/deprecated-cask.rb")
      allow(tap).to receive(:relative_cask_path).with("disabled-cask").and_return("Casks/d/disabled-cask.rb")
    end

    it "returns nil when no casks are deprecated or disabled" do
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      expect(checks.check_cask_deprecated_disabled).to be_nil
    end

    it "includes deprecated cask with homepage URL" do
      cask = instance_double(Cask::Cask, deprecated?: true, disabled?: false,
                             token: "deprecated-cask",
                             homepage: "https://example.com/deprecated-cask", tap: tap)
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])

      result = checks.check_cask_deprecated_disabled
      expect(result).to match("deprecated-cask")
      expect(result).to match("https://example.com/deprecated-cask")
    end

    it "falls back to cask tap URL when homepage is nil" do
      cask = instance_double(Cask::Cask, deprecated?: false, disabled?: true,
                             token: "disabled-cask", homepage: nil, tap: tap)
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])

      result = checks.check_cask_deprecated_disabled
      expect(result).to match("disabled-cask")
      expect(result).to match("https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/d/disabled-cask.rb")
    end
  end
end
