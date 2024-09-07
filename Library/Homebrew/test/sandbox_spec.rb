# frozen_string_literal: true

require "sandbox"

RSpec.describe Sandbox, :needs_macos do
  define_negated_matcher :not_matching, :matching

  subject(:sandbox) { described_class.new }

  let(:dir) { mktmpdir }
  let(:file) { dir/"foo" }

  before do
    skip "Sandbox not implemented." unless described_class.available?
  end

  specify "#allow_write" do
    sandbox.allow_write path: file
    sandbox.run "touch", file

    expect(file).to exist
  end

  describe "#path_filter" do
    ["'", '"', "(", ")", "\n", "\\"].each do |char|
      it "fails if the path contains #{char}" do
        expect do
          sandbox.path_filter("foo#{char}bar", :subpath)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe "#allow_write_cellar" do
    it "fails when the formula has a name including )" do
      f = formula do
        url "https://brew.sh/foo-1.0.tar.gz"
        version "1.0"

        def initialize(*, **)
          super
          @name = "foo)bar"
        end
      end

      expect do
        sandbox.allow_write_cellar f
      end.to raise_error(ArgumentError)
    end

    it "fails when the formula has a name including \"" do
      f = formula do
        url "https://brew.sh/foo-1.0.tar.gz"
        version "1.0"

        def initialize(*, **)
          super
          @name = "foo\"bar"
        end
      end

      expect do
        sandbox.allow_write_cellar f
      end.to raise_error(ArgumentError)
    end
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
        expect { sandbox.run "chmod", "ug-w", path/"foo" }.not_to raise_error(ErrorDuringExecution)
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
        expect { sandbox.run "chmod", "4000", path/"foo" }.not_to raise_error(ErrorDuringExecution)
      end
    end
  end
end
