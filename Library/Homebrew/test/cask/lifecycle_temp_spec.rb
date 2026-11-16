# typed: strict
# frozen_string_literal: true

require "cask/upgrade"

RSpec.describe Cask::Installer, :cask do
  sig { params(version: String).returns(Cask::Cask) }
  def preserving_cask(version)
    Cask::Cask.new("with-preserved-environments", source: "{}") do
      version version
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      uninstall_preflight_steps do
        if_path_exists "base/envs", base: :caskroom_path do
          move "base/envs", "{{temp}}/{{token}}-envs", source_base: :caskroom_path
        end
      end

      preflight_steps do
        remove "base", base: :caskroom_path, recursive: true
        mkdir_p "base/envs", base: :caskroom_path
      end

      postflight_steps do
        if_path_exists "{{token}}-envs", base: :temp do
          remove "base/envs", base: :caskroom_path, recursive: true
          move "{{token}}-envs", "base/envs", source_base: :temp, target_base: :caskroom_path
        end
      end
    end
  end

  # Keep each memoised helper with its type signature.
  # rubocop:disable RSpec/ScatteredLet
  sig { returns(Cask::Cask) }
  let(:old_cask) { preserving_cask("1") }

  sig { returns(Cask::Cask) }
  let(:new_cask) { preserving_cask("2") }

  sig { returns(Pathname) }
  let(:marker) { old_cask.caskroom_path/"base/envs/demo/marker" }

  sig { returns(T::Array[Pathname]) }
  let(:temporary_paths) { [] }

  sig { returns(T::Array[Integer]) }
  let(:temporary_modes) { [] }
  # rubocop:enable RSpec/ScatteredLet

  sig { params(operation: Symbol).void }
  def run_operation(operation)
    if operation == :upgrade
      Cask::Upgrade.upgrade_cask(old_cask, new_cask, binaries: true, force: false, require_sha: false,
                                quit: false, skip_cask_deps: true, verbose: false,
                                download_queue: Homebrew::DownloadQueue.default)
    else
      described_class.new(new_cask, reinstall: true, zap: operation == :reinstall_with_zap).install
    end
  end

  before do
    stub_const("HOMEBREW_TEMP", (HOMEBREW_TEMP/"cask").tap(&:mkpath))
    old_cask.staged_path.mkpath
    described_class.new(old_cask).save_caskfile
    Cask::Tab.create(old_cask).write
    marker.dirname.mkpath
    marker.write "preserve me\n"

    allow(described_class).to receive(:new).and_wrap_original do |constructor, *args, **options|
      constructor.call(*args, **options).tap do |installer|
        allow(installer).to receive_messages(prelude: nil, fetch: nil)
        allow(installer).to receive(:stage) do
          installer.cask.staged_path.mkpath
          installer.save_caskfile
        end
      end
    end

    sandbox = instance_double(Sandbox).as_null_object
    allow(Sandbox).to receive_messages(available?: true, avoid_nested_sandboxing?: false, new: sandbox)
    allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
    allow(sandbox).to receive(:run) do |*args, **|
      temporary = Pathname(JSON.parse(File.binread(args.fetch(-2))).fetch("context").fetch("temp"))
      temporary_paths << temporary
      temporary_modes << (temporary.stat.mode & 0777)
      Dir.mktmpdir("sandbox-", HOMEBREW_TEMP) do |tmpdir|
        File.open(HOMEBREW_LIBRARY_PATH/"sandbox.rb") do |inheritance|
          Utils.safe_fork do
            exec({ "HOMEBREW_TEMP" => tmpdir }, *args.map(&:to_s), Sandbox::INHERITANCE_FD => inheritance)
          end
        end
      end
    end
  end

  test_each([:upgrade, :reinstall, :reinstall_with_zap]) do |operation|
    it "shares a private temporary directory until restoration, then removes it" do
      run_operation(operation)

      expect([
        marker.read,
        temporary_paths.uniq.length,
        temporary_paths.map(&:parent).uniq,
        temporary_modes.uniq,
        temporary_paths.any?(&:exist?),
      ]).to eq(["preserve me\n", 1, [HOMEBREW_TEMP], [0700], false])
    end

    it "retains backups when installation and restoration fail" do
      allow_any_instance_of(Cask::Artifact::PostflightSteps).to receive(:install_phase).and_raise("restore failed")

      expect { run_operation(operation) }.to raise_error("restore failed")
        .and output(/Temporary files retained at:/).to_stderr
      expect((temporary_paths.fetch(0)/"#{old_cask.token}-envs/demo/marker").read).to eq("preserve me\n")
    end

    it "fails and retains temporary storage when an expected backup disappears" do
      allow_any_instance_of(Cask::Artifact::PostflightSteps).to receive(:install_phase)
        .and_wrap_original do |method, **args|
        FileUtils.remove_entry_secure(new_cask.temp/"#{old_cask.token}-envs") if
          (new_cask.temp/"#{old_cask.token}-envs").exist?
        method.call(**args)
      end

      expect { run_operation(operation) }.to raise_error(/Expected cask backup is missing:/)
        .and output(/Temporary files retained at:/).to_stderr
      expect(temporary_paths.fetch(0)).to be_a_directory
    end

    it "does not require a backup when there was no data to preserve" do
      FileUtils.remove_entry_secure(marker.dirname.parent)

      expect { run_operation(operation) }.not_to raise_error
    end
  end

  it "uses a fresh private directory for separate uninstall and install operations" do
    described_class.new(old_cask).uninstall
    described_class.new(old_cask).install

    expect([
      temporary_paths.uniq.length,
      temporary_modes.uniq,
      temporary_paths.any?(&:exist?),
      marker.exist?,
    ]).to eq([2, [0700], false, false])
  end
end
