# typed: false
# frozen_string_literal: true

require "cask/cask_loader"
require "cmd/update-report"

# Walks test/support/fixtures/cask/aged_caskrooms: miniature Caskrooms as
# past Homebrew versions left them, asserting the invariants aged installed
# state must keep satisfying (see the README there).
# rubocop:disable RSpec/DescribeClass
RSpec.describe "aged Caskroom fixtures", :cask do
  # rubocop:enable RSpec/DescribeClass
  def caskroom_snapshot(caskroom)
    caskroom.glob("*/.metadata/*/*/Casks").to_h do |casks_dir|
      caskfiles = casks_dir.children.sort
      cask = Cask::CaskLoader.load_from_installed_caskfile(caskfiles.fetch(0))
      [cask.token, {
        caskfiles:           caskfiles.count,
        version:             cask.version.to_s,
        artifacts:           cask.artifacts.count,
        uninstall_artifacts: cask.artifacts_list(uninstall_only: true),
      }]
    end
  end

  (TEST_FIXTURE_DIR/"cask/aged_caskrooms").children.select(&:directory?).sort.each do |era|
    it "loads the #{era.basename} era with its artifacts and migrates it losslessly" do
      caskroom = mktmpdir/"Caskroom"
      caskroom.mkpath
      FileUtils.cp_r (era/"caskroom").children, caskroom
      allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
      era.glob("api/*.json").each do |api_json|
        allow(Homebrew::API::Cask).to receive(:cask_json)
          .with(api_json.basename(".json").to_s)
          .and_return(JSON.parse(api_json.read))
      end

      before_migration = caskroom_snapshot(caskroom)
      expect do
        Homebrew::Cmd::UpdateReport.new(["--quiet"]).send(:migrate_caskroom_caskfiles_to_json)
      end.not_to output.to_stderr
      expect([
        caskroom_snapshot(caskroom),
        before_migration.values.all? { |cask| cask[:caskfiles] == 1 && cask[:artifacts].positive? },
      ]).to eq([before_migration, true])
    end
  end
end
