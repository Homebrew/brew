# typed: true
# frozen_string_literal: true

require "installed_dependents"

module Homebrew
  # Helper module for uninstalling kegs.
  #
  # @api private
  module Uninstall
    def self.uninstall_kegs(kegs_by_rack, casks: [], force: false, ignore_dependencies: false, named_args: [])
      handle_unsatisfied_dependents(kegs_by_rack,
                                    casks:               casks,
                                    ignore_dependencies: ignore_dependencies,
                                    named_args:          named_args)
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
                  #{keg.name} #{versions.to_sentence} #{(versions.count == 1) ? "is" : "are"} still installed.
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
              maybe_paths = Dir.glob("#{f.etc}/*#{unversioned_name}*")
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

    def self.handle_unsatisfied_dependents(kegs_by_rack, casks: [], ignore_dependencies: false, named_args: [])
      return if ignore_dependencies

      all_kegs = kegs_by_rack.values.flatten(1)
      check_for_dependents(all_kegs, casks: casks, named_args: named_args)
    rescue MethodDeprecatedError
      # Silently ignore deprecations when uninstalling.
      nil
    end

    def self.check_for_dependents(kegs, casks: [], named_args: [])
      return false unless (result = InstalledDependents.find_some_installed_dependents(kegs, casks: casks))

      if Homebrew::EnvConfig.developer?
        DeveloperDependentsMessage.new(*result, named_args: named_args).output
      else
        NondeveloperDependentsMessage.new(*result, named_args: named_args).output
      end

      true
    end

    # @api private
    class DependentsMessage
      attr_reader :reqs, :deps, :named_args

      def initialize(requireds, dependents, named_args: [])
        @reqs = requireds
        @deps = dependents
        @named_args = named_args
      end

      protected

      def sample_command
        "brew uninstall --ignore-dependencies #{named_args.join(" ")}"
      end

      def are_required_by_deps
        "#{(reqs.count == 1) ? "is" : "are"} required by #{deps.to_sentence}, " \
          "which #{(deps.count == 1) ? "is" : "are"} currently installed"
      end
    end

    # @api private
    class DeveloperDependentsMessage < DependentsMessage
      def output
        opoo <<~EOS
          #{reqs.to_sentence} #{are_required_by_deps}.
          You can silence this warning with:
            #{sample_command}
        EOS
      end
    end

    # @api private
    class NondeveloperDependentsMessage < DependentsMessage
      def output
        ofail <<~EOS
          Refusing to uninstall #{reqs.to_sentence}
          because #{(reqs.count == 1) ? "it" : "they"} #{are_required_by_deps}.
          You can override this and force removal with:
            #{sample_command}
        EOS
      end
    end

    def self.rm_pin(rack)
      Formulary.from_rack(rack).unpin
    rescue
      nil
    end
  end
end
