# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/upgrade"

RSpec.describe Homebrew::Cmd::UpgradeCmd do
  include FileUtils
  it_behaves_like "parseable arguments"

  it "upgrades a Formula and cleans up old versions", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball/0.0.1").not_to exist
  end

  it "upgrades with asking for user prompts", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect do
      brew "upgrade", "--ask"
    end.to output(/.*Formula\s*\(1\):\s*testball.*/).to_stdout.and not_to_output.to_stderr

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball/0.0.1").not_to exist
  end

  it "upgrades dependencies with asking for user prompts", :integration_test do
    setup_test_formula "testball", <<~RUBY
      depends_on "testball5"
      # should work as its not building but test doesnt pass if dependant
      depends_on "testball-build" => :build
      depends_on "installed"
    RUBY
    setup_test_formula "installed"
    setup_test_formula "testball5", <<~RUBY
      depends_on "testball4"
    RUBY
    setup_test_formula "testball4"
    setup_test_formula "hiop"
    setup_test_formula "testball-build"

    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath
    (HOMEBREW_CELLAR/"testball5/0.0.1/foo").mkpath
    (HOMEBREW_CELLAR/"testball4/0.0.1/foo").mkpath

    keg_dir = HOMEBREW_CELLAR/"installed"/"1.0"
    keg_dir.mkpath
    touch keg_dir/AbstractTab::FILENAME

    regex = /
      Formulae\s*\(3\):\s*
      (testball|testball5|testball4)
      \s*,\s*
      ((?!\1)testball|testball5|testball4)
      \s*,\s*
      ((?!\1|\2)testball|testball5|testball4)
    /x
    expect do
      brew "upgrade", "--ask"
    end.to output(regex)
      .to_stdout.and not_to_output.to_stderr

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball/0.0.1").not_to exist
    expect(HOMEBREW_CELLAR/"testball5/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball5/0.0.1").not_to exist
    expect(HOMEBREW_CELLAR/"testball4/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball4/0.0.1").not_to exist
  end

  it "upgrades only the ‘testball’ formula, prompts for dependent checks, and verifies that other fields are updated",
     :integration_test do
    content = <<~RUBY
      version "0.1"
      depends_on "testball-parent"
    RUBY
    setup_test_formula "testball-parent-parent", content, testball_bottle: true
    content = <<~RUBY
      version "0.1"
      depends_on "testball"
    RUBY
    setup_test_formula "testball-parent", content, testball_bottle: true

    content = <<~RUBY
      depends_on "testball5"
      # should work as it's not building but test doesn't pass if dependant
      # depends_on "build" => :build
      depends_on "installed"
      version "0.1"
    RUBY
    setup_test_formula "testball", content, testball_bottle: true
    setup_test_formula "installed"

    content = <<~RUBY
      version "0.1"
      depends_on "testball4"
    RUBY
    setup_test_formula "testball5", content, testball_bottle: true
    content = <<~RUBY
      version "0.1"
    RUBY
    setup_test_formula "testball4", content, testball_bottle: true
    setup_test_formula "hiop"
    setup_test_formula "build"

    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath
    (HOMEBREW_CELLAR/"testball5/0.0.1/foo").mkpath
    (HOMEBREW_CELLAR/"testball4/0.0.1/foo").mkpath
    (HOMEBREW_CELLAR/"testball-parent/0.0.1/foo").mkpath
    (HOMEBREW_CELLAR/"testball-parent-parent/0.0.1/foo").mkpath

    keg_dir = HOMEBREW_CELLAR/"installed"/"1.0"
    keg_dir.mkpath
    touch keg_dir/AbstractTab::FILENAME

    regex = /
      Formulae\s*\(5\):\s*
      (testball|testball5|testball4|testball-parent|testball-parent-parent)
      \s*,\s*
      ((?!\1)testball|testball5|testball4|testball-parent|testball-parent-parent)
      \s*,\s*
      ((?!\1|\2)testball|testball5|testball4|testball-parent|testball-parent-parent)
      \s*,\s*
      ((?!\1|\2|\3)testball|testball5|testball4|testball-parent|testball-parent-parent)
      \s*,\s*
      ((?!\1|\2|\3|\4)testball|testball5|testball4|testball-parent|testball-parent-parent)
    /x
    expect do
      brew "upgrade", "--ask", "testball"
    end.to output(regex)
      .to_stdout.and not_to_output.to_stderr

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball/0.0.1").not_to exist
    expect(HOMEBREW_CELLAR/"testball5/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball4/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball-parent/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball-parent/0.0.1").not_to exist
    expect(HOMEBREW_CELLAR/"testball-parent-parent/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball-parent-parent/0.0.1").not_to exist

    # Those directories shouldn't exist anymore
    # brew upgrade testball remove testball directory but not the following one
    # Cleanup isn't applied on the dependencies
    # expect(HOMEBREW_CELLAR/"testball5/0.0.1").not_to exist
    # expect(HOMEBREW_CELLAR/"testball4/0.0.1").not_to exist
  end
end
