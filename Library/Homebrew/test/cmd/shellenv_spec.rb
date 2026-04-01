# typed: false
# frozen_string_literal: true

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
      .to output(/fpath\[1,0\]/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
