# frozen_string_literal: true

require "cmd/info"

require "cmd/shared_examples/args_parse"

describe "brew info" do
  it_behaves_like "parseable arguments"

  it "prints as json with the --json=v1 flag", :integration_test do
    setup_test_formula "testball"

    expect { brew "info", "testball", "--json=v1" }
      .to output(a_json_string).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints as json with the --json=v2 flag", :integration_test do
    setup_test_formula "testball"

    expect { brew "info", "testball", "--json=v2" }
      .to output(a_json_string).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  describe Homebrew do
    describe "::github_remote_path" do
      let(:remote) { "https://github.com/Homebrew/homebrew-core" }

      specify "returns correct URLs" do
        expect(described_class.github_remote_path(remote, "Formula/git.rb"))
          .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/git.rb")

        expect(described_class.github_remote_path("#{remote}.git", "Formula/git.rb"))
          .to eq("https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/git.rb")

        expect(described_class.github_remote_path("git@github.com:user/repo", "foo.rb"))
          .to eq("https://github.com/user/repo/blob/HEAD/foo.rb")

        expect(described_class.github_remote_path("https://mywebsite.com", "foo/bar.rb"))
          .to eq("https://mywebsite.com/foo/bar.rb")
      end
    end
  end
end
