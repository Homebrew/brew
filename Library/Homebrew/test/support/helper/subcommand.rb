# typed: true
# frozen_string_literal: true

module Test
  module Helper
    module Subcommand
      extend T::Helpers

      requires_ancestor { Kernel }

      class Args
        attr_reader :named

        KNOWN_PREDICATES = [
          :all?,
          :cargo?,
          :casks?,
          :check?,
          :cleanup?,
          :no_cleanup_brew?,
          :no_cleanup_cargo?,
          :no_cleanup_cask?,
          :no_cleanup_flatpak?,
          :no_cleanup_go?,
          :no_cleanup_krew?,
          :no_cleanup_mas?,
          :no_cleanup_npm?,
          :no_cleanup_tap?,
          :no_cleanup_uv?,
          :no_cleanup_vscode?,
          :no_cleanup_winget?,
          :describe?,
          :no_describe?,
          :no_dump_brew?,
          :no_dump_cargo?,
          :no_dump_cask?,
          :no_dump_flatpak?,
          :no_dump_go?,
          :no_dump_krew?,
          :no_dump_mas?,
          :no_dump_npm?,
          :no_dump_tap?,
          :no_dump_uv?,
          :no_dump_vscode?,
          :no_dump_winget?,
          :flatpak?,
          :force?,
          :formulae?,
          :global?,
          :go?,
          :install?,
          :krew?,
          :mas?,
          :no_cargo?,
          :no_casks?,
          :no_flatpak?,
          :no_formulae?,
          :no_go?,
          :no_krew?,
          :no_mas?,
          :no_npm?,
          :no_restart?,
          :no_secrets?,
          :no_taps?,
          :no_upgrade?,
          :no_uv?,
          :no_vscode?,
          :no_winget?,
          :npm?,
          :quiet?,
          :services?,
          :taps?,
          :upgrade?,
          :uv?,
          :verbose?,
          :vscode?,
          :winget?,
          :zap?,
        ].freeze

        def initialize(named:, **options)
          @named = named
          @options = options
        end

        def method_missing(name, *args)
          if args.empty? && @options.key?(name)
            @options.fetch(name)
          elsif args.empty? && KNOWN_PREDICATES.include?(name)
            false
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          @options.key?(name) || KNOWN_PREDICATES.include?(name) || super
        end
      end

      sig {
        params(
          subcommand: T.nilable(T.any(String, Symbol)),
          named:      T.untyped,
          options:    T.untyped,
        ).returns(Test::Helper::Subcommand::Args)
      }
      def args_for_subcommand(subcommand = nil, *named, **options)
        Test::Helper::Subcommand::Args.new(named:, subcommand: subcommand&.to_s, **options)
      end

      require "cmd/bundle"
      sig {
        params(
          subcommand:   T.any(String, Symbol),
          global:       T::Boolean,
          file:         T.nilable(String),
          no_upgrade:   T::Boolean,
          verbose:      T::Boolean,
          force:        T::Boolean,
          ask:          T::Boolean,
          jobs:         Integer,
          zap:          T::Boolean,
          no_type_args: T::Boolean,
        ).returns(Homebrew::Cmd::Bundle::SubcommandContext)
      }
      def bundle_subcommand_context(subcommand, global: false, file: nil, no_upgrade: false, verbose: false,
                                    force: false, ask: false, jobs: 1, zap: false, no_type_args: true)
        Homebrew::Cmd::Bundle::SubcommandContext.new(
          subcommand:   subcommand.to_s,
          global:,
          file:,
          no_upgrade:,
          verbose:,
          force:,
          ask:,
          jobs:,
          zap:,
          no_type_args:,
          extensions:   Homebrew::Bundle.extensions,
        )
      end
    end
  end
end
