# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"
require "abstract_command"

module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class SubcommandContext < T::Struct
        const :subcommand, String
        const :global, T::Boolean
        const :file, T.nilable(String)
        const :no_upgrade, T::Boolean
        const :verbose, T::Boolean
        const :force, T::Boolean
        const :ask, T::Boolean
        const :zap, T::Boolean
        const :no_type_args, T::Boolean
        const :extensions, T::Array[T.class_of(Homebrew::Bundle::Extension)]

        sig { params(args: T.untyped, extension: T.class_of(Homebrew::Bundle::Extension)).returns(T::Boolean) }
        def extension_selected?(args, extension)
          args.public_send(extension.predicate_method)
        end

        sig { params(args: T.untyped, extension: T.class_of(Homebrew::Bundle::Extension)).returns(T::Boolean) }
        def extension_dump_disabled?(args, extension)
          args.public_send(extension.dump_disable_predicate_method) ||
            args.public_send(:"no_dump_#{extension.type}?")
        end

        sig { params(args: T.untyped, extension: T.class_of(Homebrew::Bundle::Extension)).returns(T::Boolean) }
        def extension_disabled?(args, extension)
          args.public_send(extension.disable_predicate_method) ||
            args.public_send(:"no_cleanup_#{extension.type}?")
        end

        sig {
          params(args: T.untyped, prefix: String, all: T::Boolean)
            .returns(T::Hash[Symbol, T::Boolean])
        }
        def core_type_options(args, prefix, all: false)
          {
            formulae: type_selected?(args, :formulae?, :no_formulae?, :"no_#{prefix}_brew?", all:),
            casks:    type_selected?(args, :casks?, :no_casks?, :"no_#{prefix}_cask?", all:),
            taps:     type_selected?(args, :taps?, :no_taps?, :"no_#{prefix}_tap?", all:),
          }
        end

        sig { params(args: T.untyped).returns(T::Array[Symbol]) }
        def selected_types(args)
          # We intentionally omit the s from `brews`, `casks`, and `taps` for ease of handling later.
          type_hash = {
            brew: args.formulae?,
            cask: args.casks?,
            tap:  args.taps?,
          }
          extensions.each do |extension|
            type_hash[extension.type] = extension_selected?(args, extension)
          end
          type_hash[:none] = no_type_args
          type_hash.select { |_, v| v }.keys
        end

        private

        sig {
          params(args: T.untyped, predicate_method: Symbol, disabled_predicate_method: Symbol,
                 env_disabled_predicate_method: Symbol, all: T::Boolean).returns(T::Boolean)
        }
        def type_selected?(args, predicate_method, disabled_predicate_method, env_disabled_predicate_method,
                           all: false)
          !type_disabled?(args, disabled_predicate_method, env_disabled_predicate_method) &&
            (args.public_send(predicate_method) || all || no_type_args)
        end

        sig { params(args: T.untyped, disabled_methods: Symbol).returns(T::Boolean) }
        def type_disabled?(args, *disabled_methods)
          disabled_methods.any? { |disabled_method| args.public_send(disabled_method) }
        end
      end
    end
  end
end
