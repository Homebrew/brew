# typed: false
# frozen_string_literal: true

require "open3"

RSpec.describe "brew shellenv", type: :system do
  it "prints export statements", :integration_test do
    expect { brew_sh "shellenv" }
      .to output(/.*/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "outputs fpath for zsh even when PATH already contains Homebrew prefix", :integration_test do
    prefix = HOMEBREW_PREFIX.to_s
    path_with_brew = "#{prefix}/bin:#{prefix}/sbin:/usr/bin:/bin"
    expect { brew_sh "shellenv", "zsh", "PATH" => path_with_brew }
      .to output(/fpath/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "does not duplicate fpath when shellenv is evaluated twice in zsh", :integration_test do
    prefix = ENV.fetch("HOMEBREW_PREFIX")
    site_functions = "#{prefix}/share/zsh/site-functions"
    brew_sh_path = "#{prefix}/bin/brew"

    # Simulate .zprofile + .zshrc: eval shellenv twice in the same zsh session.
    # First eval sets PATH; second eval triggers the early-return path.
    # fpath should contain the Homebrew site-functions directory only once.
    Bundler.with_unbundled_env do
      stdout, _, status = Open3.capture3(
        { "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin" },
        "zsh", "-f", "-c",
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "eval \"$(#{brew_sh_path} shellenv zsh)\" && " \
        "printf '%s\\n' \"${fpath[@]}\" | grep -cxF '#{site_functions}'"
      )
      expect(status).to be_success
      expect(stdout.strip).to eq("1")
    end
  end
end
