# typed: strict
# frozen_string_literal: true

require "tap"
require "trust"

RSpec.describe Homebrew::Trust, :trust_store do
  it "lets HOMEBREW_NO_REQUIRE_TAP_TRUST override HOMEBREW_REQUIRE_TAP_TRUST" do
    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1", HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect(Homebrew::EnvConfig.require_tap_trust?).to be(false)
    end
  end

  it "trusts third-party taps" do
    tap = Tap.fetch("thirdparty", "foo")

    expect(described_class.trusted_tap?(tap)).to be(false)

    described_class.trust!(:tap, "thirdparty/foo")

    expect(described_class.trusted_tap?(tap)).to be(true)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust a custom-remote tap by its name but does by its remote URL" do
    tap = Tap.fetch("thirdparty", "custom")
    tap.path.mkpath
    system "git", "-C", tap.path.to_s, "init"
    system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://gitlab.com/other/repo"

    described_class.trust!(:tap, "thirdparty/custom")
    expect(described_class.trusted_tap?(tap)).to be(false)

    described_class.trust!(:tap, "https://gitlab.com/other/repo")
    expect(described_class.trusted_tap?(tap)).to be(true)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "canonicalises a GitHub default-remote URL to the tap name" do
    result = described_class.target("https://github.com/thirdparty/homebrew-foo", type: :tap)
    expect(result).to eq([:tap, "thirdparty/foo"])
  end

  it "stores a non-GitHub URL verbatim" do
    result = described_class.target("https://gitlab.com/other/repo", type: :tap)
    expect(result).to eq([:tap, "https://gitlab.com/other/repo"])
  end

  it "trusts a not-yet-installed tap by its non-GitHub remote URL" do
    described_class.trust!(:tap, "https://gitlab.com/absent/repo")
    expect(described_class.trusted_entries(:tap)).to include("https://gitlab.com/absent/repo")
  ensure
    described_class.clear!(:tap)
  end

  it "untrusts a tap by its remote URL" do
    described_class.trust!(:tap, "https://gitlab.com/other/repo")
    type, trust_name = described_class.target("https://gitlab.com/other/repo", type: :tap, include_existing: true)
    removed = described_class.untrust!(type, trust_name)
    expect(removed).to be(true)
    expect(described_class.trusted_entries(:tap)).not_to include("https://gitlab.com/other/repo")
  ensure
    described_class.clear!(:tap)
  end

  it "invalidates old tap trust entries after a redirect" do
    described_class.trust!(:tap, "thirdparty/foo")
    described_class.trust!(:tap, "https://gitlab.com/old/repo")
    described_class.trust!(:formula, "thirdparty/foo/bar")
    described_class.trust!(:cask, "thirdparty/foo/baz")
    described_class.trust!(:command, "thirdparty/foo/hello")

    expect(described_class.invalidate_tap_references!("thirdparty/foo",
                                                      remote: "https://gitlab.com/old/repo")).to be(true)

    expect(described_class.trusted_entries(:tap)).to be_empty
    expect(described_class.trusted_entries(:formula)).to be_empty
    expect(described_class.trusted_entries(:cask)).to be_empty
    expect(described_class.trusted_entries(:command)).to be_empty
  ensure
    described_class.clear!(:tap)
    described_class.clear!(:formula)
    described_class.clear!(:cask)
    described_class.clear!(:command)
  end

  it "infers tap type for a remote URL argument" do
    result = described_class.target("https://gitlab.com/other/repo")
    expect(result).to eq([:tap, "https://gitlab.com/other/repo"])
  end

  it "infers tap type for an scp-style remote URL argument" do
    result = described_class.target("git@gitlab.com:other/repo")
    expect(result).to eq([:tap, "git@gitlab.com:other/repo"])
  end

  it "rejects a bare @-string rather than trusting it as a tap" do
    expect { described_class.target("foo@bar") }
      .to raise_error(UsageError, /fully-qualified/)
    expect(described_class.trusted_entries(:tap)).to be_empty
  end

  it "rejects a bare @-string even with an explicit tap type" do
    expect { described_class.target("not@valid", type: :tap) }
      .to raise_error(UsageError, /Invalid tap name/)
    expect(described_class.trusted_entries(:tap)).to be_empty
  end

  it "trusts custom-remote tap items by remote but still resolves existing entries to untrust" do
    tap = Tap.fetch("thirdparty", "custom")
    tap.path.mkpath
    system "git", "-C", tap.path.to_s, "init"
    system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://gitlab.com/other/repo"

    described_class.trust!(*described_class.target("thirdparty/custom/bar", type: :formula))

    expect(described_class.trusted?(:formula, "thirdparty/custom/bar")).to be(true)
    expect(described_class.trusted_entries(:formula)).to contain_exactly("https://gitlab.com/other/repo/bar")

    described_class.trust!(:formula, "thirdparty/custom/legacy")
    expect(described_class.target("thirdparty/custom/legacy", type: :formula, include_existing: true))
      .to eq([:formula, "thirdparty/custom/legacy"])
  ensure
    described_class.clear!(:formula)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "trusts formulae from trusted taps" do
    Tap.fetch("trustedformulae", "foo")

    described_class.trust!(:tap, "trustedformulae/foo")

    expect(described_class.trusted?(:formula, "trustedformulae/foo/bar")).to be(true)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"trustedformulae"
  end

  it "ignores a trust file with a non-object JSON root" do
    trust_file = T.let(nil, T.nilable(Pathname))
    trust_file = described_class.trust_file
    trust_file.dirname.mkpath
    trust_file.write("[]")

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    trust_file.unlink if trust_file&.exist?
  end

  it "trusts a GitHub SSH-remote tap by its name" do
    tap = Tap.fetch("thirdparty", "foo")
    tap.path.mkpath
    system "git", "-C", tap.path.to_s, "init"
    system "git", "-C", tap.path.to_s, "remote", "add", "origin", "git@github.com:thirdparty/homebrew-foo"
    # Guard the setup so the test genuinely exercises SSH-vs-HTTPS equivalence: a
    # remote-less tap would also be trusted by name, passing for the wrong reason.
    expect(tap.remote).to eq("git@github.com:thirdparty/homebrew-foo")

    described_class.trust!(:tap, "thirdparty/foo")

    expect(described_class.trusted_tap?(tap)).to be(true)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "untrusts third-party taps" do
    described_class.trust!(:tap, "thirdparty/foo")

    expect(described_class.untrust!(:tap, "thirdparty/foo")).to be(true)
    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
  end

  it "does not lose entries when trusting concurrently" do
    names = Array.new(10) { |i| "thirdparty/foo/formula#{i}" }

    names.map do |name|
      Thread.new { described_class.trust!(:formula, name) }
    end.each(&:join)

    expect(described_class.trusted_entries(:formula)).to match_array(names)
  ensure
    described_class.clear!(:formula)
  end

  it "trusts fully-qualified formulae and casks" do
    tap = Tap.fetch("qualified", "foo")
    tap.formula_dir.mkpath
    tap.cask_dir.mkpath
    (tap.formula_dir/"bar.rb").write("class Bar < Formula; end\n")
    (tap.cask_dir/"baz.rb").write("cask 'baz'\n")

    without_partial_double_verification do
      expect($stderr).to receive(:ohai).with("Trusted formula qualified/foo/bar").ordered
      expect($stderr).to receive(:ohai).with("Trusted cask qualified/foo/baz").ordered

      described_class.trust_fully_qualified_items!(["qualified/foo/bar", "qualified/foo/baz"])
    end

    expect(described_class.trusted?(:formula, "qualified/foo/bar")).to be(true)
    expect(described_class.trusted?(:cask, "qualified/foo/baz")).to be(true)
  ensure
    described_class.clear!(:formula)
    described_class.clear!(:cask)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"qualified"
  end

  it "does not trust missing fully-qualified formulae or casks" do
    Tap.fetch("thirdparty", "foo")

    described_class.trust_fully_qualified_items!(["thirdparty/foo/bar"], type: :formula)
    described_class.trust_fully_qualified_items!(["thirdparty/foo/baz"], type: :cask)

    expect(described_class.trusted?(:formula, "thirdparty/foo/bar")).to be(false)
    expect(described_class.trusted?(:cask, "thirdparty/foo/baz")).to be(false)
  ensure
    described_class.clear!(:formula)
    described_class.clear!(:cask)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not report taps with trusted entries as wholly untrusted" do
    allow(described_class).to receive(:untrusted_taps)
      .and_return([
        instance_double(Tap, name: "thirdparty/foo", reference: "thirdparty/foo", uses_custom_remote?: false),
      ])
    described_class.trust!(:formula, "thirdparty/foo/bar")

    expect(described_class.wholly_untrusted_taps).to be_empty
  ensure
    described_class.clear!(:formula)
  end

  it "writes the trust store with user-only permissions" do
    described_class.trust!(:tap, "thirdparty/foo")

    trust_file = described_class.trust_file
    expect(trust_file.stat.mode & 0777).to eq(0600)
  ensure
    described_class.clear!(:tap)
  end

  it "creates the trust store directory with user-only permissions" do
    trust_file = described_class.trust_file
    FileUtils.rm_rf trust_file.dirname
    old_umask = T.let(nil, T.nilable(Integer))
    old_umask = File.umask(0002)

    described_class.trust!(:tap, "thirdparty/foo")

    expect(trust_file.dirname.stat.mode & 0777).to eq(0700)
  ensure
    File.umask(old_umask) if old_umask
    described_class.clear!(:tap)
  end

  it "rejects a trust store in a group-writable directory" do
    trust_file = T.let(nil, T.nilable(Pathname))
    trust_file = described_class.trust_file
    trust_file.dirname.chmod(0770)

    expect { described_class.trust!(:tap, "thirdparty/foo") }
      .to raise_error(Homebrew::InsecureTrustStoreError, /Refusing to write insecure trust store/)
  ensure
    if trust_file
      trust_file.dirname.chmod(0700) if trust_file.dirname.exist?
      FileUtils.rm_f trust_file
    end
  end

  it "rejects a group-writable trust store" do
    trust_file = T.let(nil, T.nilable(Pathname))
    trust_file = described_class.trust_file
    trust_file.write(JSON.generate({ trustedtaps: ["thirdparty/foo"] }))
    trust_file.chmod(0660)

    expect { described_class.trust!(:tap, "thirdparty/bar") }
      .to raise_error(Homebrew::InsecureTrustStoreError, /Refusing to write insecure trust store/)
  ensure
    trust_file.chmod(0600) if trust_file&.exist?
    FileUtils.rm_f trust_file if trust_file
  end

  it "writes a symlinked trust store through to its target" do
    trust_file = described_class.trust_file
    target_dir = T.let(nil, T.nilable(Pathname))
    target_dir = Pathname(TEST_TMPDIR)/"trust-target"
    target_dir.mkpath
    target_file = target_dir/"trust.json"
    target_file.write(JSON.generate({ trustedtaps: ["thirdparty/foo"] }))
    FileUtils.ln_s target_file, trust_file

    described_class.trust!(:tap, "thirdparty/bar")

    expect(trust_file).to be_a_symlink
    expect(JSON.parse(target_file.read).fetch("trustedtaps")).to eq(["thirdparty/bar", "thirdparty/foo"])
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf target_dir if target_dir
  end

  it "rejects a symlinked trust store in a group-writable directory" do
    trust_file = described_class.trust_file
    target_dir = T.let(nil, T.nilable(Pathname))
    target_dir = Pathname(TEST_TMPDIR)/"trust-target"
    target_dir.mkpath
    target_dir.chmod(0770)
    FileUtils.ln_s target_dir/"trust.json", trust_file

    expect { described_class.trust!(:tap, "thirdparty/foo") }
      .to raise_error(Homebrew::InsecureTrustStoreError, /Refusing to write insecure trust store/)
  ensure
    target_dir.chmod(0700) if target_dir&.exist?
    FileUtils.rm_rf target_dir if target_dir
  end

  it "rejects a symlinked trust store pointing to another symlink" do
    trust_file = described_class.trust_file
    target_dir = T.let(nil, T.nilable(Pathname))
    target_dir = Pathname(TEST_TMPDIR)/"trust-target"
    target_dir.mkpath
    FileUtils.ln_s target_dir/"real-trust.json", target_dir/"trust.json"
    FileUtils.ln_s target_dir/"trust.json", trust_file

    expect { described_class.trust!(:tap, "thirdparty/foo") }
      .to raise_error(Homebrew::InsecureTrustStoreError, /Refusing to write insecure trust store/)
  ensure
    FileUtils.rm_rf target_dir if target_dir
  end

  it "requires third-party taps by default" do
    described_class.clear!(:tap)
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    expect { described_class.require_trusted_formula!("default-trust", formula_path) }
      .to raise_error(Homebrew::UntrustedTapError)

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust or store default trust when checking files" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    expect { expect(described_class.trusted_formula_file?(formula_path)).to be(false) }
      .not_to output.to_stderr

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust untrusted files when trust checks are enabled" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      expect(described_class.trusted_formula_file?(formula_path)).to be(false)
    end
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "allows explicitly named formula files when trust checks are enabled" do
    old_argv = ARGV.dup
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      ARGV.replace(["thirdparty/foo/default-trust"])
      expect(described_class.trusted_formula_file?(formula_path)).to be(true)
    end

    expect(described_class.trusted?(:formula, "thirdparty/foo/default-trust")).to be(false)
  ensure
    ARGV.replace(old_argv) if old_argv
    described_class.clear!(:tap)
    described_class.clear!(:formula)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "allows files from explicitly named taps when trust checks are enabled" do
    old_argv = ARGV.dup
    tap = Tap.fetch("thirdparty", "foo")
    cask_path = tap.cask_dir/"default-trust.rb"
    cask_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      ARGV.replace(["--tap", "thirdparty/foo"])
      expect(described_class.trusted_cask_file?(cask_path)).to be(true)
    end

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
    expect(described_class.trusted?(:cask, "thirdparty/foo/default-trust")).to be(false)
  ensure
    ARGV.replace(old_argv) if old_argv
    described_class.clear!(:tap)
    described_class.clear!(:cask)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not allow explicitly named command files when trust checks are enabled" do
    old_argv = ARGV.dup
    tap = Tap.fetch("thirdparty", "foo")
    command_path = tap.path/"cmd/brew-default-trust.rb"
    command_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      ARGV.replace(["thirdparty/foo/default-trust"])
      expect(described_class.trusted_command_files([command_path])).to eq([])
    end
  ensure
    ARGV.replace(old_argv) if old_argv
    described_class.clear!(:command)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust untrusted command files when trust checks are enabled" do
    tap = Tap.fetch("thirdparty", "foo")
    command_path = tap.path/"cmd/brew-default-trust.rb"
    command_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      expect { expect(described_class.trusted_command_files([command_path])).to eq([]) }
        .to output(%r{Skipping thirdparty/foo because it is not trusted}).to_stderr
    end
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not warn about a partially trusted tap when other files are untrusted" do
    tap = Tap.fetch("thirdparty", "foo")
    trusted_path = tap.formula_dir/"trusted.rb"
    untrusted_path = tap.formula_dir/"untrusted.rb"
    trusted_path.dirname.mkpath
    FileUtils.touch [trusted_path, untrusted_path]
    described_class.trust!(:formula, "thirdparty/foo/trusted")

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      expect { expect(described_class.trusted_formula_files([trusted_path, untrusted_path])).to eq([trusted_path]) }
        .not_to output.to_stderr
    end
  ensure
    described_class.clear!(:tap)
    described_class.clear!(:formula)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not store default trust when trust checks are disabled" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect { described_class.require_trusted_formula!("default-trust", formula_path) }
        .not_to output.to_stderr
    end

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end
end
