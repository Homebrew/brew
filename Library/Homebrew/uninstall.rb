# typed: strict
# frozen_string_literal: true

require "utils/text"

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
        dry_run:             T::Boolean,
      ).returns(T.nilable(T::Array[Keg]))
    }
    def self.uninstall_kegs(kegs_by_rack, casks: [], force: false, ignore_dependencies: false, named_args: [],
                            dry_run: false)
      kegs_to_uninstall = []
      handle_unsatisfied_dependents(kegs_by_rack,
                                    casks:,
                                    ignore_dependencies:,
                                    named_args:,
                                    dry_run:)
      return if Homebrew.failed?

      kegs_by_rack.each do |rack, kegs|
        if force
          name = rack.basename

          if rack.directory?
            if dry_run
              kegs.each do |keg|
                puts "Would uninstall #{keg.name} #{keg.version}"
                kegs_to_uninstall << keg
                keg.unlink(dry_run: true)
                keg.uninstall(dry_run: true)
              end
            else
              puts "Uninstalling #{name}... (#{rack.abv})"
              kegs.each do |keg|
                kegs_to_uninstall << keg
                keg.unlink
                keg.uninstall
              end
            end
          end

          rm_pin rack unless dry_run
        else
          kegs.each do |keg|
            pinned_name = begin
              f = Formulary.from_rack(rack)
              f.full_name if f.pinned?
            rescue
              keg.name if (HOMEBREW_PINNED_KEGS/keg.name).symlink?
            end
            if pinned_name
              onoe "#{pinned_name} is pinned. You must unpin it to uninstall."
              break # exit keg loop and move on to next rack
            end

            keg.lock do
              if dry_run
                puts "Would uninstall #{keg.name} #{keg.version}"
                kegs_to_uninstall << keg
                keg.unlink(dry_run: true)
                keg.uninstall(dry_run: true)
                next
              end

              puts "Uninstalling #{keg}... (#{keg.abv})"
              kegs_to_uninstall << keg
              keg.unlink
              keg.uninstall
              rack = keg.rack
              rm_pin rack

              if rack.directory?
                versions = rack.subdirs.map(&:basename)
                verb = versions.one? ? "is" : "are"
                puts <<~EOS
                  #{keg.name} #{Utils::Text.to_sentence(versions)} #{verb} still installed.
                  To remove all versions, run:
                    brew uninstall --force #{keg.name}
                EOS
              end

              next unless f

              paths = f.pkgetc.find.map(&:to_s) if f.pkgetc.exist?
              if paths.present?
                puts
                paths_list = paths.sort.uniq.join("\n  ")
                opoo <<~EOS
                  The following #{f.name} configuration files have not been removed!
                  If desired, remove them manually with `rm -rf`:
                    #{paths_list}
                EOS
              end

              unversioned_name = f.name.gsub(/@.+$/, "")
              maybe_paths = Dir.glob("#{f.etc}/#{unversioned_name}*")
              excluded_names = if Homebrew::EnvConfig.no_install_from_api?
                Formula.names
              else
                Homebrew::API.formula_names
              end.to_set
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
                paths_list = maybe_paths.sort.uniq.join("\n  ")
                opoo <<~EOS
                  The following may be #{f.name} configuration files and have not been removed!
                  If desired, remove them manually with `rm -rf`:
                    #{paths_list}
                EOS
              end
            end
          end
        end
      end
      kegs_to_uninstall
    rescue MultipleVersionsInstalledError => e
      ofail e
      nil
    ensure
      # If we delete Cellar/newname, then Cellar/oldname symlink
      # can become broken and we have to remove it.
      if !dry_run && HOMEBREW_CELLAR.directory?
        HOMEBREW_CELLAR.children.each do |rack|
          rack.unlink if rack.symlink? && !Utils::Path.resolved_path_exists?(rack)
        end
      end
    end

    sig {
      params(
        kegs_by_rack:        T::Hash[Pathname, T::Array[Keg]],
        casks:               T::Array[Cask::Cask],
        ignore_dependencies: T::Boolean,
        named_args:          T::Array[String],
        dry_run:             T::Boolean,
      ).void
    }
    def self.handle_unsatisfied_dependents(kegs_by_rack, casks: [], ignore_dependencies: false, named_args: [],
                                           dry_run: false)
      return if ignore_dependencies

      all_kegs = kegs_by_rack.values.flatten(1)
      # A formula that is uninstalled too does not keep the dependencies it declares.
      keg_names = all_kegs.map(&:name)
      remaining_formulae = Formula.installed.reject { |f| keg_names.intersect?(f.possible_names) }
      InstalledDependents.prune_stale_dependencies(remaining_formulae, dry_run:)
      check_for_dependents!(all_kegs, casks:, named_args:)
    rescue MethodDeprecatedError
      # Silently ignore deprecations when uninstalling.
      nil
    end

    sig { params(kegs: T::Array[Keg], casks: T::Array[Cask::Cask], named_args: T::Array[String]).returns(T::Boolean) }
    def self.check_for_dependents!(kegs, casks: [], named_args: [])
      if (result = InstalledDependents.find_some_installed_dependents(kegs, casks:))
        required_kegs, dependents = result
        formulae = Formula.installed.select { |f| dependents.include?(f.to_s) }
        # A dependent that is not a formula keeps requiring the kegs.
        commands = if formulae.count == dependents.count
          keg_names = required_kegs.to_h { |keg| [keg.name, keg.name] }
          InstalledDependents.commands_to_drop_dependencies(keg_names, formulae, all_dependents: true)
        else
          []
        end
        DependentsMessage.new(required_kegs, dependents, named_args:, commands:).output
      elsif (result = InstalledDependents.find_installed_build_dependents(kegs))
        DependentsMessage.new(*result, named_args:, build: true).output
      else
        return false
      end
      true
    end

    sig { params(rack: Pathname).void }
    def self.rm_pin(rack)
      Formulary.from_rack(rack).unpin
    rescue
      pin = HOMEBREW_PINNED_KEGS/rack.basename
      return if pin.exist? || !pin.symlink?

      pin.unlink
      Utils::Path.rmdir_if_possible(HOMEBREW_PINNED_KEGS)
    end
  end
end
