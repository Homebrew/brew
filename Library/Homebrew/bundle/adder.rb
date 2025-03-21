# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/brewfile"
require "bundle/dumper"

module Homebrew
  module Bundle
    module Adder
      module_function

      def add(*args, type:, global:, file:)
        brewfile = Brewfile.read(global:, file:)
        content = brewfile.input
        # TODO: - support `:describe`
        new_content = args.map do |arg|
          case type
          when :brew
            Formulary.factory(arg)
          when :cask
            Cask::CaskLoader.load(arg)
          end

          "#{type} \"#{arg}\""
        end

        content << new_content.join("\n") << "\n"
        path = Dumper.brewfile_path(global:, file:)

        Dumper.write_file path, content
      end
    end
  end
end
