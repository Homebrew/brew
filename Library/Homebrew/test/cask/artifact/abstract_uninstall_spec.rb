# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AbstractUninstall, :cask do
  [
    [Cask::Artifact::Uninstall, :uninstall],
    [Cask::Artifact::Zap, :zap],
  ].each do |artifact_class, artifact_dsl_key|
    describe "#each_resolved_path for #{artifact_dsl_key.inspect}" do
      subject(:artifact) { cask.artifacts.find { |candidate| candidate.is_a?(artifact_class) } }

      let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-delete")) }

      around do |example|
        old_home = Dir.home
        ENV["HOME"] = TEST_TMPDIR
        example.run
      ensure
        ENV["HOME"] = old_home
      end

      it "skips relative paths" do
        result = nil
        expect do
          result = artifact.send(:each_resolved_path, :delete, ["relative/path"]).to_a
        end.to output(%r{Skipping delete for relative path 'relative/path'\.}).to_stderr

        expect(result).to be_empty
      end

      it "skips absolute paths containing relative segments" do
        tmpdir = Pathname.new(TEST_TMPDIR)
        valid_path = tmpdir/"each_resolved_path_#{artifact_dsl_key}"

        FileUtils.touch valid_path

        [
          tmpdir/"nested/../#{valid_path.basename}",
          tmpdir/"nested/./#{valid_path.basename}",
        ].each do |invalid_path|
          result = nil
          expect do
            result = artifact.send(:each_resolved_path, :delete, [invalid_path.to_s]).to_a
          end.to output(
            /Skipping delete for path with relative segments '#{Regexp.escape(invalid_path.to_s)}'\./,
          ).to_stderr

          expect(result).to be_empty
        end
      ensure
        FileUtils.rm_f valid_path
      end

      it "skips tilde paths containing relative segments" do
        invalid_path = "~/../each_resolved_path_#{artifact_dsl_key}"

        result = nil
        expect do
          result = artifact.send(:each_resolved_path, :delete, [invalid_path]).to_a
        end.to output(
          /Skipping delete for path with relative segments '#{Regexp.escape(invalid_path)}'\./,
        ).to_stderr

        expect(result).to be_empty
      end

      it "skips undeletable glob matches after expansion" do
        glob_dir = Pathname.new(TEST_TMPDIR)/"each_resolved_path_glob_#{artifact_dsl_key}"
        safe_path = glob_dir/"safe.plist"
        undeletable_path = glob_dir/"undeletable.plist"

        FileUtils.mkdir_p glob_dir
        FileUtils.touch [safe_path, undeletable_path]

        allow(artifact).to receive(:undeletable?) { |target| target == undeletable_path }

        result = nil
        expect do
          result = artifact.send(:each_resolved_path, :delete, ["#{glob_dir}/*.plist"]).to_a
        end.to output(
          /Skipping delete for undeletable path '#{Regexp.escape(undeletable_path.to_s)}'\./,
        ).to_stderr

        expect(result).to eq([["#{glob_dir}/*.plist", [safe_path]]])
      ensure
        FileUtils.rm_rf glob_dir
      end

      it "surfaces Full Disk Access guidance when globbing raises EPERM" do
        allow(Pathname).to receive(:glob).and_raise(Errno::EPERM)
        allow(File).to receive(:readable?).and_call_original
        allow(File).to receive(:readable?).with(File.expand_path("~/Library/Application Support/com.apple.TCC"))
                                          .and_return(false)
        allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:ventura))

        expect do
          artifact.send(:each_resolved_path, :delete, ["/tmp/each_resolved_path_#{artifact_dsl_key}"]).to_a
        end.to raise_error(SystemExit)
          .and output(/Full Disk Access/).to_stderr
      end
    end
  end
end
