# typed: false
# frozen_string_literal: true

RSpec.describe "brew shellenv", type: :system do
  it "prints export statements", :integration_test do
    expect { brew_sh "shellenv" }
      .to output(/.*/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "sets zsh fpath idempotently at the front across repeated evals", :integration_test do
    skip "zsh is not installed." unless which("zsh")

    prefix = ENV.fetch("HOMEBREW_PREFIX")
    site_functions = "#{prefix}/share/zsh/site-functions"
    brew_sh_path = "#{prefix}/bin/brew"

    Bundler.with_unbundled_env do
      # Start with site-functions in the middle of fpath and an empty entry, then
      # eval shellenv twice. This exercises all four concerns in one session:
      #   1. fpath is emitted even on the early-return path (second eval, PATH already set)
      #   2. site-functions is moved to the front
      #   3. site-functions appears exactly once (no duplicates)
      #   4. empty fpath entries are preserved
      stdout, _, status = Open3.capture3(
        { "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin" },
        "zsh", "-f", "-c",
        "fpath=(/tmp/homebrew-shellenv-test '#{site_functions}' '' /tmp/homebrew-shellenv-test-2) && " \
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "printf '%s\\n' \"${fpath[@]}\""
      )
      expect(status).to be_success
      expect(stdout).to eq <<~EOS
        #{site_functions}
        /tmp/homebrew-shellenv-test

        /tmp/homebrew-shellenv-test-2
      EOS

      stdout, _, status = Open3.capture3(
        { "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin" },
        "zsh", "-f", "-c",
        "unset fpath && " \
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "printf '%s\\n' \"${fpath[@]}\""
      )
      expect(status).to be_success
      expect(stdout).to eq <<~EOS
        #{site_functions}
      EOS
    end
  end
end
