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
    prefix = ENV.fetch("HOMEBREW_PREFIX")
    site_functions = "#{prefix}/share/zsh/site-functions"
    brew_sh_path = "#{prefix}/bin/brew"

    # Start with site-functions in the middle of fpath, then eval shellenv twice.
    # This exercises all three concerns in one session:
    #   1. fpath is emitted even on the early-return path (second eval, PATH already set)
    #   2. site-functions is moved to the front
    #   3. site-functions appears exactly once (no duplicates)
    Bundler.with_unbundled_env do
      stdout, _, status = Open3.capture3(
        { "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin" },
        "zsh", "-f", "-c",
        "fpath=(/tmp/homebrew-shellenv-test '#{site_functions}' /tmp/homebrew-shellenv-test-2) && " \
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "[[ \"${fpath[1]}\" = '#{site_functions}' ]] && " \
        "printf '%s\\n' \"${fpath[@]}\" | grep -cxF '#{site_functions}'"
      )
      expect(status).to be_success
      expect(stdout.strip).to eq("1")
    end
  end
end
