# typed: strict
# frozen_string_literal: true

require "pty"
require "utils/editor"

RSpec.describe Utils::Editor do
  describe ".command" do
    it "uses the configured editor" do
      ENV["HOMEBREW_EDITOR"] = "vemate -w"

      expect(described_class.command).to eq("vemate -w")
    end
  end

  describe ".open" do
    it "runs the editor attached to the terminal" do
      ENV["HOMEBREW_EDITOR"] = "sh -c 'test -t 0 && test -t 1'"

      PTY.open do |_control, terminal|
        $stdin.reopen(terminal)
        $stdout.reopen(terminal)

        expect { described_class.open("#{TEST_TMPDIR}/testball.rb") }.not_to raise_error
      end
    end

    it "raises when the editor fails" do
      ENV["HOMEBREW_EDITOR"] = "false"

      expect { described_class.open("#{TEST_TMPDIR}/testball.rb") }.to raise_error(ErrorDuringExecution)
    end
  end
end
