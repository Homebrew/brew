# typed: strict
# frozen_string_literal: true

require "utils/data"

require "cask/artifact/binary"
require "extend/pathname"
require "shellwords"

module Cask
  module Artifact
    # Artifact corresponding to the `command_wrapper` stanza.
    class CommandWrapper < Binary
      Arguments = T.type_alias { T.any(String, Pathname, T::Array[T.any(String, Pathname)]) }
      Environment = T.type_alias { T::Hash[T.any(String, Symbol), T.any(String, Pathname)] }

      sig { override.returns(Symbol) }
      def self.dirmethod = :binarydir

      sig {
        override.params(
          cask:    Cask,
          name:    T.any(String, Pathname),
          options: T.nilable(DirectivesType),
        ).returns(T.attached_class)
      }
      def self.from_args(cask, name, options = nil)
        options = {} if options.nil?
        raise CaskInvalidError.new(cask, "'command_wrapper' requires a hash of options") unless options.is_a?(Hash)

        ::Utils::Data.assert_valid_keys(options, :content, :executable, :args, :env)

        new(
          cask,
          name,
          content:    options[:content],
          executable: options[:executable],
          args:       options.fetch(:args, []),
          env:        options.fetch(:env, {}),
        )
      end

      sig {
        params(
          cask:       Cask,
          name:       T.any(String, Pathname),
          content:    T.nilable(String),
          executable: T.nilable(T.any(String, Pathname)),
          args:       Arguments,
          env:        Environment,
        ).void
      }
      def initialize(cask, name, content: nil, executable: nil, args: [], env: {})
        name = Pathname(name)
        if name.basename != name || [".", ".."].include?(name.to_s)
          raise CaskInvalidError.new(cask, "'command_wrapper' requires a command name without path components")
        end
        if content.blank? && executable.to_s.blank?
          raise CaskInvalidError.new(cask, "'command_wrapper' requires content or executable")
        end
        if content.present? && executable.to_s.present?
          raise CaskInvalidError.new(cask, "'command_wrapper' requires content or executable, not both")
        end
        if content.present? && (args.present? || env.present?)
          raise CaskInvalidError.new(cask, "'command_wrapper' args and env require executable")
        end

        super(cask, ".homebrew-command-wrappers/#{name}", target: name)
        @content = T.let(content.presence, T.nilable(String))
        @executable = T.let(executable&.to_s.presence, T.nilable(String))
        @args = T.let(Array(args).map(&:to_s), T::Array[String])
        @env = T.let(env.to_h { |key, value| [key.to_s, value.to_s] }, T::Hash[String, String])
      end

      sig {
        override.params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          overwrite:    T::Boolean,
          dry_run:      T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        overwrite: false, dry_run: false, command: SystemCommand)
        unless dry_run
          if (content = @content)
            source.dirname.mkpath
            source.write(content)
          elsif (executable = @executable)
            args = @args.map { |arg| Shellwords.shellescape(arg) }
            source.write_env_script(executable, args, @env)
          end
        end
        super
      end

      sig { override.returns(T::Array[T.anything]) }
      def to_args
        options = {}
        if (content = @content)
          options[:content] = content
        else
          options[:executable] = @executable
          options[:args] = @args if @args.present?
          options[:env] = @env if @env.present?
        end
        [@target_string, options]
      end
    end
  end
end
