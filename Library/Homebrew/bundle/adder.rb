# typed: strict
# frozen_string_literal: true

require "bundle/brewfile"
require "bundle/dumper"

module Homebrew
  module Bundle
    module Adder
      module_function

      sig { params(args: String, type: Symbol, global: T::Boolean, file: String).void }
      def add(*args, type:, global:, file:)
        brewfile_path = Brewfile.path(global:, file:)
        brewfile_path.write("") unless brewfile_path.exist?

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
