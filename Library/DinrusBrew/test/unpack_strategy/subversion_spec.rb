# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Subversion, :needs_svn do
  let(:repo) { mktmpdir }
  let(:working_copy) { mktmpdir }
  let(:path) { working_copy }

  before do
    safe_system "svnadmin", "create", repo
    safe_system "svn", "checkout", "file://#{repo}", working_copy

    FileUtils.touch working_copy/"test"
    system "svn", "add", working_copy/"test"
    system "svn", "commit", working_copy, "-m", "Add `test` file."
  end

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["test"]

  context "when the directory name contains an '@' symbol" do
    let(:working_copy) { mktmpdir(["", "@1.2.3"])  }

    include_examples "#extract", children: ["test"]
  end
end
