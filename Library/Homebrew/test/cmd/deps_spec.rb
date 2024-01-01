# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew deps" do
  it_behaves_like "parseable arguments"

  it "outputs all of a Formula's dependencies and their dependencies on separate lines", :integration_test do
    # Included in output
    setup_test_formula "bar"
    setup_test_formula "foo"
    setup_test_formula "test"

    # Excluded from output
    setup_test_formula "baz", <<~RUBY
      url "https://brew.sh/baz-1.0"
      depends_on "bar"
      depends_on "build" => :build
      depends_on "test" => :test
      depends_on "optional" => :optional
      depends_on "recommended_test" => [:recommended, :test]
      depends_on "installed"
    RUBY
    setup_test_formula "build"
    setup_test_formula "optional"
    setup_test_formula "recommended_test"
    setup_test_formula "installed"

    # Mock `Formula#any_version_installed?` by creating the tab in a plausible keg directory
    keg_dir = HOMEBREW_CELLAR/"installed"/"1.0"
    keg_dir.mkpath
    touch keg_dir/Tab::FILENAME

    expect { brew "deps", "baz", "--include-test", "--missing", "--skip-recommended" }
      .to be_a_success
      .and output("bar\nfoo\ntest\n").to_stdout
      .and not_to_output.to_stderr
  end
end
