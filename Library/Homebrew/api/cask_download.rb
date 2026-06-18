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
          quarantine:  T.nilable(T::Boolean),
          require_sha: T::Boolean,
        ).returns(T.nilable(::Cask::Download))
      }
      def self.download(token:, cask_struct:, quarantine: nil, require_sha: false)
        return if cask_struct.languages.any?
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
        end

        ::Cask::Download.new(cask, quarantine:, require_sha:)
      end
    end
  end
end
