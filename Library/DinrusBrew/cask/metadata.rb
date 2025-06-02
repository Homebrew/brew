# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Cask
  # Helper module for reading and writing cask metadata.
  module Metadata
    extend T::Helpers

    METADATA_SUBDIR = ".metadata"
    TIMESTAMP_FORMAT = "%Y%m%d%H%M%S.%L"

    requires_ancestor { Cask }

    def metadata_main_container_path(caskroom_path: self.caskroom_path)
      caskroom_path.join(METADATA_SUBDIR)
    end

    def metadata_versioned_path(version: self.version, caskroom_path: self.caskroom_path)
      cask_version = (version || :unknown).to_s

      raise CaskError, "Cannot create metadata path with empty version." if cask_version.empty?

      metadata_main_container_path(caskroom_path:).join(cask_version)
    end

    def metadata_timestamped_path(version: self.version, timestamp: :latest, create: false,
                                  caskroom_path: self.caskroom_path)
      raise CaskError, "Cannot create metadata path when timestamp is :latest." if create && timestamp == :latest

      path = if timestamp == :latest
        Pathname.glob(metadata_versioned_path(version:, caskroom_path:).join("*")).max
      else
        timestamp = new_timestamp if timestamp == :now
        metadata_versioned_path(version:, caskroom_path:).join(timestamp)
      end

      if create && !path.directory?
        odebug "Creating metadata directory: #{path}"
        path.mkpath
      end

      path
    end

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

    def new_timestamp(time = Time.now)
      time.utc.strftime(TIMESTAMP_FORMAT)
    end
  end
end
