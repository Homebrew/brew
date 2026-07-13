# typed: strict
# frozen_string_literal: true

require "cmd/--env"
require "extend/ENV/super"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Env do
  it_behaves_like "parseable arguments"

  describe "--shell=bash", :integration_test do
    it "prints the Homebrew build environment variables in Bash syntax" do
      path = [Superenv.bin&.parent, HOMEBREW_PREFIX].compact.join(File::PATH_SEPARATOR)
      expect { brew "--env", "--shell=bash" }
        .to output(/export CMAKE_PREFIX_PATH="#{Regexp.quote(path)}"/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end
end
