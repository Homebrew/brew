# typed: true
# frozen_string_literal: true

require "utils/vendor_version_check"

RSpec.describe Utils::VendorVersionCheck do
  let(:gem_setup_source) do
    <<~RUBY
      module Utils
        module GemSetup
          JSON_NATIVE_EXTENSIONS = %w[json/ext/generator json/ext/parser].freeze
          VENDOR_VERSION = 9

          def self.gem_integrity_check_required?
            true
          end
        end
      end
    RUBY
  end

  it "ignores comments and formatting in integrity rules" do
    updated_source = gem_setup_source.sub(
      "    JSON_NATIVE_EXTENSIONS =",
      "    # Native JSON extensions\n    JSON_NATIVE_EXTENSIONS =",
    ).sub("      true", "        true")

    expect(described_class.integrity_rules_changed?(base_source:    gem_setup_source,
                                                    current_source: updated_source)).to be(false)
  end

  it "detects changes to the gem integrity check" do
    updated_source = gem_setup_source.sub("      true", "      false")

    expect(described_class.integrity_rules_changed?(base_source:    gem_setup_source,
                                                    current_source: updated_source)).to be(true)
  end

  it "detects changes to native JSON extensions" do
    updated_source = gem_setup_source.sub("json/ext/generator", "json/ext/encoder")

    expect(described_class.integrity_rules_changed?(base_source:    gem_setup_source,
                                                    current_source: updated_source)).to be(true)
  end

  it "requires a version bump for integrity rule changes" do
    updated_source = gem_setup_source.sub("      true", "      false")

    expect(described_class.vendor_version_bumped_for_integrity_changes?(base_source:    gem_setup_source,
                                                                        current_source: updated_source))
      .to be(false)
  end

  it "accepts a version bump for integrity rule changes" do
    updated_source = gem_setup_source.sub("VENDOR_VERSION = 9", "VENDOR_VERSION = 10")
                                     .sub("      true", "      false")

    expect(described_class.vendor_version_bumped_for_integrity_changes?(base_source:    gem_setup_source,
                                                                        current_source: updated_source))
      .to be(true)
  end
end
