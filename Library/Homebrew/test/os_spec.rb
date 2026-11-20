# typed: strict
# frozen_string_literal: true

require "os"

RSpec.describe OS::ThirdPartyHomebrew do
  it "detects a configuration when its check matches" do
    mktmpdir do |dir|
      marker = dir/"wrapper"
      wrapper = described_class.new(issues_url: "https://example.com/issues", check: marker.method(:file?))
      stub_const("OS::ThirdPartyHomebrew::CONFIGURATIONS", { wrapper: })

      expect { marker.write("") }.to change(described_class, :detect).from(nil).to(wrapper)
    end
  end
end
