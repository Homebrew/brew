# frozen_string_literal: true

require "utils/shared_audits"

RSpec.describe SharedAudits do
  describe "::github_tag_from_url" do
    it "finds tags in archive urls" do
      url = "https://github.com/a/b/archive/refs/tags/v1.2.3.tar.gz"
      expect(described_class.github_tag_from_url(url)).to eq("v1.2.3")
    end

    it "finds tags in release urls" do
      url = "https://github.com/a/b/releases/download/1.2.3/b-1.2.3.tar.bz2"
      expect(described_class.github_tag_from_url(url)).to eq("1.2.3")
    end

    it "finds tags with slashes" do
      url = "https://github.com/a/b/archive/refs/tags/c/d/e/f/g-v1.2.3.tar.gz"
      expect(described_class.github_tag_from_url(url)).to eq("c/d/e/f/g-v1.2.3")
    end

    it "finds tags in orgs/repos with special characters" do
      url = "https://github.com/a-b/c-d_e.f/archive/refs/tags/2.5.tar.gz"
      expect(described_class.github_tag_from_url(url)).to eq("2.5")
    end
  end

  describe "::gitlab_tag_from_url" do
    it "doesn't find tags in invalid urls" do
      url = "https://gitlab.com/a/-/archive/v1.2.3/a-v1.2.3.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to be_nil
    end

    it "finds tags in basic urls" do
      url = "https://gitlab.com/a/b/-/archive/v1.2.3/b-1.2.3.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to eq("v1.2.3")
    end

    it "finds tags in urls with subgroups" do
      url = "https://gitlab.com/a/b/c/d/e/f/g/-/archive/2.5/g-2.5.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to eq("2.5")
    end

    it "finds tags in urls with special characters" do
      url = "https://gitlab.com/a.b/c-d_e/-/archive/2.5/c-d_e-2.5.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to eq("2.5")
    end
  end
end
