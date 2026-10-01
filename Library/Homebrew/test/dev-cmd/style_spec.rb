# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/style"

RSpec.describe Homebrew::DevCmd::StyleCmd do
  it_behaves_like "parseable arguments"

  test_each(%w[package/scripts/postinstall completions/bash/brew Dockerfile]) do |file|
    it "includes #{file} in changed shell files" do
      repository = mktmpdir
      stub_const("HOMEBREW_REPOSITORY", repository)
      script = repository/file
      script.dirname.mkpath
      script.write "#!/bin/bash\n"
      system "git", "-C", repository.to_s, "init", "--quiet"
      allow(Utils::Git).to receive(:changed_files).with(repository.to_s).and_return([file, "deleted.rb", "README.md"])

      Dir.chdir(repository) do
        expect(described_class.new(["--changed"]).changed_ruby_or_shell_files).to eq([script])
      end
    end
  end

  it "checks a Formula and Cask", :cask, :integration_test do
    formula_file = setup_test_formula "testball"
    HOMEBREW_LIBRARY.mkpath
    FileUtils.ln_s HOMEBREW_LIBRARY_PATH.parent/".rubocop.yml", HOMEBREW_LIBRARY/".rubocop.yml"
    FileUtils.ln_s HOMEBREW_LIBRARY_PATH, HOMEBREW_LIBRARY/"Homebrew"

    begin
      expect do
        brew "style", "--only-cops=Layout/TrailingWhitespace", formula_file, cask_path("local-caffeine")
      end.to be_a_success
    ensure
      FileUtils.rm_f HOMEBREW_LIBRARY/".rubocop.yml"
      FileUtils.rm_f HOMEBREW_LIBRARY/"Homebrew"
    end
  end
end
