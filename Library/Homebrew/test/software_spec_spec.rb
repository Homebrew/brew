# typed: true
# frozen_string_literal: true

require "software_spec"

RSpec.describe SoftwareSpec do
  subject(:spec) { described_class.new }

  let(:owner) { instance_double(Cask::Cask, name: "some_name", full_name: "some_name", tap: "homebrew/core") }

  alias_matcher :have_defined_resource, :be_resource_defined
  alias_matcher :have_defined_option, :be_option_defined

  describe "#resource" do
    it "defines a resource" do
      spec.resource("foo") do
        T.bind(self, Resource)
        url "foo-1.0"
      end
      expect(spec).to have_defined_resource("foo")
    end

    it "sets itself to be the resource's owner" do
      spec.resource("foo") do
        T.bind(self, Resource)
        url "foo-1.0"
      end
      spec.owner = owner
      spec.resources.each_value do |r|
        expect(r.owner).to eq(spec)
      end
    end

    it "receives the owner's version if it has no own version" do
      spec.url("foo-42")
      spec.resource("bar") do
        T.bind(self, Resource)
        url "bar"
      end
      spec.owner = owner

      expect(spec.resource("bar").version).to eq("42")
    end

    it "raises an error when duplicate resources are defined" do
      spec.resource("foo") do
        T.bind(self, Resource)
        url "foo-1.0"
      end
      expect do
        spec.resource("foo") do
          T.bind(self, Resource)
          url "foo-1.0"
        end
      end.to raise_error(DuplicateResourceError)
    end

    it "raises an error when accessing missing resources" do
      spec.owner = owner
      expect do
        spec.resource("foo")
      end.to raise_error(ResourceMissingError)
    end
  end

  describe "#owner" do
    it "sets the owner" do
      spec.owner = owner
      expect(spec.owner).to eq(owner)
    end

    it "sets the name" do
      spec.owner = owner
      expect(spec.name).to eq(owner.name)
    end
  end

  describe "#option" do
    it "defines an option" do
      spec.option("foo")
      expect(spec).to have_defined_option("foo")
    end

    it "raises an error when it begins with dashes" do
      expect do
        spec.option("--foo")
      end.to raise_error(ArgumentError)
    end

    it "raises an error when name is empty" do
      expect do
        spec.option("")
      end.to raise_error(ArgumentError)
    end

    it "supports options with descriptions" do
      spec.option("bar", "description")
      expect(spec.options.first.description).to eq("description")
    end

    it "defaults to an empty string when no description is given" do
      spec.option("foo")
      expect(spec.options.first.description).to eq("")
    end
  end

  describe "#deprecated_option" do
    it "allows specifying deprecated options" do
      spec.deprecated_option("foo" => "bar")
      expect(spec.deprecated_options).not_to be_empty
      expect(spec.deprecated_options.first.old).to eq("foo")
      expect(spec.deprecated_options.first.current).to eq("bar")
    end

    it "allows specifying deprecated options as a Hash from an Array/String to an Array/String" do
      spec.deprecated_option(["foo1", "foo2"] => "bar1", "foo3" => ["bar2", "bar3"])
      expect(spec.deprecated_options).to include(DeprecatedOption.new("foo1", "bar1"))
      expect(spec.deprecated_options).to include(DeprecatedOption.new("foo2", "bar1"))
      expect(spec.deprecated_options).to include(DeprecatedOption.new("foo3", "bar2"))
      expect(spec.deprecated_options).to include(DeprecatedOption.new("foo3", "bar3"))
    end

    it "raises an error when empty" do
      expect do
        spec.deprecated_option({})
      end.to raise_error(ArgumentError)
    end
  end

  describe "#depends_on" do
    it "allows specifying dependencies" do
      spec.depends_on("foo")
      expect(spec.deps.first.name).to eq("foo")
    end

    it "allows specifying requirements with keyword syntax" do
      spec.depends_on macos: :sonoma
      expect(spec.requirements.first).to eq(MacOSRequirement.new([:sonoma]))
    end

    it "allows specifying optional dependencies" do
      spec.depends_on "foo" => :optional
      expect(spec).to have_defined_option("with-foo")
    end

    it "allows specifying recommended dependencies" do
      spec.depends_on "bar" => :recommended
      expect(spec).to have_defined_option("without-bar")
    end
  end

  describe "#uses_from_macos" do
    context "when simulating Linux" do
      around do |example|
        Homebrew::SimulateSystem.with(os: :linux) do
          example.run
        end
      end

      it "allows specifying dependencies" do
        spec.uses_from_macos("foo")

        expect(spec.declared_deps).not_to be_empty
        expect(spec.deps).not_to be_empty
        expect(spec.deps.first.name).to eq("foo")
        expect(spec.deps.first).to be_uses_from_macos
        expect(spec.deps.first).not_to be_use_macos_install
      end

      it "works with tags" do
        spec.uses_from_macos("foo" => :build)

        expect(spec.declared_deps).not_to be_empty
        expect(spec.deps).not_to be_empty
        expect(spec.deps.first.name).to eq("foo")
        expect(spec.deps.first.tags).to include(:build)
        expect(spec.deps.first).to be_uses_from_macos
        expect(spec.deps.first).not_to be_use_macos_install
      end

      it "handles dependencies when simulating generic macOS" do
        Homebrew::SimulateSystem.with(os: :macos) do
          spec.uses_from_macos("foo")

          expect(spec.deps).to be_empty
          expect(spec.declared_deps.first.name).to eq("foo")
          expect(spec.declared_deps.first.tags).to be_empty
          expect(spec.declared_deps.first).to be_uses_from_macos
          expect(spec.declared_deps.first).to be_use_macos_install
        end
      end

      it "handles dependencies with tags when simulating generic macOS" do
        Homebrew::SimulateSystem.with(os: :macos) do
          spec.uses_from_macos("foo" => :build)

          expect(spec.deps).to be_empty
          expect(spec.declared_deps.first.name).to eq("foo")
          expect(spec.declared_deps.first.tags).to include(:build)
          expect(spec.declared_deps.first).to be_uses_from_macos
          expect(spec.declared_deps.first).to be_use_macos_install
        end
      end

      it "ignores OS version specifications" do
        spec.uses_from_macos("foo", since: :sequoia)
        spec.uses_from_macos("bar" => :build, :since => :sequoia)

        expect(spec.deps.count).to eq 2
        expect(spec.deps.first.name).to eq("foo")
        expect(spec.deps.first).to be_uses_from_macos
        expect(spec.deps.first).not_to be_use_macos_install
        expect(spec.deps.last.name).to eq("bar")
        expect(spec.deps.last.tags).to include(:build)
        expect(spec.deps.last).to be_uses_from_macos
        expect(spec.deps.last).not_to be_use_macos_install
        expect(spec.declared_deps.count).to eq 2
      end
    end

    context "when simulating Sonoma" do
      around do |example|
        Homebrew::SimulateSystem.with(os: :sonoma) do
          example.run
        end
      end

      it "adds a macOS dependency if the OS version meets requirements" do
        spec.uses_from_macos("foo", since: :sonoma)

        expect(spec.deps).to be_empty
        expect(spec.declared_deps).not_to be_empty
        expect(spec.declared_deps.first).to be_uses_from_macos
        expect(spec.declared_deps.first).to be_use_macos_install
      end

      it "adds a macOS dependency if the OS version doesn't meet requirements" do
        spec.uses_from_macos("foo", since: :sequoia)

        expect(spec.declared_deps).not_to be_empty
        expect(spec.deps).not_to be_empty
        expect(spec.deps.first.name).to eq("foo")
        expect(spec.deps.first).to be_uses_from_macos
        expect(spec.deps.first).not_to be_use_macos_install
      end

      it "works with tags" do
        spec.uses_from_macos("foo" => :build, :since => :sequoia)

        expect(spec.declared_deps).not_to be_empty
        expect(spec.deps).not_to be_empty

        dep = spec.deps.first

        expect(dep.name).to eq("foo")
        expect(dep.tags).to include(:build)
        expect(dep).to be_uses_from_macos
        expect(dep).not_to be_use_macos_install
      end

      it "doesn't add an effective dependency if no OS version is specified" do
        spec.uses_from_macos("foo")
        spec.uses_from_macos("bar" => :build)

        expect(spec.deps).to be_empty
        expect(spec.declared_deps).not_to be_empty

        dep = spec.declared_deps.first
        expect(dep.name).to eq("foo")
        expect(dep).to be_uses_from_macos
        expect(dep).to be_use_macos_install

        dep = spec.declared_deps.last
        expect(dep.name).to eq("bar")
        expect(dep.tags).to include(:build)
        expect(dep).to be_uses_from_macos
        expect(dep).to be_use_macos_install
      end

      it "treats invalid OS versions as macOS-provided dependencies" do
        spec.uses_from_macos("foo", since: :bar)

        expect(spec.deps).to be_empty
        expect(spec.declared_deps.first).to be_use_macos_install
      end
    end
  end

  specify "explicit options override defaupt depends_on option description" do
    spec.option("with-foo", "blah")
    spec.depends_on("foo" => :optional)
    expect(spec.options.first.description).to eq("blah")
  end

  describe "#patch" do
    it "adds a patch" do
      spec.patch(:p1, :DATA)
      expect(spec.patches.count).to eq(1)
      expect(spec.patches.first.strip).to eq(:p1)
    end

    it "doesn't add a patch with no url" do
      spec.patch do
        T.bind(self, Resource::Patch)
        sha256 "7852a7a365f518b12a1afd763a6a80ece88ac7aeea3c9023aa6c1fe46ac5a1ae"
      end
      expect(spec.patches.empty?).to be true
    end
  end
end
