# typed: strict
# frozen_string_literal: true

require "utils"
require "utils/output"
require "bundle/package_type"

module Homebrew
  module Bundle
    class Cask < Homebrew::Bundle::PackageType
      extend ::Utils::Output::Mixin

      PACKAGE_TYPE = :cask
      PACKAGE_TYPE_NAME = "Cask"

      class << self
        sig { override.void }
        def reset!
          @casks = T.let(nil, T.nilable(T::Array[::Cask::Cask]))
          @cask_names = T.let(nil, T.nilable(T::Array[String]))
          @cask_oldnames = T.let(nil, T.nilable(T::Hash[String, String]))
          @installed_casks = T.let(nil, T.nilable(T::Array[String]))
          @outdated_casks = T.let(nil, T.nilable(T::Array[String]))
        end

        private

        sig { params(no_upgrade: T::Boolean, name: String, options: Homebrew::Bundle::EntryOptions).returns(T::Boolean) }
        def upgrading?(no_upgrade, name, options)
          return false if no_upgrade
          return true if cask_upgradable?(name)
          return false unless options[:greedy]

          cask_is_outdated_using_greedy?(name)
        end

        sig { params(name: String, options: Homebrew::Bundle::EntryOptions, verbose: T::Boolean).returns(T::Boolean) }
        def postinstall_change_state!(name:, options:, verbose:)
          postinstall = T.cast(options.fetch(:postinstall, nil), T.nilable(String))
          return true if postinstall.blank?

          puts "Running postinstall for #{name}: #{postinstall}" if verbose
          Kernel.system(postinstall) || false
        end

        sig { returns(T::Array[::Cask::Cask]) }
        def casks
          return [] unless Bundle.cask_installed?

          require "cask/caskroom"
          @casks ||= T.let(::Cask::Caskroom.casks, T.nilable(T::Array[::Cask::Cask]))
        end

        sig { params(cask_config: ::Cask::Config).returns(String) }
        def explicit_s(cask_config)
          cask_config.explicit.map do |key, value|
            # inverse of #env - converts :languages config key back to --language flag
            if key == :languages
              key = "language"
              value = Array(cask_config.explicit.fetch(:languages, [])).join(",")
            end
            "#{key}: \"#{value.to_s.sub(/^#{Dir.home}/, "~")}\""
          end.join(", ")
        end

        public

        # Override makes `name` a required argument unlike the parent's default-argument signature.
        # rubocop:disable Sorbet/AllowIncompatibleOverride
        sig {
          override(allow_incompatible: true).params(name: String, options: Homebrew::Bundle::EntryOptions).returns(String)
        }
        # rubocop:enable Sorbet/AllowIncompatibleOverride
        def install_verb(name, options = {})
          return "Installing" if !cask_installed?(name) || !upgrading?(false, name, options)

          "Upgrading"
        end

        sig { override.params(name: String, no_upgrade: T::Boolean, verbose: T::Boolean, options: T.untyped).returns(T::Boolean) }
        def preinstall!(name, no_upgrade: false, verbose: false, **options)
          if cask_installed?(name) && !upgrading?(no_upgrade, name, options)
            puts "Skipping install of #{name} cask. It is already installed." if verbose
            return false
          end

          true
        end

        sig {
          override.params(name: String, preinstall: T::Boolean, no_upgrade: T::Boolean, verbose: T::Boolean,
                          force: T::Boolean, options: T.untyped).returns(T::Boolean)
        }
        def install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, **options)
          return true unless preinstall

          full_name = options.fetch(:full_name, name)

          install_result = if cask_installed?(name) && upgrading?(no_upgrade, name, options)
            status = "#{options[:greedy] ? "may not be" : "not"} up-to-date"
            puts "Upgrading #{name} cask. It is installed but #{status}." if verbose
            Bundle.brew("upgrade", "--cask", full_name, verbose:)
          else
            args = options.fetch(:args, []).filter_map do |k, v|
              case v
              when TrueClass
                "--#{k}"
              when FalseClass, NilClass
                nil
              else
                "--#{k}=#{v}"
              end
            end

            args << "--force" if force
            args << "--adopt" unless args.include?("--force")
            args.uniq!

            with_args = " with #{args.join(" ")}" if args.present?
            puts "Installing #{name} cask#{with_args}. It is not currently installed." if verbose

            if Bundle.brew("install", "--cask", full_name, *args, verbose:)
              installed_casks << name
              true
            else
              false
            end
          end
          result = install_result

          if cask_installed?(name)
            postinstall_result = postinstall_change_state!(name:, options:, verbose:)
            result &&= postinstall_result
          end

          result
        end

        sig { params(name: String, no_upgrade: T::Boolean, options: T.untyped).returns(T::Boolean) }
        def installable_or_upgradable?(name, no_upgrade: false, **options)
          !cask_installed?(name) || upgrading?(no_upgrade, name, options)
        end

        sig { params(name: String, options: Homebrew::Bundle::EntryOptions, no_upgrade: T::Boolean).returns(T.nilable(String)) }
        def fetchable_name(name, options = {}, no_upgrade: false)
          full_name = T.cast(options.fetch(:full_name, name), String)
          return if (tap_name = Utils.tap_from_full_name(full_name)) &&
                    Homebrew::Bundle::Tap.installed_taps.exclude?(tap_name)
          return unless installable_or_upgradable?(name, no_upgrade:, **options)

          full_name
        end

        sig { params(cask: String, no_upgrade: T::Boolean).returns(T::Boolean) }
        def cask_installed_and_up_to_date?(cask, no_upgrade: false)
          return false unless cask_installed?(cask)
          return true if no_upgrade

          !cask_upgradable?(cask)
        end

        sig { params(cask: String, array: T::Array[String]).returns(T::Boolean) }
        def cask_in_array?(cask, array)
          return true if array.include?(cask)

          array.include?(Utils.name_from_full_name(cask))
        end

        sig { params(cask: String).returns(T::Boolean) }
        def cask_installed?(cask)
          return true if cask_in_array?(cask, installed_casks)

          old_name = cask_oldnames[cask]
          old_name ||= cask_oldnames[Utils.name_from_full_name(cask)]
          return false unless old_name
          return false unless cask_in_array?(old_name, installed_casks)

          opoo "#{cask} was renamed to #{old_name}"

          true
        end

        sig { params(cask: String).returns(T::Boolean) }
        def cask_upgradable?(cask)
          cask_in_array?(cask, outdated_casks)
        end

        sig { returns(T::Array[String]) }
        def installed_casks
          @installed_casks ||= cask_names
        end

        sig { returns(T::Array[String]) }
        def outdated_casks
          @outdated_casks ||= outdated_cask_names
        end

        sig { returns(T::Array[String]) }
        def cask_names
          @cask_names ||= casks.map(&:to_s)
        end

        sig { returns(T::Array[String]) }
        def outdated_cask_names
          return [] unless Bundle.cask_installed?

          casks.select { |c| c.outdated?(greedy: false) }
               .map(&:to_s)
        end

        sig { params(cask_name: String).returns(T::Boolean) }
        def cask_is_outdated_using_greedy?(cask_name)
          return false unless Bundle.cask_installed?

          cask = casks.find { |installed_cask| installed_cask.to_s == cask_name }
          return false if cask.nil?

          cask.outdated?(greedy: true)
        end

        sig { override.params(describe: T::Boolean).returns(String) }
        def dump(describe: false)
          casks.map do |cask|
            description = "# #{cask.desc}\n" if describe && cask.desc.present?
            config = ", args: { #{explicit_s(cask.config)} }" if cask.config.present? && cask.config.explicit.present?
            "#{description}cask \"#{cask.full_name}\"#{config}"
          end.join("\n")
        end

        sig { override.params(describe: T::Boolean, no_restart: T::Boolean).returns(String) }
        def dump_output(describe: false, no_restart: false)
          _ = no_restart

          dump(describe:)
        end

        sig { returns(T::Hash[String, String]) }
        def cask_oldnames
          @cask_oldnames ||= casks.each_with_object({}) do |c, hash|
            oldnames = c.old_tokens
            next if oldnames.blank?

            oldnames.each do |oldname|
              hash[oldname] = c.full_name
              if (tap_name = Utils.tap_from_full_name(c.full_name))
                hash["#{tap_name}/#{oldname}"] = c.full_name
              end
            end
          end
        end

        sig { params(cask_list: T::Array[String]).returns(T::Array[String]) }
        def formula_dependencies(cask_list)
          return [] unless Bundle.cask_installed?
          return [] if cask_list.blank?

          casks.flat_map do |cask|
            next unless cask_list.include?(cask.to_s)

            cask.depends_on[:formula]
          end.compact
        end
      end

      sig { override.params(cask: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(cask, no_upgrade: false)
        raise "cask must be a String, got #{cask.class}: #{cask}" unless cask.is_a?(String)

        self.class.cask_installed_and_up_to_date?(cask, no_upgrade:)
      end
    end
  end
end
