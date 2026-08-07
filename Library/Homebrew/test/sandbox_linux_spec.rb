# typed: true
# frozen_string_literal: true

require "sandbox"
require "extend/os/linux/sandbox" if OS.linux?

RSpec.describe Sandbox, :needs_linux do
  subject(:sandbox) { described_class.new }

  describe "#run" do
    before do
      skip "Sandbox not available." unless described_class.available?
    end

    it "allows writing to an allowed path" do
      file = mktmpdir/"foo"
      sandbox.allow_write path: file
      sandbox.run "touch", file

      expect(file).to exist
    end

    it "fails when writing to a path that has not been allowed" do
      file = mktmpdir/"foo"

      expect do
        sandbox.run "touch", file
      end.to raise_error(ErrorDuringExecution)

      expect(file).not_to exist
    end

    it "returns the command exit status" do
      expect { sandbox.run "false" }.to raise_error(ErrorDuringExecution)
    end

    it "allows spawning a pseudo-terminal" do
      sandbox.deny_read_path mktmpdir

      expect do
        sandbox.run RUBY_PATH, "-rpty", "-e", 'PTY.spawn("true") { |_, _, pid| Process.wait(pid) }'
      end.not_to raise_error
    end

    it "prevents listing a denied read hierarchy" do
      denied_dir = mktmpdir
      FileUtils.touch denied_dir/"secret"
      sandbox.deny_read_path denied_dir

      expect { sandbox.run "/bin/sh", "-c", 'ls "$1" | grep -q secret', "brew-test", denied_dir }
        .to raise_error(ErrorDuringExecution)
    end

    it "prevents executing from a denied read hierarchy" do
      denied_dir = mktmpdir
      executable = denied_dir/"secret"
      executable.write "#!/bin/sh\nexit 0\n"
      executable.chmod 0755
      sandbox.deny_read_path denied_dir

      expect { sandbox.run "/bin/sh", "-c", 'exec "$1"', "brew-test", executable }
        .to raise_error(ErrorDuringExecution)
    end

    it "allows standard devices and shared memory" do
      expect do
        sandbox.run RUBY_PATH, "-rio/console", "-e", <<~'RUBY'
          begin
            File.open("/dev/tty", "r+") { |tty| tty.winsize }
          rescue Errno::ENXIO, Errno::ENOENT, Errno::EACCES, Errno::EPERM
            nil
          end

          if File.exist?("/dev/full")
            begin
              File.write("/dev/full", "test")
              raise "/dev/full accepted a write"
            rescue Errno::ENOSPC
              nil
            end
          end

          if Dir.exist?("/dev/shm")
            path = "/dev/shm/homebrew-landlock-#{Process.pid}"
            File.write(path, "test")
            File.unlink(path)
          end
        RUBY
      end.not_to raise_error
    end
  end
end
