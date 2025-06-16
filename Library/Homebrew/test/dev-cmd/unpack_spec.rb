# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/unpack"

RSpec.describe Homebrew::DevCmd::Unpack do
  it_behaves_like "parseable arguments"

  it "unpacks a given Formula's archive", :integration_test do
    setup_test_formula "testball"

    mktmpdir do |path|
      expect { brew "unpack", "testball", "--destdir=#{path}" }
        .to be_a_success

      expect(path/"testball-0.1").to be_a_directory
    end
  end
end
