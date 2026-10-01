# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "trust"

module Homebrew
  module Cmd
    class Untrust < AbstractCommand
      cmd_args do
        description <<~EOS
          Stop trusting non-official tap formulae, casks or commands.
          Trusted entries are stored in `${XDG_CONFIG_HOME}/homebrew/trust.json` if
          `$XDG_CONFIG_HOME` is set or `~/.homebrew/trust.json` otherwise.
        EOS
        switch "--tap",
               description: "Untrust the named tap."
        switch "--formula", "--formulae",
               description: "Untrust the named formula."
        switch "--cask", "--casks",
               description: "Untrust the named cask."
        switch "--command", "--commands",
               description: "Untrust the named external command."

        conflicts "--tap", "--formula", "--cask", "--command"

        named_args :target
      end

      sig { override.void }
      def run
        if args.no_named?
          types = selected_type ? [selected_type] : [:tap, :formula, :cask, :command]
          printed = T.let(false, T::Boolean)
          types.each do |type|
            values = Homebrew::Trust.untrusted_taps.flat_map do |tap|
              case type
              when :tap
                [tap.name]
              when :formula
                tap.formula_files.filter_map do |file|
                  name = file.basename(file.extname).to_s
                  full_name = "#{tap.name}/#{name}"
                  full_name unless Homebrew::Trust.trusted?(:formula, full_name)
                end
              when :cask
                tap.cask_files.filter_map do |file|
                  name = file.basename(file.extname).to_s
                  full_name = "#{tap.name}/#{name}"
                  full_name unless Homebrew::Trust.trusted?(:cask, full_name)
                end
              when :command
                tap.command_files.filter_map do |file|
                  name = file.basename(file.extname).to_s.delete_prefix("brew-")
                  full_name = "#{tap.name}/#{name}"
                  full_name unless Homebrew::Trust.trusted?(:command, full_name)
                end
              else
                raise "Unsupported trust type: #{type}"
              end
            end.sort
            next if values.empty?

            label = case type
            when :tap then "taps"
            when :formula then "formulae"
            when :cask then "casks"
            when :command then "commands"
            else raise "Unsupported trust type: #{type}"
            end
            puts "Untrusted #{label}:"
            values.each { |value| puts "  #{value}" }
            printed = true
          end

          puts "No untrusted taps, formulae, casks or commands." unless printed
          return
        end

        args.named.each do |name|
          item_types = [:formula, :cask, :command]
          type, trust_name = Homebrew::Trust.target(name, type: selected_type, include_existing: true)
          if type == :tap && !Tap.remote_reference?(trust_name) && Tap.fetch(trust_name).official?
            puts "Official tap #{trust_name} is always trusted."
            next
          end

          removed = Homebrew::Trust.untrust!(type, trust_name)
          if type == :tap
            item_types.each do |item_type|
              Homebrew::Trust.trusted_entries(item_type).each do |entry|
                removed = true if entry.start_with?("#{trust_name}/") && Homebrew::Trust.untrust!(item_type, entry)
              end
            end
          end
          action = removed ? "Untrusted" : "Not trusted"

          puts "#{action} #{type}: #{trust_name}"
        end
      end

      private

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
