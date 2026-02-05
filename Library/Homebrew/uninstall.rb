# typed: strict
# frozen_string_literal: true

require "dependents_message"
require "installed_dependents"
require "utils/output"

module Homebrew
  # Helper module for uninstalling kegs.
  module Uninstall
    extend ::Utils::Output::Mixin

    sig {
      params(
        kegs_by_rack:        T::Hash[Pathname, T::Array[Keg]],
        casks:               T::Array[Cask::Cask],
        force:               T::Boolean,
        ignore_dependencies: T::Boolean,
        named_args:          T::Array[String],
      ).void
    }
    def self.uninstall_kegs(kegs_by_rack, casks: [], force: false, ignore_dependencies: false, named_args: [])
      handle_unsatisfied_dependents(kegs_by_rack,
                                    casks:,
                                    ignore_dependencies:,
                                    named_args:)
      return if Homebrew.failed?

      kegs_by_rack.each do |rack, kegs|
        if force
          name = rack.basename

          if rack.directory?
            puts "Uninstalling #{name}... (#{rack.abv})"
            kegs.each do |keg|
              keg.unlink
              keg.uninstall
            end
          end

          rm_pin rack
        else
          kegs.each do |keg|
            begin
              f = Formulary.from_rack(rack)
              if f.pinned?
                onoe "#{f.full_name} is pinned. You must unpin it to uninstall."
                break # exit keg loop and move on to next rack
              end
            rescue
              nil
            end

            keg.lock do
              puts "Uninstalling #{keg}... (#{keg.abv})"
              keg.unlink
              keg.uninstall
              rack = keg.rack
              rm_pin rack

              if rack.directory?
                versions = rack.subdirs.map(&:basename)
                puts <<~EOS
                  #{keg.name} #{versions.to_sentence} #{versions.one? ? "is" : "are"} still installed.
                  To remove all versions, run:
                    brew uninstall --force #{keg.name}
                EOS
              end

              next unless f

              paths = f.pkgetc.find.map(&:to_s) if f.pkgetc.exist?
              if paths.present?
                puts
                opoo <<~EOS
                  The following #{f.name} configuration files have not been removed!
                  If desired, remove them manually with `rm -rf`:
                    #{paths.sort.uniq.join("\n  ")}
                EOS
              end

              unversioned_name = f.name.gsub(/@.+$/, "")
              maybe_paths = Dir.glob("#{f.etc}/#{unversioned_name}*")
              excluded_names = if Homebrew::EnvConfig.no_install_from_api?
                Formula.names
              else
                Homebrew::API.formula_names
              end
              maybe_paths = maybe_paths.reject do |path|
                # Remove extension only if a file
                # (e.g. directory with name "openssl@1.1" will be trimmed to "openssl@1")
                basename = if File.directory?(path)
                  File.basename(path)
                else
                  File.basename(path, ".*")
                end
                excluded_names.include?(basename)
              end
              maybe_paths -= paths if paths.present?
              if maybe_paths.present?
                puts
                opoo <<~EOS
                  The following may be #{f.name} configuration files and have not been removed!
                  If desired, remove them manually with `rm -rf`:
                    #{maybe_paths.sort.uniq.join("\n  ")}
                EOS
              end
            end
          end
        end
      end
    rescue MultipleVersionsInstalledError => e
      ofail e
    ensure
      # If we delete Cellar/newname, then Cellar/oldname symlink
      # can become broken and we have to remove it.
      if HOMEBREW_CELLAR.directory?
        HOMEBREW_CELLAR.children.each do |rack|
          rack.unlink if rack.symlink? && !rack.resolved_path_exists?
        end
      end
    end

    sig {
      params(
        kegs_by_rack:        T::Hash[Pathname, T::Array[Keg]],
        casks:               T::Array[Cask::Cask],
        ignore_dependencies: T::Boolean,
        named_args:          T::Array[String],
      ).void
    }
    def self.handle_unsatisfied_dependents(kegs_by_rack, casks: [], ignore_dependencies: false, named_args: [])
      return if ignore_dependencies

      all_kegs = kegs_by_rack.values.flatten(1)
      check_for_dependents!(all_kegs, casks:, named_args:)
    rescue MethodDeprecatedError
      # Silently ignore deprecations when uninstalling.
      nil
    end

    sig { params(kegs: T::Array[Keg], casks: T::Array[Cask::Cask], named_args: T::Array[String]).returns(T::Boolean) }
    def self.check_for_dependents!(kegs, casks: [], named_args: [])
      return false unless (result = InstalledDependents.find_some_installed_dependents(kegs, casks:))

      DependentsMessage.new(*result, named_args:).output
      true
    end

    sig { params(rack: Pathname).void }
    def self.rm_pin(rack)
      Formulary.from_rack(rack).unpin
    rescue
      nil
    end
  end
end
