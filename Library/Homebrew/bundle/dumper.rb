# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require "pathname"

module Homebrew
  module Bundle
    module Dumper
      private_class_method def self.can_write_to_brewfile?(brewfile_path, force: false)
        raise "#{brewfile_path} already exists" if should_not_write_file?(brewfile_path, overwrite: force)

        true
      end

      def self.build_brewfile(describe:, no_restart:, brews:, taps:, casks:, mas:, whalebrew:, vscode:)
        require "bundle/tap_dumper"
        require "bundle/brew_dumper"
        require "bundle/cask_dumper"
        require "bundle/mac_app_store_dumper"
        require "bundle/whalebrew_dumper"
        require "bundle/vscode_extension_dumper"

        content = []
        content << TapDumper.dump if taps
        content << BrewDumper.dump(describe:, no_restart:) if brews
        content << CaskDumper.dump(describe:) if casks
        content << MacAppStoreDumper.dump if mas
        content << WhalebrewDumper.dump if whalebrew
        content << VscodeExtensionDumper.dump if vscode
        "#{content.reject(&:empty?).join("\n")}\n"
      end

      def self.dump_brewfile(global:, file:, describe:, force:, no_restart:, brews:, taps:, casks:, mas:, whalebrew:,
                             vscode:)
        path = brewfile_path(global:, file:)
        can_write_to_brewfile?(path, force:)
        content = build_brewfile(describe:, no_restart:, taps:, brews:, casks:, mas:, whalebrew:, vscode:)
        write_file path, content
      end

      def self.brewfile_path(global: false, file: nil)
        require "bundle/brewfile"
        Brewfile.path(dash_writes_to_stdout: true, global:, file:)
      end

      private_class_method def self.should_not_write_file?(file, overwrite: false)
        file.exist? && !overwrite && file.to_s != "/dev/stdout"
      end

      def self.write_file(file, content)
        Bundle.exchange_uid_if_needed! do
          file.open("w") { |io| io.write content }
        end
      end
    end
  end
end
