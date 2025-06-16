# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Generic artifact corresponding to the `artifact` stanza.
    class Artifact < Moved
      sig { returns(String) }
      def self.english_name
        "Generic Artifact"
      end

      sig { params(cask: Cask, args: T.untyped).returns(T.attached_class) }
      def self.from_args(cask, *args)
        source, options = args

        raise CaskInvalidError.new(cask.token, "No source provided for #{english_name}.") if source.blank?

        unless options&.key?(:target)
          raise CaskInvalidError.new(cask.token, "#{english_name} '#{source}' requires a target.")
        end

        new(cask, source, **options)
      end

      sig { params(target: T.any(String, Pathname)).returns(Pathname) }
      def resolve_target(target)
        super(target, base_dir: nil)
      end
    end
  end
end
