# frozen_string_literal: true

require "rubocops/shell_commands"

RSpec.describe RuboCop::Cop::Homebrew::ExecShellMetacharacters do
  subject(:cop) { described_class.new }

  context "when auditing exec calls" do
    it "reports aan offense when output piping is used" do
      expect_offense(<<~RUBY)
        fork do
          exec "foo bar > output"
               ^^^^^^^^^^^^^^^^^^ Homebrew/ExecShellMetacharacters: Don't use shell metacharacters in `exec`. Implement the logic in Ruby instead, using methods like `$stdout.reopen`.
        end
      RUBY
    end

    it "reports no offenses when no metacharacters are used" do
      expect_no_offenses(<<~RUBY)
        fork do
          exec "foo bar"
        end
      RUBY
    end
  end
end
