# typed: strict
# frozen_string_literal: true

require "utils/data"

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Artifact corresponding to the `generated_script` stanza.
    class GeneratedScript < AbstractArtifact
      sig {
        params(
          cask:    Cask,
          path:    T.any(String, Pathname),
          options: T.nilable(DirectivesType),
        ).returns(T.attached_class)
      }
      def self.from_args(cask, path, options = nil)
        raise CaskInvalidError.new(cask, "'generated_script' requires content") unless options.is_a?(Hash)

        ::Utils::Data.assert_valid_keys(options, :content)
        new(cask, path, content: options[:content])
      end

      sig { params(cask: Cask, path: T.any(String, Pathname), content: T.nilable(String)).void }
      def initialize(cask, path, content:)
        raise CaskInvalidError.new(cask, "'generated_script' requires content") if content.nil? || content.blank?

        super(cask)
        path = Pathname(path)
        if path.absolute? || path.each_filename.any?("..")
          raise CaskInvalidError.new(cask, "'generated_script' requires a path within the staged cask")
        end

        @path = T.let(cask.staged_path/path, Pathname)
        @path_string = T.let(path.to_s, String)
        @content = content
      end

      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        command: SystemCommand)
        @path.ascend do |path|
          break if path == cask.staged_path

          raise CaskInvalidError.new(cask, "'generated_script' path contains a symlink") if path.symlink?
        end

        @path.dirname.mkpath
        File.open(@path, File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW) do |file|
          file.write(@content)
          file.chmod(0755)
        end
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
