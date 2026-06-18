# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/which-update"

RSpec.describe Homebrew::DevCmd::WhichUpdate do
  it_behaves_like "parseable arguments"

  it "requires --pull-request when --repository is passed" do
    mktmpdir do |path|
      database = path/"executables.txt"

      expect do
        described_class.new(["--repository=Homebrew/homebrew-core", database.to_s]).run
      end.to raise_error(Homebrew::CLI::OptionConstraintError)
    end
  end

  it "rejects repositories with extra path segments" do
    mktmpdir do |path|
      database = path/"executables.txt"

      expect(GitHub::API).not_to receive(:paginate_rest)
      expect do
        described_class.new([
          "--pull-request=123",
          "--repository=Homebrew/homebrew-core/extra",
          database.to_s,
        ]).run
      end.to raise_error(UsageError, %r{`--repository` must be in the form `owner/repo`\.})
    end
  end

  it "removes formulae from pull request files" do
    mktmpdir do |path|
      database = path/"executables.txt"
      database.write ""

      db = instance_double(Homebrew::ExecutablesDB, save!: nil)
      allow(Homebrew::ExecutablesDB).to receive(:new).with(database.to_s).and_return(db)
      expect(db).to receive(:update!).with(
        bottle_json_dir:  nil,
        removed_formulae: ["old-formula", "renamed-old"],
      )

      expect(GitHub::API).to receive(:paginate_rest) do |url, &block|
        expect(url.to_s).to end_with("/repos/Homebrew/homebrew-core/pulls/123/files")
        block.call [
          { "filename" => "Formula/new-formula.rb", "status" => "added" },
          { "filename" => "Formula/old-formula.rb", "status" => "removed" },
          {
            "filename"          => "Formula/renamed-new.rb",
            "previous_filename" => "Formula/renamed-old.rb",
            "status"            => "renamed",
          },
          { "filename" => ".github/workflows/tests.yml", "status" => "modified" },
        ]
      end

      described_class.new([
        "--pull-request=123",
        "--repository=Homebrew/homebrew-core",
        database.to_s,
      ]).run
    end
  end

  it "updates versionless formula entries from bottle JSON", :integration_test do
    mktmpdir do |path|
      database = path/"executables.txt"
      database.write <<~EOS
        bar(2.0.0):oldbar
        foo(1.0.0):foo oldfoo
        remove-me(3.0.0):remove-me
        untouched(4.0.0):untouched
      EOS

      removed_formulae = path/"removed-formulae.txt"
      removed_formulae.write "remove-me\n"

      bottle_json_dir = path/"bottle-json"
      bottle_json_dir.mkpath
      (bottle_json_dir/"invalid.bottle.json").write "{"
      (bottle_json_dir/"foo.bottle.json").write <<~JSON
        {
          "foo": {
            "formula": {
              "name": "foo"
            },
            "bottle": {
              "tags": {
                "arm64_sonoma": {
                  "path_exec_files": ["bin/foo", "sbin/food"]
                }
              }
            }
          }
        }
      JSON

      github_output = path/"github-output.txt"
      expect do
        expect do
          brew "which-update",
               "--bottle-json-dir=#{bottle_json_dir}",
               "--removed-formulae-file=#{removed_formulae}",
               database.to_s,
               "GITHUB_OUTPUT" => github_output.to_s
        end.to be_a_success
      end.to output("Removed remove-me\n").to_stdout

      expect(database.read).to eq <<~EOS
        bar:oldbar
        foo:foo food
        untouched:untouched
      EOS
      expect(github_output.read).to eq "updated=true\n"
    end
  end
end
