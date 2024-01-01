# frozen_string_literal: true

require "extend/ENV"
require "requirement"

describe Requirement do
  alias_matcher :be_a_build_requirement, :be_a_build

  subject(:requirement) { klass.new }

  let(:klass) { Class.new(described_class) }

  describe "#tags" do
    subject { klass.new(tags) }

    context "with a single tag" do
      let(:tags) { ["bar"] }

      its(:tags) { are_expected.to eq(tags) }
    end

    context "with multiple tags" do
      let(:tags) { ["bar", "baz"] }

      its(:tags) { are_expected.to eq(tags) }
    end

    context "with symbol tags" do
      let(:tags) { [:build] }

      its(:tags) { are_expected.to eq(tags) }
    end

    context "with symbol and string tags" do
      let(:tags) { [:build, "bar"] }

      its(:tags) { are_expected.to eq(tags) }
    end
  end

  describe "#fatal?" do
    describe "#fatal true is specified" do
      let(:klass) do
        Class.new(described_class) do
          fatal true
        end
      end

      it { is_expected.to be_fatal }
    end

    describe "#fatal is omitted" do
      it { is_expected.not_to be_fatal }
    end
  end

  describe "#satisfied?" do
    describe "#satisfy with block and build_env returns true" do
      let(:klass) do
        Class.new(described_class) do
          satisfy(build_env: false) do
            true
          end
        end
      end

      it { is_expected.to be_satisfied }
    end

    describe "#satisfy with block and build_env returns false" do
      let(:klass) do
        Class.new(described_class) do
          satisfy(build_env: false) do
            false
          end
        end
      end

      it { is_expected.not_to be_satisfied }
    end

    describe "#satisfy returns true" do
      let(:klass) do
        Class.new(described_class) do
          satisfy true
        end
      end

      it { is_expected.to be_satisfied }
    end

    describe "#satisfy returns false" do
      let(:klass) do
        Class.new(described_class) do
          satisfy false
        end
      end

      it { is_expected.not_to be_satisfied }
    end

    describe "#satisfy with block returning true and without :build_env" do
      let(:klass) do
        Class.new(described_class) do
          satisfy do
            true
          end
        end
      end

      it "sets up build environment" do
        expect(ENV).to receive(:with_build_environment).and_call_original
        requirement.satisfied?
      end
    end

    describe "#satisfy with block returning true and :build_env set to false" do
      let(:klass) do
        Class.new(described_class) do
          satisfy(build_env: false) do
            true
          end
        end
      end

      it "skips setting up build environment" do
        expect(ENV).not_to receive(:with_build_environment)
        requirement.satisfied?
      end
    end

    describe "#satisfy with block returning path and without :build_env" do
      let(:klass) do
        Class.new(described_class) do
          satisfy do
            Pathname.new("/foo/bar/baz")
          end
        end
      end

      it "infers path from #satisfy result" do
        expect(ENV).to receive(:prepend_path).with("PATH", Pathname.new("/foo/bar"))
        requirement.satisfied?
        requirement.modify_build_environment
      end
    end
  end

  describe "#build?" do
    context "when the :build tag is specified" do
      subject { klass.new([:build]) }

      it { is_expected.to be_a_build_requirement }
    end

    describe "#build omitted" do
      it { is_expected.not_to be_a_build_requirement }
    end
  end

  describe "#name and #option_names" do
    let(:const) { :FooRequirement }
    let(:klass) { self.class.const_get(const) }

    before do
      self.class.const_set(const, Class.new(described_class))
    end

    after do
      self.class.send(:remove_const, const)
    end

    its(:name) { is_expected.to eq("foo") }
    its(:option_names) { are_expected.to eq(["foo"]) }
  end

  describe "#modify_build_environment" do
    context "without env proc" do
      let(:klass) { Class.new(described_class) }

      it "returns nil" do
        expect(requirement.modify_build_environment).to be_nil
      end
    end
  end

  describe "#eql? and #==" do
    subject(:requirement) { klass.new }

    it "returns true if the names and tags are equal" do
      other = klass.new

      expect(requirement).to eql(other)
      expect(requirement).to eq(other)
    end

    it "returns false if names differ" do
      other = klass.new
      allow(other).to receive(:name).and_return("foo")
      expect(requirement).not_to eql(other)
      expect(requirement).not_to eq(other)
    end

    it "returns false if tags differ" do
      other = klass.new([:optional])

      expect(requirement).not_to eql(other)
      expect(requirement).not_to eq(other)
    end
  end

  describe "#hash" do
    subject(:requirement) { klass.new }

    it "is equal if names and tags are equal" do
      other = klass.new
      expect(requirement.hash).to eq(other.hash)
    end

    it "differs if names differ" do
      other = klass.new
      allow(other).to receive(:name).and_return("foo")
      expect(requirement.hash).not_to eq(other.hash)
    end

    it "differs if tags differ" do
      other = klass.new([:optional])
      expect(requirement.hash).not_to eq(other.hash)
    end
  end
end
