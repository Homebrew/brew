# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "json"
require "trust"

module Homebrew
  module Cmd
    class Trust < AbstractCommand
      VALID_TYPES = [:tap, :formula, :cask, :command].freeze

      cmd_args do
        description <<~EOS
          Trust non-official tap formulae, casks or commands so Homebrew may load them.
          Trusted entries are stored in `${XDG_CONFIG_HOME}/homebrew/trust.json` if
          `$XDG_CONFIG_HOME` is set or `~/.homebrew/trust.json` otherwise.
        EOS
        switch "--tap", "--taps",
               description: "Trust the named tap."
        switch "--formula", "--formulae",
               description: "Trust the named formula."
        switch "--cask", "--casks",
               description: "Trust the named cask."
        switch "--command", "--commands",
               description: "Trust the named external command."
        flag "--json=",
             description: "Print trusted entries as JSON. A <version> number is required. " \
                          "The only accepted value for <version> is `v1`."

        conflicts "--tap", "--formula", "--cask", "--command"

        named_args :target
      end

      sig { override.void }
      def run
        if args.json
          raise UsageError, "invalid JSON version: #{args.json}" if args.json != "v1"
          raise UsageError, "`--json=v1` requires no named arguments." if args.named.present?

          print_json
          return
        end

        if args.no_named?
          puts "All official taps and commands are trusted."
          printed = T.let(false, T::Boolean)
          types.each do |type|
            values = Homebrew::Trust.trusted_entries(type)
            next if values.empty?

            label = Utils.pluralize(type.to_s, 2)
            puts "Trusted #{label}:"
            values.each { |value| puts "  #{value}" }
            printed = true
          end

          puts "No trusted taps, formulae, casks or commands." unless printed
          return
        end

        args.named.each do |name|
          type, trust_name = Homebrew::Trust.target(name, type: selected_type)
          if type == :tap && !Tap.remote_reference?(trust_name) && Tap.fetch(trust_name).official?
            puts "Official tap #{trust_name} is always trusted."
            next
          end

          action = Homebrew::Trust.trust!(type, trust_name) ? "Trusted" : "Already trusted"

          puts "#{action} #{type}: #{trust_name}"
        end
      end

      private

      sig { void }
      def print_json
        if (type = selected_type)
          puts JSON.pretty_generate(Homebrew::Trust.trusted_entries(type))
          return
        end

        json = T.let({}, T::Hash[String, T::Array[String]])

        types.each do |type|
          key = Utils.pluralize(type.to_s, 2)
          json[key] = Homebrew::Trust.trusted_entries(type)
        end

        puts JSON.pretty_generate(json)
      end

      sig { returns(T::Array[Symbol]) }
      def types
        type = selected_type
        return [type] if type

        VALID_TYPES
      end

      sig { returns(T.nilable(Symbol)) }
      def selected_type
        return :tap if args.tap?
        return :formula if args.formula?
        return :cask if args.cask?

        :command if args.command? || args.commands?
      end
    end
  end
end
