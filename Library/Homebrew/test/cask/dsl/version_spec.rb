# frozen_string_literal: true

RSpec.describe Cask::DSL::Version, :cask do
  shared_examples "expectations hash" do |input_name, expectations|
    expectations.each do |input_value, expected_output|
      context "when #{input_name} is #{input_value.inspect}" do
        let(input_name.to_sym) { input_value }

        it { is_expected.to eq expected_output }
      end
    end
  end

  shared_examples "version equality" do
    let(:raw_version) { "1.2.3" }

    context "when other is nil" do
      let(:other) { nil }

      it { is_expected.to be false }
    end

    context "when other is a String" do
      context "when other == self.raw_version" do
        let(:other) { "1.2.3" }

        it { is_expected.to be true }
      end

      context "when other != self.raw_version" do
        let(:other) { "1.2.3.4" }

        it { is_expected.to be false }
      end
    end

    context "when other is a #{described_class}" do
      context "when other.raw_version == self.raw_version" do
        let(:other) { described_class.new("1.2.3") }

        it { is_expected.to be true }
      end

      context "when other.raw_version != self.raw_version" do
        let(:other) { described_class.new("1.2.3.4") }

        it { is_expected.to be false }
      end
    end
  end

  let(:version) { described_class.new(raw_version) }

  describe "#initialize" do
    it "raises an error when the version contains a slash" do
      expect do
        described_class.new("0.1,../../directory/traversal")
      end.to raise_error(TypeError, %r{invalid characters: /})
    end
  end

  describe "#==" do
    subject { version == other }

    include_examples "version equality"
  end

  describe "#eql?" do
    subject { version.eql?(other) }

    include_examples "version equality"
  end

  shared_examples "version expectations hash" do |method, hash|
    subject { version.send(method) }

    include_examples "expectations hash", :raw_version,
                     { :latest  => "latest",
                       "latest" => "latest",
                       ""       => "",
                       nil      => "" }.merge(hash)
  end

  describe "#latest?" do
    include_examples "version expectations hash", :latest?,
                     :latest  => true,
                     "latest" => true,
                     ""       => false,
                     nil      => false,
                     "1.2.3"  => false
  end

  describe "string manipulation helpers" do
    describe "#major" do
      include_examples "version expectations hash", :major,
                       "1"           => "1",
                       "1.2"         => "1",
                       "1.2.3"       => "1",
                       "1.2.3-4,5:6" => "1"
    end

    describe "#minor" do
      include_examples "version expectations hash", :minor,
                       "1"           => "",
                       "1.2"         => "2",
                       "1.2.3"       => "2",
                       "1.2.3-4,5:6" => "2"
    end

    describe "#patch" do
      include_examples "version expectations hash", :patch,
                       "1"           => "",
                       "1.2"         => "",
                       "1.2.3"       => "3",
                       "1.2.3-4,5:6" => "3-4"
    end

    describe "#major_minor" do
      include_examples "version expectations hash", :major_minor,
                       "1"           => "1",
                       "1.2"         => "1.2",
                       "1.2.3"       => "1.2",
                       "1.2.3-4,5:6" => "1.2"
    end

    describe "#major_minor_patch" do
      include_examples "version expectations hash", :major_minor_patch,
                       "1"           => "1",
                       "1.2"         => "1.2",
                       "1.2.3"       => "1.2.3",
                       "1.2.3-4,5:6" => "1.2.3-4"
    end

    describe "#minor_patch" do
      include_examples "version expectations hash", :minor_patch,
                       "1"           => "",
                       "1.2"         => "2",
                       "1.2.3"       => "2.3",
                       "1.2.3-4,5:6" => "2.3-4"
    end

    describe "#csv" do
      subject { version.csv }

      include_examples "expectations hash", :raw_version,
                       :latest     => ["latest"],
                       "latest"    => ["latest"],
                       ""          => [],
                       nil         => [],
                       "1.2.3"     => ["1.2.3"],
                       "1.2.3,"    => ["1.2.3"],
                       ",abc"      => ["", "abc"],
                       "1.2.3,abc" => ["1.2.3", "abc"]
    end

    describe "#before_comma" do
      include_examples "version expectations hash", :before_comma,
                       "1.2.3"     => "1.2.3",
                       "1.2.3,"    => "1.2.3",
                       ",abc"      => "",
                       "1.2.3,abc" => "1.2.3"
    end

    describe "#after_comma" do
      include_examples "version expectations hash", :after_comma,
                       "1.2.3"     => "",
                       "1.2.3,"    => "",
                       ",abc"      => "abc",
                       "1.2.3,abc" => "abc"
    end

    describe "#dots_to_hyphens" do
      include_examples "version expectations hash", :dots_to_hyphens,
                       "1.2.3_4-5" => "1-2-3_4-5"
    end

    describe "#dots_to_underscores" do
      include_examples "version expectations hash", :dots_to_underscores,
                       "1.2.3_4-5" => "1_2_3_4-5"
    end

    describe "#hyphens_to_dots" do
      include_examples "version expectations hash", :hyphens_to_dots,
                       "1.2.3_4-5" => "1.2.3_4.5"
    end

    describe "#hyphens_to_underscores" do
      include_examples "version expectations hash", :hyphens_to_underscores,
                       "1.2.3_4-5" => "1.2.3_4_5"
    end

    describe "#underscores_to_dots" do
      include_examples "version expectations hash", :underscores_to_dots,
                       "1.2.3_4-5" => "1.2.3.4-5"
    end

    describe "#underscores_to_hyphens" do
      include_examples "version expectations hash", :underscores_to_hyphens,
                       "1.2.3_4-5" => "1.2.3-4-5"
    end

    describe "#no_dots" do
      include_examples "version expectations hash", :no_dots,
                       "1.2.3_4-5" => "123_4-5"
    end

    describe "#no_hyphens" do
      include_examples "version expectations hash", :no_hyphens,
                       "1.2.3_4-5" => "1.2.3_45"
    end

    describe "#no_underscores" do
      include_examples "version expectations hash", :no_underscores,
                       "1.2.3_4-5" => "1.2.34-5"
    end

    describe "#no_dividers" do
      include_examples "version expectations hash", :no_dividers,
                       "1.2.3_4-5" => "12345"
    end
  end

  describe "#unstable?" do
    [
      "0.0.11-beta.7",
      "0.0.23b-alpha",
      "0.1-beta",
      "0.1.0-beta.6",
      "0.10.0b",
      "0.2.0-alpha",
      "0.2.0-beta",
      "0.2.4-beta.9",
      "0.2.588-dev",
      "0.3-beta",
      "0.3.0-SNAPSHOT-624369f",
      "0.4.1-alpha",
      "0.4.9-alpha",
      "0.5.3,beta",
      "0.6-alpha1,a",
      "0.7.1b2",
      "0.7a19",
      "0.8.0b8",
      "0.8b3",
      "0.9.10-alpha",
      "0.9.3b",
      "08b2",
      "1.0-b9",
      "1.0-beta",
      "1.0-beta-7.0",
      "1.0-beta.3",
      "1.0.0-alpha.5",
      "1.0.0-alpha5",
      "1.0.0-beta-2.2,20160421",
      "1.0.0-beta.16",
      "1.0.0-rc",
      "1.0.6b1",
      "1.0.beta-43",
      "1.004,alpha",
      "1.0b10",
      "1.0b12",
      "1.1-alpha-20181201a",
      "1.1.16-beta-rc2",
      "1.1.58.BETA",
      "1.10.1,b87:8941241e",
      "1.13.0-beta.7",
      "1.13beta8",
      "1.15.0.b20190302001",
      "1.16.2-Beta",
      "1.1b23",
      "1.2.0,b200",
      "1.2.1pre1",
      "1.2.2-beta.2845",
      "1.20.0-beta.3",
      "1.2b24",
      "1.3.0,b102",
      "1.3.7a",
      "1.36.0-beta0",
      "1.4.3a",
      "1.6.0_65-b14-468",
      "1.6.4-beta0-4e46f007",
      "1.7,b566",
      "1.7b5",
      "1.9.3a",
      "1.9.3b8",
      "17.03.1-beta",
      "18.0-Leia_rc4",
      "18.2-rc-3",
      "1875Beta",
      "19.3.2,b4188-155116",
      "2.0-rc.22",
      "2.0.0-beta.2",
      "2.0.0-beta14",
      "2.0.0-dev.11,1902221558.a6b3c4a8",
      "2.0.12,b1807-50472cde",
      "2.0b",
      "2.0b2",
      "2.0b3-2020",
      "2.0b5",
      "2.1.1-dev.3",
      "2.12.12beta3",
      "2.12b1",
      "2.2-Beta",
      "2.2.0-RC1",
      "2.2b2",
      "2.3.0-beta1u1",
      "2.3.1,rc4",
      "2.3b19",
      "2.4.0-beta2",
      "2.4.6-beta3u2",
      "2.6.1-dev_2019-02-09_14-04_git-master-c1f194a",
      "2.7.4a1",
      "2.79b",
      "2.99pre5",
      "2019.1-Beta2",
      "2019.1-b112",
      "2019.1-beta1",
      "2019a",
      "26.1-rc1-1",
      "3.0.0-beta.5",
      "3.0.0-beta19",
      "3.0.0-canary.8",
      "3.0.0-preview-27122-01",
      "3.0.0-rc.14",
      "3.0.1-beta.19",
      "3.0.100-preview-010184",
      "3.0.6a",
      "3.00b5",
      "3.1.0-beta.1",
      "3.1.0_b15007",
      "3.2.8beta1",
      "3.21-beta",
      "3.7.9beta03,5210",
      "3b19",
      "4.0.0a",
      "4.2.0-preview",
      "4.3-beta5",
      "4.3b3",
      "4.99beta",
      "5.0.0-RC7",
      "5.5.0-beta-9",
      "6.0.0-beta3,20181228T124823",
      "6.0.0_BETA3,127054",
      "6.1.1b176",
      "6.2.0-preview.4",
      "6.2.0.0.beta1",
      "6.3.9_b16229",
      "6.44b",
      "7.0.6-7A69",
      "7.3.BETA-3",
      "8.5a8",
      "8u202,b08:1961070e4c9b4e26a04e7f5a083f551e",
    ].each do |unstable_version|
      it "detects #{unstable_version.inspect} as unstable" do
        expect(described_class.new(unstable_version)).to be_unstable
      end
    end

    [
      "0.20.1,63d9b84e-bbcf-4a00-9427-0bb3f713c769",
      "1.5.4,13:53d8a307-a8ae-4f9b-9a59-a1adb8c67012",
      "b226",
    ].each do |stable_version|
      it "does not detect #{stable_version.inspect} as unstable" do
        expect(described_class.new(stable_version)).not_to be_unstable
      end
    end
  end
end
