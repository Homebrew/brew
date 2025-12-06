# frozen_string_literal: true

require "cmd/install"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::InstallCmd do
  include FileUtils

  let(:testball1_rack) { HOMEBREW_CELLAR/"testball1" }

  it_behaves_like "parseable arguments"

  it "installs a Formula from bottle", :integration_test do
    formula_name = "testball_bottle"
    formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
    formula_prefix_regex = /#{Regexp.escape(formula_prefix)}/
    option_file = formula_prefix/"foo/test"
    bottle_file = formula_prefix/"bin/helloworld"

    setup_test_formula formula_name

    expect { brew "install", formula_name }
      .to output(formula_prefix_regex).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(option_file).not_to be_a_file
    expect(bottle_file).to be_a_file

    uninstall_test_formula formula_name

    expect { brew "install", "--ask", formula_name }
      .to output(/.*Formula\s*\(1\):\s*#{formula_name}.*/).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(option_file).not_to be_a_file
    expect(bottle_file).to be_a_file

    uninstall_test_formula formula_name

    expect { brew "install", formula_name, { "HOMEBREW_FORBIDDEN_FORMULAE" => formula_name } }
      .to not_to_output(formula_prefix_regex).to_stdout
      .and output(/#{formula_name} was forbidden/).to_stderr
      .and be_a_failure
    expect(formula_prefix).not_to exist
  end

  it "installs a Formula from source", :integration_test do
    formula_name = "testball2"
    formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
    formula_prefix_regex = /#{Regexp.escape(formula_prefix)}/
    option_file = formula_prefix/"foo/test"
    always_built_file = formula_prefix/"bin/test"

    setup_test_formula formula_name

    expect { brew "install", formula_name, "--with-foo" }
      .to output(formula_prefix_regex).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(option_file).to be_a_file
    expect(always_built_file).to be_a_file

    uninstall_test_formula formula_name

    expect { brew "install", formula_name, "--debug-symbols", "--build-from-source" }
      .to output(formula_prefix_regex).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(option_file).not_to be_a_file
    expect(always_built_file).to be_a_file
    expect(formula_prefix/"bin/test.dSYM/Contents/Resources/DWARF/test").to be_a_file if OS.mac?
    expect(HOMEBREW_CACHE/"Sources/#{formula_name}").to be_a_directory
  end

  it "installs a keg-only Formula", :integration_test do
    setup_test_formula "testball1", <<~RUBY
      version "1.0"

      keg_only "test reason"
    RUBY

    expect { brew "install", "testball1" }
      .to output(%r{#{testball1_rack}/1\.0}o).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(testball1_rack/"1.0/foo/test").not_to be_a_file
  end

  it "installs a HEAD Formula", :integration_test do
    repo_path = HOMEBREW_CACHE/"repo"
    (repo_path/"bin").mkpath

    repo_path.cd do
      system "git", "-c", "init.defaultBranch=master", "init"
      system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-foo"
      FileUtils.touch "bin/something.bin"
      FileUtils.touch "README"
      system "git", "add", "--all"
      system "git", "commit", "-m", "Initial repo commit"
    end

    setup_test_formula "testball1", <<~RUBY
      version "1.0"

      head "file://#{repo_path}", :using => :git

      def install
        prefix.install Dir["*"]
      end
    RUBY

    # Ignore dependencies, because we'll try to resolve requirements in build.rb
    # and there will be the git requirement, but we cannot instantiate git
    # formula since we only have testball1 formula.
    expect { brew "install", "testball1", "--HEAD", "--ignore-dependencies", "HOMEBREW_DOWNLOAD_CONCURRENCY" => "1" }
      .to output(%r{#{testball1_rack}/HEAD-d5eb689}o).to_stdout
      .and output(/Cloning into/).to_stderr
      .and be_a_success
    expect(testball1_rack/"HEAD-d5eb689/foo/test").not_to be_a_file
  end
end
