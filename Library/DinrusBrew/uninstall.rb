# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "installed_dependents"

module DinrusBrew
  # Helper module for uninstalling kegs.
  module Uninstall
    def self.uninstall_kegs(kegs_by_rack, casks: [], force: false, ignore_dependencies: false, named_args: [])
      handle_unsatisfied_dependents(kegs_by_rack,
                                    casks:,
                                    ignore_dependencies:,
                                    named_args:)
      return if DinrusBrew.failed?

      kegs_by_rack.each do |rack, kegs|
        if force
          name = rack.basename

          if rack.directory?
            puts "Деинсталируется #{name}... (#{rack.abv})"
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
                onoe "#{f.full_name} прикреплён. Для деинсталяции его нужно сначала открепить (unpin)."
                break # exit keg loop and move on to next rack
              end
            rescue
              nil
            end

            keg.lock do
              puts "Деинсталируется #{keg}... (#{keg.abv})"
              keg.unlink
              keg.uninstall
              rack = keg.rack
              rm_pin rack

              if rack.directory?
                versions = rack.subdirs.map(&:basename)
                puts <<~EOS
                  #{keg.name} #{versions.to_sentence} всё ещё #{(versions.count == 1) ? "установлен" : "установлены"}.
                  Чтобы удалить все версии, выполните:
                    brew uninstall --force #{keg.name}
                EOS
              end

              next unless f

              paths = f.pkgetc.find.map(&:to_s) if f.pkgetc.exist?
              if paths.present?
                puts
                opoo <<~EOS
                  Следующие файлы конфигурации: #{f.name} - не были удалены!
                  Если хотите, удалите их вручную, посредством `rm -rf`:
                    #{paths.sort.uniq.join("\n  ")}
                EOS
              end

              unversioned_name = f.name.gsub(/@.+$/, "")
              maybe_paths = Dir.glob("#{f.etc}/*#{unversioned_name}*")
              maybe_paths -= paths if paths.present?
              if maybe_paths.present?
                puts
                opoo <<~EOS
                  Возможно, следующие файлы - #{f.name} - файлы конфигурации, и они не удалены!
                  Если хотите, удалите их вручную, посредством `rm -rf`:
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
      if DINRUSBREW_CELLAR.directory?
        DINRUSBREW_CELLAR.children.each do |rack|
          rack.unlink if rack.symlink? && !rack.resolved_path_exists?
        end
      end
    end

    def self.handle_unsatisfied_dependents(kegs_by_rack, casks: [], ignore_dependencies: false, named_args: [])
      return if ignore_dependencies

      all_kegs = kegs_by_rack.values.flatten(1)
      check_for_dependents(all_kegs, casks:, named_args:)
    rescue MethodDeprecatedError
      # Silently ignore deprecations when uninstalling.
      nil
    end

    def self.check_for_dependents(kegs, casks: [], named_args: [])
      return false unless (result = InstalledDependents.find_some_installed_dependents(kegs, casks:))

      DependentsMessage.new(*result, named_args:).output
      true
    end

    class DependentsMessage
      attr_reader :reqs, :deps, :named_args

      def initialize(requireds, dependents, named_args: [])
        @reqs = requireds
        @deps = dependents
        @named_args = named_args
      end

      def output
        ofail <<~EOS
          Отказано в деинсталяции #{reqs.to_sentence},
          так как #{(reqs.count == 1) ? "он" : "они"} #{are_required_by_deps}.
          Это можно переопределить и форсировать удаление посредством:
            #{sample_command}
        EOS
      end

      protected

      def sample_command
        "brew uninstall --ignore-dependencies #{named_args.join(" ")}"
      end

      def are_required_by_deps
        "требу#{(reqs.count == 1) ? "ется" : "ются"} для #{deps.to_sentence}, " \
          "котор#{(deps.count == 1) ? "ый" : "ые"} в данный момент установлен#{(deps.count == 1) ? "" : "ы"}"
      end
    end

    def self.rm_pin(rack)
      Formulary.from_rack(rack).unpin
    rescue
      nil
    end
  end
end
