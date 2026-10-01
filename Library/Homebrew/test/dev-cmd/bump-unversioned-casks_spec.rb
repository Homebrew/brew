# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-unversioned-casks"

RSpec.describe Homebrew::DevCmd::BumpUnversionedCasks do
  it_behaves_like "parseable arguments"

  it "skips an unsuitable Cask", :cask, :integration_test do
    caskfile = CoreCaskTap.instance.cask_dir/"versioned-test.rb"
    caskfile.write <<~RUBY
      cask "versioned-test" do
        version "1.0"
        sha256 :no_check
        url "https://brew.sh/versioned-test-1.0.zip"
      end
    RUBY
    CoreCaskTap.instance.clear_cache

    expect { brew "bump-unversioned-casks", "--dry-run", caskfile }
      .to output(/Unversioned Casks: 1.*Checking versioned-test/m).to_stdout
      .and output(/Skipping, not a single-app or PKG cask/).to_stderr
      .and be_a_success
  end
end
