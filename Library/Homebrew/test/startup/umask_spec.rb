# typed: strict
# frozen_string_literal: true

require "open3"

RSpec.describe "startup umask", type: :system do
  test_each([
    ["1", "staff", "staff", "000", "0022"],
    ["1", "staff", "staff", "002", "0022"],
    ["1", "staff", "staff", "007", "0027"],
    ["1", "staff", "staff", "077", "0077"],
    ["1", "staff", "staff admin", "000", "0000"],
    ["1", "brew-users", "brew-users staff", "000", "0000"],
    ["", "staff", "staff", "000", "0000"],
  ]) do |(macos, primary_group, groups, initial_umask, expected_umask)|
    it "uses #{expected_umask} for #{[macos, primary_group, groups, initial_umask]} including subprocesses" do
      directory = mktmpdir
      stdout, stderr, status = Open3.capture3(
        { "HOMEBREW_MACOS" => macos }, "/bin/bash", "-c", <<~SH, "--", directory.to_s
          umask #{initial_umask}
          source() { :; }
          id() {
            if [[ "$1" == -gn ]]; then echo '#{primary_group}'; else echo '#{groups}'; fi
          }
          #{(HOMEBREW_LIBRARY_PATH/"brew.sh").read.split("\nrealpath()", 2).first}
          umask
          /bin/bash -c 'mkdir "$1/child"; touch "$1/child/file"' -- "$1"
        SH
      )

      expect([status.exitstatus, stderr, stdout, (directory/"child").stat.mode & 0777,
              (directory/"child/file").stat.mode & 0777])
        .to eq([0, "", "#{expected_umask}\n", 0777 & ~expected_umask.to_i(8), 0666 & ~expected_umask.to_i(8)])
    end
  end
end
