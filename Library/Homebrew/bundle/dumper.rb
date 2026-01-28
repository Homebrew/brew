# typed: strict
# frozen_string_literal: true

require "fileutils"
require "pathname"

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
          describe:   T::Boolean,
          no_restart: T::Boolean,
          formulae:   T::Boolean,
          taps:       T::Boolean,
          casks:      T::Boolean,
          mas:        T::Boolean,
          vscode:     T::Boolean,
          go:         T::Boolean,
          cargo:      T::Boolean,
          flatpak:    T::Boolean,
        ).returns(String)
      }
      def self.build_brewfile(describe:, no_restart:, formulae:, taps:, casks:, mas:, vscode:, go:, cargo:, flatpak:)
        require "bundle/tap_dumper"
        require "bundle/formula_dumper"
        require "bundle/cask_dumper"
        require "bundle/mac_app_store_dumper"
        require "bundle/vscode_extension_dumper"
        require "bundle/go_dumper"
        require "bundle/cargo_dumper"
        require "bundle/flatpak_dumper"

        content = []
        content << TapDumper.dump if taps
        content << FormulaDumper.dump(describe:, no_restart:) if formulae
        content << CaskDumper.dump(describe:) if casks
        content << MacAppStoreDumper.dump if mas
        content << VscodeExtensionDumper.dump if vscode
        content << GoDumper.dump if go
        content << CargoDumper.dump if cargo
        content << FlatpakDumper.dump if flatpak
        "#{content.reject(&:empty?).join("\n")}\n"
      end

      sig {
        params(
          global:     T::Boolean,
          file:       T.nilable(String),
          describe:   T::Boolean,
          force:      T::Boolean,
          no_restart: T::Boolean,
          formulae:   T::Boolean,
          taps:       T::Boolean,
          casks:      T::Boolean,
          mas:        T::Boolean,
          vscode:     T::Boolean,
          go:         T::Boolean,
          cargo:      T::Boolean,
          flatpak:    T::Boolean,
        ).void
      }
      def self.dump_brewfile(global:, file:, describe:, force:, no_restart:, formulae:, taps:, casks:, mas:,
                             vscode:, go:, cargo:, flatpak:)
        path = brewfile_path(global:, file:)
        can_write_to_brewfile?(path, force:)
        content = build_brewfile(
          describe:, no_restart:, taps:, formulae:, casks:, mas:, vscode:, go:, cargo:, flatpak:,
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
        Bundle.exchange_uid_if_needed! do
          file.open("w") { |io| io.write content }
        end
      end
    end
  end
end
