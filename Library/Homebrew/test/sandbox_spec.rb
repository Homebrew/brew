# frozen_string_literal: true

require "sandbox"

describe Sandbox, :needs_macos do
  define_negated_matcher :not_matching, :matching

  subject(:sandbox) { described_class.new }

  let(:dir) { mktmpdir }
  let(:file) { dir/"foo" }

  before do
    skip "Sandbox not implemented." unless described_class.available?
  end

  specify "#allow_write" do
    sandbox.allow_write file
    sandbox.exec "touch", file

    expect(file).to exist
  end

  describe "#exec" do
    it "fails when writing to file not specified with ##allow_write" do
      expect do
        sandbox.exec "touch", file
      end.to raise_error(ErrorDuringExecution)

      expect(file).not_to exist
    end

    it "complains on failure" do
      ENV["HOMEBREW_VERBOSE"] = "1"

      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read).with("syslog", any_args).and_return("foo")

      expect { sandbox.exec "false" }
        .to raise_error(ErrorDuringExecution)
        .and output(/foo/).to_stdout
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

      expect { sandbox.exec "false" }
        .to raise_error(ErrorDuringExecution)
        .and output(a_string_matching(/foo/).and(matching(/bar/).and(not_matching(/Python/)))).to_stdout
    end
  end
end
