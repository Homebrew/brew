# frozen_string_literal: true

require "cmd/install"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::InstallCmd do
  include FileUtils

  it_behaves_like "parseable arguments"

  context "when using a bottle" do
    let(:formula_name) { "testball_bottle" }
    let(:formula_prefix) { HOMEBREW_CELLAR/formula_name/"0.1" }
    let(:formula_prefix_regex) { /#{Regexp.escape(formula_prefix)}/o }
    let(:option_file) { formula_prefix/"foo/test" }
    let(:bottle_file) { formula_prefix/"bin/helloworld" }

    it "installs a Formula", :integration_test do
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

    it "installs a keg-only Formula", :integration_test do
      setup_test_formula formula_name, <<~RUBY
        keg_only "test reason"
      RUBY

      expect { brew "install", formula_name }
        .to output(formula_prefix_regex).to_stdout
        .and output(/✔︎.*/m).to_stderr
        .and be_a_success
      expect(option_file).not_to be_a_file
      expect(bottle_file).to be_a_file
      expect(HOMEBREW_PREFIX/"bin/helloworld").not_to be_a_file
    end
  end

  context "when building from source" do
    let(:formula_name) { "testball1" }

    it "installs a Formula", :integration_test do
      formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
      formula_prefix_regex = /#{Regexp.escape(formula_prefix)}/o
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

    it "installs a HEAD Formula", :integration_test do
      testball1_prefix = HOMEBREW_CELLAR/"testball1/HEAD-d5eb689"
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

        head "file://#{repo_path}", using: :git

        def install
          prefix.install Dir["*"]
        end
      RUBY

      expect { brew "install", formula_name, "--HEAD", "HOMEBREW_DOWNLOAD_CONCURRENCY" => "1" }
        .to output(/#{Regexp.escape(testball1_prefix)}/o).to_stdout
        .and output(/Cloning into/).to_stderr
        .and be_a_success
      expect(testball1_prefix/"foo/test").not_to be_a_file
      expect(testball1_prefix/"bin/something.bin").to be_a_file
    end
  end
end
