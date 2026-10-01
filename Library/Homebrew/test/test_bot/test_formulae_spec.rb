# typed: true
# frozen_string_literal: true

require "test_bot"
require "utils/github/artifacts"

RSpec.describe Homebrew::TestBot::TestFormulae do
  subject(:test_formulae) do
    Class.new(described_class) do
      T.bind(self, T.class_of(Homebrew::TestBot::TestFormulae))
      public :bottled_or_built?
    end.new(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
  end

  describe "#bottled_or_built?" do
    let(:dependent) do
      formula("dependent") do
        T.bind(self, T.class_of(Formula))
        url "dependent-1.0"
        depends_on "dependency"
        bottle do
          sha256 cellar: :any_skip_relocation, Utils::Bottles.tag.to_sym => TEST_SHA256
        end
      end
    end
    let(:dependency) do
      formula("dependency") do
        T.bind(self, T.class_of(Formula))
        url "dependency-1.0"
        depends_on "unbottled"
        depends_on "build-only" => :build
        depends_on "test-only" => :test
        depends_on "optional" => :optional
        bottle do
          sha256 cellar: :any_skip_relocation, Utils::Bottles.tag.to_sym => TEST_SHA256
        end
      end
    end
    let(:unbottled) do
      formula("unbottled") do
        T.bind(self, T.class_of(Formula))
        url "unbottled-1.0"
      end
    end

    before do
      [dependent, dependency, unbottled].each { |f| stub_formula_loader f }
    end

    it "rejects a bottled formula with an unbottled recursive runtime dependency" do
      expect(test_formulae.bottled_or_built?(dependent, [])).to be(false)
    end

    it "rejects a built formula with an unbottled recursive runtime dependency" do
      allow(dependent).to receive(:bottle_specification).and_return(BottleSpecification.new)

      expect(test_formulae.bottled_or_built?(dependent, [dependent.full_name])).to be(false)
    end

    it "accepts a recursive runtime dependency built in this run" do
      expect(test_formulae.bottled_or_built?(dependent, [unbottled.full_name])).to be(true)
    end

    context "with an older compatible bottle for a recursive runtime dependency" do
      before do
        allow(unbottled.bottle_specification).to receive(:tag?).and_return(false)
        allow(unbottled.bottle_specification).to receive(:tag?)
          .with(Utils::Bottles.tag, no_older_versions: false).and_return(true)
      end

      it "rejects older bottles when requested" do
        expect(test_formulae.bottled_or_built?(dependent, [], no_older_versions: true)).to be(false)
      end

      it "accepts older compatible bottles" do
        expect(test_formulae.bottled_or_built?(dependent, [])).to be(true)
      end
    end
  end

  describe "#cleanup_package_manager_caches" do
    it "removes caches that do not verify their contents but keeps content-addressed ones" do
      read_only = HOMEBREW_CACHE/"go_mod_cache/read-only"
      read_only.mkpath
      read_only.chmod(0555)
      (HOMEBREW_CACHE/"npm_cache").mkpath

      with_env(HOMEBREW_GITHUB_ACTIONS: "1") do
        test_formulae.cleanup_package_manager_caches
      end

      expect(HOMEBREW_CACHE/"go_mod_cache").not_to exist
      expect(HOMEBREW_CACHE/"npm_cache").to exist
    end
  end

  describe "#artifact_cache_valid?" do
    it "rejects a bottle when a local patch has changed" do
      Dir.mktmpdir do |tmpdir|
        repository = Pathname(tmpdir)
        formula_path = repository/"foo.rb"
        patch_path = repository/"patches/foo.diff"
        patch_path.dirname.mkpath
        formula_path.write "formula\n"
        patch_path.write "old patch\n"
        system "git", "-C", repository.to_s, "init", "--quiet"
        system "git", "-C", repository.to_s, "add", "."
        system "git", "-C", repository.to_s, "commit", "--quiet", "-m", "initial"
        revision = Utils.safe_popen_read("git", "-C", repository, "rev-parse", "HEAD").chomp
        patch_path.write "new patch\n"

        f = formula("foo", path: formula_path) do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          patch do
            file "patches/foo.diff"
          end
        end
        test_formulae = Class.new(described_class) do
          T.bind(self, T.class_of(Homebrew::TestBot::TestFormulae))
          public :artifact_cache_valid?
        end.new(
          tap: instance_double(Tap, path: repository), git: "git", dry_run: true, fail_fast: false, verbose: false,
        )
        allow(test_formulae).to receive(:local_bottle_hash).and_return(
          "foo" => { "formula" => { "tap_git_revision" => revision } },
        )

        expect(test_formulae.artifact_cache_valid?(f)).to be(false)
      end
    end
  end

  describe "#download_artifacts_from_previous_run!" do
    it "does not raise KeyError when accessing downloaded_artifacts for a new SHA" do
      # Regression test: @downloaded_artifacts uses a hash with a default block, so we must use
      # [] (not .fetch) when accessing by SHA. Using .fetch(sha) would raise KeyError for new SHAs.
      new_sha = "8e624f21ac73d02a609cfec1ce620ccfee3aa97c"
      allow(GitHub).to receive(:pull_request_labels).with("owner", "repo", 1).and_return([])
      allow(GitHub::API).to receive_messages(credentials_type: :pat, open_graphql: { "repository" => {
        "object" => {
          "checkSuites" => {
            "nodes" => [
              {
                "status"      => "COMPLETED",
                "updatedAt"   => "2024-01-01T00:00:00Z",
                "workflowRun" => { "databaseId" => 1, "event" => "pull_request", "workflow" => { "name" => "CI" } },
                "checkRuns"   => { "nodes" => [{ "name" => "conclusion", "status" => "COMPLETED" }] },
              },
            ],
          },
        },
      } })
      allow(test_formulae).to receive_messages(
        previous_github_sha:  new_sha,
        github_event_payload: { "pull_request" => { "number" => 1 } },
        artifact_metadata:    [
          {
            "name"                 => "bottles",
            "archive_download_url" => "https://example.com/artifact",
            "id"                   => 1,
          },
        ],
      )
      allow(GitHub).to receive(:download_artifact)

      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) do
          with_env("GITHUB_REPOSITORY" => "owner/repo") do
            test_formulae.download_artifacts_from_previous_run!("bottles*", dry_run: false)
          end
        end
      end

      # Proves we passed the @downloaded_artifacts[sha] access for a new SHA without KeyError.
      expect(test_formulae.downloaded_artifacts[new_sha]).to include("bottles")
    end
  end
end
