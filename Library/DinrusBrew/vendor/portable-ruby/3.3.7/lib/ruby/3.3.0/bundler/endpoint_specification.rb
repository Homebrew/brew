# frozen_string_literal: true

module Bundler
  # used for Creating Specifications from the Gemcutter Endpoint
  class EndpointSpecification < Gem::Specification
    include MatchRemoteMetadata

    attr_reader :name, :version, :platform, :checksum
    attr_accessor :source, :remote, :dependencies

    def initialize(name, version, platform, spec_fetcher, dependencies, metadata = nil)
      super()
      @name         = name
      @version      = Gem::Version.create version
      @platform     = Gem::Platform.new(platform)
      @spec_fetcher = spec_fetcher
      @dependencies = dependencies.map {|dep, reqs| build_dependency(dep, reqs) }

      @loaded_from          = nil
      @remote_specification = nil

      parse_metadata(metadata)
    end

    def fetch_platform
      @platform
    end

    # needed for standalone, load required_paths from local gemspec
    # after the gem is installed
    def require_paths
      if @remote_specification
        @remote_specification.require_paths
      elsif _local_specification
        _local_specification.require_paths
      else
        super
      end
    end

    # needed for inline
    def load_paths
      # remote specs aren't installed, and can't have load_paths
      if _local_specification
        _local_specification.load_paths
      else
        super
      end
    end

    # needed for binstubs
    def executables
      if @remote_specification
        @remote_specification.executables
      elsif _local_specification
        _local_specification.executables
      else
        super
      end
    end

    # needed for bundle clean
    def bindir
      if @remote_specification
        @remote_specification.bindir
      elsif _local_specification
        _local_specification.bindir
      else
        super
      end
    end

    # needed for post_install_messages during install
    def post_install_message
      if @remote_specification
        @remote_specification.post_install_message
      elsif _local_specification
        _local_specification.post_install_message
      else
        super
      end
    end

    # needed for "with native extensions" during install
    def extensions
      if @remote_specification
        @remote_specification.extensions
      elsif _local_specification
        _local_specification.extensions
      else
        super
      end
    end

    # needed for `bundle fund`
    def metadata
      if @remote_specification
        @remote_specification.metadata
      elsif _local_specification
        _local_specification.metadata
      else
        super
      end
    end

    def _local_specification
      return unless @loaded_from && File.exist?(local_specification_path)
      eval(File.read(local_specification_path), nil, local_specification_path).tap do |spec|
        spec.loaded_from = @loaded_from
      end
    end

    def __swap__(spec)
      SharedHelpers.ensure_same_dependencies(self, dependencies, spec.dependencies)
      @remote_specification = spec
    end

    private

    def _remote_specification
      @_remote_specification ||= @spec_fetcher.fetch_spec([@name, @version, @platform])
    end

    def local_specification_path
      "#{base_dir}/specifications/#{full_name}.gemspec"
    end

    def parse_metadata(data)
      unless data
        @required_ruby_version = nil
        @required_rubygems_version = nil
        return
      end

      data.each do |k, v|
        next unless v
        case k.to_s
        when "checksum"
          begin
            @checksum = Checksum.from_api(v.last, @spec_fetcher.uri)
          rescue ArgumentError => e
            raise ArgumentError, "Invalid checksum for #{full_name}: #{e.message}"
          end
        when "rubygems"
          @required_rubygems_version = Gem::Requirement.new(v)
        when "ruby"
          @required_ruby_version = Gem::Requirement.new(v)
        end
      end
    rescue StandardError => e
      raise GemspecError, "There was an error parsing the metadata for the gem #{name} (#{version}): #{e.class}\n#{e}\nThe metadata was #{data.inspect}"
    end

    def build_dependency(name, requirements)
      Gem::Dependency.new(name, requirements)
    end
  end
end
