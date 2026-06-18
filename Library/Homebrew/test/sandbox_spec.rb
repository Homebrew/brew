# typed: true
# frozen_string_literal: true

require "sandbox"

RSpec.describe Sandbox, :needs_macos do
  subject(:sandbox) { described_class.new }

  let(:dir) { mktmpdir }
  let(:file) { dir/"foo" }

  define_negated_matcher :not_matching, :matching

  before do
    skip "Sandbox not implemented." unless described_class.available?
  end

  specify "#allow_write" do
    sandbox.allow_write path: file
    sandbox.run "touch", file

    expect(file).to exist
  end

  it "writes to a path containing the seatbelt string delimiters \\ and \"" do
    delimiter_dir = dir/"I:\\ and \"quote\""
    delimiter_dir.mkpath
    target = delimiter_dir/"foo"
    sandbox.allow_write path: target
    sandbox.run "touch", target

    expect(target).to exist
  end

  describe "#run" do
    it "fails when writing to file not specified with ##allow_write" do
      expect do
        sandbox.run "touch", file
      end.to raise_error(ErrorDuringExecution)

      expect(file).not_to exist
    end

    it "complains on failure" do
      ENV["HOMEBREW_VERBOSE"] = "1"

      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read).with("syslog", any_args).and_return("foo")

      expect { sandbox.run "false" }
        .to raise_error(ErrorDuringExecution)
        .and output(/foo/).to_stdout
    end

    it "does not raise getcwd EPERM when the parent CWD is sandbox-denied" do
      mktmpdir do |denied|
        sandbox.deny_read_path(denied)
        Dir.chdir(denied) do
          expect { sandbox.run "/bin/pwd" }.not_to raise_error
        end
      end
    end

    it "ignores bogus Python error" do
      ENV["HOMEBREW_VERBOSE"] = "1"

      with_bogus_error = <<~EOS
        foo
        Mar 17 02:55:06 sandboxd[342]: Python(49765) deny file-write-unlink /System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/distutils/errors.pyc
        bar
      EOS
      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read).with("syslog", any_args).and_return(with_bogus_error)

      expect { sandbox.run "false" }
        .to raise_error(ErrorDuringExecution)
        .and output(a_string_matching(/foo/).and(matching(/bar/).and(not_matching(/Python/)))).to_stdout
    end
  end

  describe "#disallow chmod on some directory" do
    it "formula does a chmod to opt" do
      expect { sandbox.run "chmod", "ug-w", HOMEBREW_PREFIX }.to raise_error(ErrorDuringExecution)
    end

    it "allows chmod on a path allowed to write" do
      mktmpdir do |path|
        FileUtils.touch path/"foo"
        sandbox.allow_write_path(path)
        expect { sandbox.run "chmod", "ug-w", path/"foo" }.not_to raise_error
      end
    end
  end

  describe "#disallow chmod SUID or SGID on some directory" do
    it "formula does a chmod 4000 to opt" do
      expect { sandbox.run "chmod", "4000", HOMEBREW_PREFIX }.to raise_error(ErrorDuringExecution)
    end

    it "allows chmod 4000 on a path allowed to write" do
      mktmpdir do |path|
        FileUtils.touch path/"foo"
        sandbox.allow_write_path(path)
        expect { sandbox.run "chmod", "4000", path/"foo" }.not_to raise_error
      end
    end
  end
end
