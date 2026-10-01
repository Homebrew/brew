# typed: strict
# frozen_string_literal: true

require "api/cask_struct"
require "cask/cask"
require "cask/download"

module Homebrew
  module API
    module CaskDownload
      sig {
        params(
          token:       String,
          cask_struct: Homebrew::API::CaskStruct,
          languages:   T.nilable(T::Array[String]),
          require_sha: T::Boolean,
        ).returns(T.nilable(::Cask::Download))
      }
      def self.download(token:, cask_struct:, languages: nil, require_sha: false)
        languages ||= cask_struct.languages.empty? ? [] : ::Cask::Config.new.languages
        cask_struct = cask_struct.localise(languages)
        return if cask_struct.languages.any? && cask_struct.language_variations.empty?
        return if cask_struct.url_args.empty?

        cask = ::Cask::Cask.new(
          token,
          tap:                      CoreCaskTap.instance,
          loaded_from_api:          true,
          loaded_from_internal_api: true,
        ) do
          version cask_struct.version
          sha256 cask_struct.sha256
          url(*cask_struct.url_args, **cask_struct.url_kwargs)
          homepage cask_struct.homepage if cask_struct.homepage?
          if cask_struct.container?
            container(nested: cask_struct.container_args[:nested], type: cask_struct.container_args[:type])
          end
          # Staging (and the download queue's pre-staging) performs rename
          # operations through this cask, so they must be preserved here.
          cask_struct.renames.each do |from, to|
            rename from, to
          end
        end

        ::Cask::Download.new(cask, require_sha:)
      end
    end
  end
end
