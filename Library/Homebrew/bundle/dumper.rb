# typed: strict
# frozen_string_literal: true

require "fileutils"
require "bundle/dsl"
require "bundle/extensions"
require "bundle/package_types"

module Homebrew
  module Bundle
    module Dumper
      sig { params(brewfile_path: Pathname, force: T::Boolean).returns(T::Boolean) }
      private_class_method def self.can_write_to_brewfile?(brewfile_path, force: false)
        raise "#{brewfile_path} already exists" if should_not_write_file?(brewfile_path, overwrite: force)

        true
      end

      sig {
        params(
          describe:        T::Boolean,
          no_restart:      T::Boolean,
          formulae:        T::Boolean,
          taps:            T::Boolean,
          casks:           T::Boolean,
          extension_types: Homebrew::Bundle::ExtensionTypes,
        ).returns(String)
      }
      def self.build_brewfile(describe:, no_restart:, formulae:, taps:, casks:, extension_types: {})
        selected_package_types = extension_types.dup
        selected_package_types[:tap] = taps
        selected_package_types[:brew] = formulae
        selected_package_types[:cask] = casks
        dumped_formulae = if formulae
          Homebrew::Bundle::Brew.formulae.filter_map { |f| f[:full_name] if f[:installed_on_request?] }
        else
          []
        end
        dumped_casks = if casks
          Homebrew::Bundle::Cask.casks.map(&:full_name)
        else
          []
        end
        content = []
        Homebrew::Bundle.dump_package_types.select(&:dump_supported?).each do |package_type|
          next unless selected_package_types.fetch(package_type.type, false)

          content << if package_type == Homebrew::Bundle::Tap
            Homebrew::Bundle::Tap.dump(dumped_formulae:, dumped_casks:)
          else
            package_type.dump_output(describe:, no_restart:)
          end
        end
        "#{content.reject(&:empty?).join("\n")}\n"
      end

      sig {
        params(
          global:          T::Boolean,
          file:            T.nilable(String),
          describe:        T::Boolean,
          force:           T::Boolean,
          no_restart:      T::Boolean,
          formulae:        T::Boolean,
          taps:            T::Boolean,
          casks:           T::Boolean,
          extension_types: Homebrew::Bundle::ExtensionTypes,
        ).void
      }
      def self.dump_brewfile(global:, file:, describe:, force:, no_restart:, formulae:, taps:, casks:,
                             extension_types: {})
        path = brewfile_path(global:, file:)
        can_write_to_brewfile?(path, force:)
        content = build_brewfile(
          describe:, no_restart:, taps:, formulae:, casks:, extension_types:,
        )
        write_file path, content
      end

      sig { params(global: T::Boolean, file: T.nilable(String)).returns(Pathname) }
      def self.brewfile_path(global: false, file: nil)
        require "bundle/brewfile"
        Brewfile.path(dash_writes_to_stdout: true, global:, file:)
      end

      sig { params(file: Pathname, overwrite: T::Boolean).returns(T::Boolean) }
      private_class_method def self.should_not_write_file?(file, overwrite: false)
        file.exist? && !overwrite && file.to_s != "/dev/stdout"
      end

      sig { params(file: Pathname, content: String).void }
      def self.write_file(file, content)
        file.open("w") { |io| io.write content }
      end
    end
  end
end
