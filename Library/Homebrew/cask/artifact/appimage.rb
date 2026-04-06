# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    class AppImage < Symlinked
      sig { params(target: T.any(String, Pathname)).returns(Pathname) }
      def resolve_target(target)
        Pathname.new("#{config.appimagedir}/#{target}")
      end
    end
  end
end
