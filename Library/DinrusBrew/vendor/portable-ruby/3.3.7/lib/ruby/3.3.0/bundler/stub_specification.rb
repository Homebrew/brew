# frozen_string_literal: true

module Bundler
  class StubSpecification < RemoteSpecification
    def self.from_stub(stub)
      return stub if stub.is_a?(Bundler::StubSpecification)
      spec = new(stub.name, stub.version, stub.platform, nil)
      spec.stub = stub
      spec
    end

    attr_reader :checksum
    attr_accessor :stub, :ignored

    def source=(source)
      super
      # Stub has no concept of source, which means that extension_dir may be wrong
      # This is the case for git-based gems. So, instead manually assign the extension dir
      return unless source.respond_to?(:extension_dir_name)
      unique_extension_dir = [source.extension_dir_name, File.basename(full_gem_path)].uniq.join("-")
      path = File.join(stub.extensions_dir, unique_extension_dir)
      stub.extension_dir = File.expand_path(path)
    end

    def to_yaml
      _remote_specification.to_yaml
    end

    # @!group Stub Delegates

    def ignored?
      return @ignored unless @ignored.nil?

      @ignored = missing_extensions?
      return false unless @ignored

      warn "Source #{source} is ignoring #{self} because it is missing extensions"

      true
    end

    def manually_installed?
      # This is for manually installed gems which are gems that were fixed in place after a
      # failed installation. Once the issue was resolved, the user then manually created
      # the gem specification using the instructions provided by `gem help install`
      installed_by_version == Gem::Version.new(0)
    end

    # This is defined directly to avoid having to loading the full spec
    def missing_extensions?
      return false if default_gem?
      return false if extensions.empty?
      return false if File.exist? gem_build_complete_path
      return false if manually_installed?

      true
    end

    def activated?
      stub.activated?
    end

    def activated=(activated)
      stub.instance_variable_set(:@activated, activated)
    end

    def extensions
      stub.extensions
    end

    def gem_build_complete_path
      stub.gem_build_complete_path
    end

    def default_gem?
      stub.default_gem?
    end

    def full_gem_path
      stub.full_gem_path
    end

    def full_gem_path=(path)
      stub.full_gem_path = path
    end

    def full_require_paths
      stub.full_require_paths
    end

    def require_paths
      stub.require_paths
    end

    def base_dir=(path)
      stub.base_dir = path
    end

    def load_paths
      full_require_paths
    end

    def loaded_from
      stub.loaded_from
    end

    def matches_for_glob(glob)
      stub.matches_for_glob(glob)
    end

    def raw_require_paths
      stub.raw_require_paths
    end

    private

    def _remote_specification
      @_remote_specification ||= begin
        rs = stub.to_spec
        if rs.equal?(self) # happens when to_spec gets the spec from Gem.loaded_specs
          rs = Gem::Specification.load(loaded_from)
          Bundler.rubygems.stub_set_spec(stub, rs)
        end

        unless rs
          raise GemspecError, "The gemspec for #{full_name} at #{loaded_from}" \
            " was missing or broken. Try running `gem pristine #{name} -v #{version}`" \
            " to fix the cached spec."
        end

        rs.source = source
        rs.base_dir = stub.base_dir

        rs
      end
    end
  end
end
