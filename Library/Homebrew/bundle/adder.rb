# typed: strict
# frozen_string_literal: true

require "bundle/brewfile"
require "bundle/dumper"
require "tap"
require "trust"

module Homebrew
  module Bundle
    module Adder
      module_function

      sig { params(args: String, type: Symbol, global: T::Boolean, file: String, describe: T::Boolean).void }
      def add(*args, type:, global:, file:, describe: false)
        item_type = case type
        when :brew
          :formula
        when :cask
          :cask
        end
        if item_type
          args.each do |arg|
            tap_with_name = if type == :brew
              ::Tap.with_formula_name(arg)
            else
              ::Tap.with_cask_token(arg)
            end
            next unless tap_with_name

            tap, = tap_with_name
            tap.ensure_installed!
          end
          Homebrew::Trust.trust_fully_qualified_items!(args, type: item_type)
        end

        brewfile_path = Brewfile.path(global:, file:)
        brewfile_path.write("") unless brewfile_path.exist?

        brewfile = Brewfile.read(global:, file:)
        content = brewfile.input
        new_content = args.map do |arg|
          desc = case type
          when :brew
            Formulary.factory(arg).desc
          when :cask
            Kernel.require "cask/cask_loader"
            ::Cask::CaskLoader.load(arg).desc
          end

          entry = "#{type} \"#{arg}\""
          if describe && desc.present?
            desc.split("\n").map { |s| "# #{s}\n" }.join + entry
          else
            entry
          end
        end

        content << new_content.join("\n") << "\n"
        path = Dumper.brewfile_path(global:, file:)

        Dumper.write_file path, content
      end
    end
  end
end
