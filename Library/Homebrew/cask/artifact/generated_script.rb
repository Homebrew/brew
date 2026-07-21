# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Artifact corresponding to the `generated_script` stanza.
    class GeneratedScript < AbstractArtifact
      sig {
        params(
          cask:    Cask,
          path:    T.any(String, Pathname),
          options: T.untyped,
        ).returns(T.attached_class)
      }
      def self.from_args(cask, path, options = nil)
        options ||= {}
        options.assert_valid_keys(:content)
        new(cask, path, **options)
      end

      sig { params(cask: Cask, path: T.any(String, Pathname), content: String).void }
      def initialize(cask, path, content:)
        raise CaskInvalidError.new(cask, "'generated_script' requires content") if content.blank?

        super(cask)
        path = Pathname(path)
        if path.absolute? || path.each_filename.any?("..")
          raise CaskInvalidError.new(cask, "'generated_script' requires a path within the staged cask")
        end

        @path = T.let(cask.staged_path/path, Pathname)
        @path_string = T.let(path.to_s, String)
        @content = content
      end

      sig { params(_options: T.anything).void }
      def install_phase(**_options)
        @path.dirname.mkpath
        @path.write(@content)
        @path.chmod(0755)
      end

      sig { override.returns(T::Array[T.anything]) }
      def to_args
        [@path_string, { content: @content }]
      end

      sig { override.returns(String) }
      def summarize = @path_string
    end
  end
end
