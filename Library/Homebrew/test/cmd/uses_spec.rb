# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew uses" do
  it_behaves_like "parseable arguments"

  it "prints the Formulae a given Formula is used by", :integration_test do
    # Included in output
    setup_test_formula "bar"
    setup_test_formula "optional", <<~RUBY
      url "https://brew.sh/optional-1.0"
      depends_on "bar" => :optional
    RUBY

    # Excluded from output
    setup_test_formula "foo"
    setup_test_formula "test", <<~RUBY
      url "https://brew.sh/test-1.0"
      depends_on "foo" => :test
    RUBY
    setup_test_formula "build", <<~RUBY
      url "https://brew.sh/build-1.0"
      depends_on "foo" => :build
    RUBY
    setup_test_formula "installed", <<~RUBY
      url "https://brew.sh/installed-1.0"
      depends_on "foo"
    RUBY

    # Mock `Formula#any_version_installed?` by creating the tab in a plausible keg directory
    %w[foo installed].each do |formula_name|
      keg_dir = HOMEBREW_CELLAR/formula_name/"1.0"
      keg_dir.mkpath
      touch keg_dir/Tab::FILENAME
    end

    expect { brew "uses", "foo", "--eval-all", "--include-optional", "--missing", "--recursive" }
      .to output(/^(bar\noptional|optional\nbar)$/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
