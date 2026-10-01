# typed: strict
# frozen_string_literal: true

require "utils/output"

module Cask
  # Helper module for reading and writing cask metadata.
  module Metadata
    extend T::Helpers
    include ::Utils::Output::Mixin

    METADATA_SUBDIR = ".metadata"
    TIMESTAMP_FORMAT = "%Y%m%d%H%M%S.%L"

    requires_ancestor { Cask }

    sig { params(caskroom_path: Pathname).returns(Pathname) }
    def metadata_main_container_path(caskroom_path: self.caskroom_path)
      caskroom_path.join(METADATA_SUBDIR)
    end

    sig { params(version: T.nilable(T.any(DSL::Version, String)), caskroom_path: Pathname).returns(Pathname) }
    def metadata_versioned_path(version: self.version, caskroom_path: self.caskroom_path)
      cask_version = (version || :unknown).to_s

      raise CaskError, "Cannot create metadata path with empty version." if cask_version.empty?

      metadata_main_container_path(caskroom_path:).join(cask_version)
    end

    sig {
      params(
        version:       T.nilable(T.any(DSL::Version, String)),
        timestamp:     T.any(Symbol, String),
        create:        T::Boolean,
        caskroom_path: Pathname,
      ).returns(T.nilable(Pathname))
    }
    def metadata_timestamped_path(version: self.version, timestamp: :latest, create: false,
                                  caskroom_path: self.caskroom_path)
      case timestamp
      when :latest
        raise CaskError, "Cannot create metadata path when timestamp is :latest." if create

        return Pathname.glob(metadata_versioned_path(version:, caskroom_path:).join("*")).max
      when :now
        timestamp = new_timestamp
      when Symbol
        raise CaskError, "Invalid timestamp symbol :#{timestamp}. Valid symbols are :latest and :now."
      end

      path = metadata_versioned_path(version:, caskroom_path:).join(timestamp)

      if create && !path.directory?
        odebug "Creating metadata directory: #{path}"
        path.mkpath
      end

      path
    end

    sig {
      params(
        leaf:          String,
        version:       T.nilable(T.any(DSL::Version, String)),
        timestamp:     T.any(Symbol, String),
        create:        T::Boolean,
        caskroom_path: Pathname,
      ).returns(T.nilable(Pathname))
    }
    def metadata_subdir(leaf, version: self.version, timestamp: :latest, create: false,
                        caskroom_path: self.caskroom_path)
      raise CaskError, "Cannot create metadata subdir when timestamp is :latest." if create && timestamp == :latest
      raise CaskError, "Cannot create metadata subdir for empty leaf." if !leaf.respond_to?(:empty?) || leaf.empty?

      parent = metadata_timestamped_path(version:, timestamp:, create:,
                                         caskroom_path:)

      return if parent.nil?

      subdir = parent.join(leaf)

      if create && !subdir.directory?
        odebug "Creating metadata subdirectory: #{subdir}"
        subdir.mkpath
      end

      subdir
    end

    private

    sig { params(time: Time).returns(String) }
    def new_timestamp(time = Time.now)
      time.utc.strftime(TIMESTAMP_FORMAT)
    end
  end
end
