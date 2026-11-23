# typed: strict
# frozen_string_literal: true

module Homebrew
  module TestBot
    # Tests installation and removal of changed casks.
    class Casks < Test
      sig { params(paths: T::Array[String]).void }
      def run!(paths)
        return if paths.empty? || !(cask_tap = tap)

        require "cask/cask_loader"
        require "cask/caskroom"
        require "simulate_system"
        require "utils/ast"

        other_os = SimulateSystem.simulating_or_running_on_linux? ? :macos : :linux
        paths.each do |path|
          cask_path = cask_tap.path/path
          source = Utils::AST::CaskAST.new(cask_path.read)
          if source.depends_on_os?(other_os, top_level: true) || source.excludes_arch?(SimulateSystem.current_arch)
            puts "Skipping #{cask_path.basename(".rb")}: unsupported on this runner."
            next
          end

          cask = Cask::CaskLoader.from_tap_path(cask_path)
          if cask.disabled? ||
             !cask.platform_supported?(SimulateSystem.current_tag, installable: false, require_download: false)
            puts "Skipping #{cask}: disabled or unsupported on this runner."
            next
          end

          if cask.version.blank? || cask.sha256.blank? || cask.url.blank?
            test HOMEBREW_BREW_FILE, "audit", "--cask", "--only=required_stanzas", "--", cask.full_name
            next
          end

          installed_before = Cask::Caskroom.tokens.select { |token| Cask::Caskroom.cask_installed?(token) }
          raise Cask::CaskError, "#{cask} is already installed." if !@dry_run && cask.installed?

          formulae_before = installed_formula_names unless @dry_run

          begin
            test HOMEBREW_BREW_FILE, "install", "--cask", "--", cask.full_name,
                 env: { "HOMEBREW_NO_INSTALL_CLEANUP" => "1" }
          ensure
            if formulae_before
              installed_by_test = (Cask::Caskroom.tokens - installed_before).select do |token|
                Cask::Caskroom.cask_installed?(token)
              end
              if installed_by_test.present?
                # Remove the tested cask before any of its dependencies.
                installed_by_test = (installed_by_test & [cask.token]) | installed_by_test
                test HOMEBREW_BREW_FILE, "uninstall", "--cask", "--", *installed_by_test,
                     env: { "HOMEBREW_NO_AUTOREMOVE" => "1" }
              end
            end
          end
        ensure
          if formulae_before && (new_formulae = installed_formula_names - formulae_before).present?
            test HOMEBREW_BREW_FILE, "uninstall", "--formula", "--", *new_formulae,
                 env: { "HOMEBREW_NO_AUTOREMOVE" => "1" }
          end
        end
      end

      private

      # Read the Cellar directly because subprocess installs do not invalidate Formula's rack cache.
      sig { returns(T::Array[String]) }
      def installed_formula_names
        return [] unless HOMEBREW_CELLAR.directory?

        HOMEBREW_CELLAR.subdirs.filter_map do |rack|
          next if rack.symlink? || rack.subdirs.empty?

          rack.basename.to_s
        end
      end
    end
  end
end
