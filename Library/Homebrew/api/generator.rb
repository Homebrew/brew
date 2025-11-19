# typed: strict
# frozen_string_literal: true

require "tap"
require "formulary"
require "utils/output"
require "formula"
require "context"

module Homebrew
  module API
    class Generator
      include Utils::Output::Mixin

      sig { params(only_core: T::Boolean, only_cask: T::Boolean, dry_run: T::Boolean).void }
      def initialize(only_core: false, only_cask: false, dry_run: false)
        @generate_formula_api = T.let(!only_cask, T::Boolean)
        @generate_cask_api = T.let(!only_core, T::Boolean)
        @dry_run = T.let(dry_run, T::Boolean)
        @first_letter = T.let(nil, T.nilable(String))
      end

      sig { void }
      def generate!
        generate_api!(type: :formula) if generate_formula_api?
        generate_api!(type: :cask) if generate_cask_api?
        generate_packages_api! if generate_formula_api? && generate_cask_api?
      end

      private

      sig { returns(T::Boolean) }
      def generate_formula_api? = @generate_formula_api

      sig { returns(T::Boolean) }
      def generate_cask_api? = @generate_cask_api

      sig { returns(T::Boolean) }
      def dry_run? = @dry_run

      sig { params(type: Symbol).void }
      def generate_api!(type:)
        ohai "Generating #{type} API data..."

        tap = if type == :formula
          CoreTap.instance
        else
          CoreCaskTap.instance
        end
        raise TapUnavailableError, tap.name unless tap.installed?

        unless dry_run?
          directories = ["_data/#{type}", "api/#{type}", type.to_s]
          directories << "api/cask_source" if type == :cask

          FileUtils.rm_rf "_data/formula_canonical.json" if type == :formula
          FileUtils.rm_rf directories
          FileUtils.mkdir_p directories
        end

        Homebrew.with_no_api_env do
          tap_migrations_json = JSON.dump(tap.tap_migrations)
          File.write("api/#{type}_tap_migrations.json", tap_migrations_json) unless dry_run?

          if type == :formula
            Formulary.enable_factory_cache!
            ::Formula.generating_hash!
          else
            ::Cask::Cask.generating_hash!
          end

          # TODO: double check that this is fine for formulae, since they used -1 before for some reason
          latest_macos = MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            all_packages = if type == :formula
              formulae(tap)
            else
              casks(tap)
            end

            return if dry_run?

            all_packages.each do |name, hash|
              json = JSON.pretty_generate(hash)

              # TODO: add cask-source
              File.write("_data/#{type}/#{name.tr("+", "_")}.json", "#{json}\n")
              File.write("api/#{type}/#{name}.json", json_template(type: type))
              File.write("#{type}/#{name}.html", html_template(name, type: type))
            end
          end

          renames = if type == :formula
            tap.formula_renames.merge(tap.alias_table)
          else
            tap.cask_renames
          end

          canonical_json = JSON.pretty_generate(renames)
          File.write("_data/#{type}_canonical.json", "#{canonical_json}\n") unless dry_run?
        end
      end

      sig { void }
      def generate_packages_api!
        ohai "Generating packages API data..."

        core_tap = CoreTap.instance
        cask_tap = CoreCaskTap.instance

        OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
          formulae = formulae(core_tap).transform_values do |hash|
            InternalFormulaHash.from_hash(hash, bottle_tag:)
          end

          casks = casks(cask_tap).transform_values do |hash|
            InternalCaskHash.from_hash(hash, bottle_tag:)
          end

          next if dry_run?

          packages_hash = {
            formulae:            formulae,
            casks:               casks,
            core_aliases:        core_tap.alias_table,
            core_renames:        core_tap.formula_renames,
            core_tap_migrations: core_tap.tap_migrations,
            cask_renames:        cask_tap.cask_renames,
            cask_tap_migrations: cask_tap.tap_migrations,
          }

          FileUtils.mkdir_p "api/internal"
          File.write("api/internal/packages.#{bottle_tag}.json", JSON.generate(packages_hash))
        end
      end

      sig { params(tap: Tap).returns(T::Hash[String, T.untyped]) }
      def formulae(tap)
        reset_debugging!
        # TODO: remove the slicing when done testing
        @formulae ||= T.let(T.must(tap.formula_names.slice(0, 2)).to_h do |name|
          debug_load!(name, type: :formula)
          formula = Formulary.factory(name)
          [formula.name, formula.to_hash_with_variations]
        rescue
          onoe "Error while generating data for formula '#{name}'."
          raise
        end, T.nilable(T::Hash[String, T.untyped]))
      end

      sig { params(tap: Tap).returns(T::Hash[String, T.untyped]) }
      def casks(tap)
        reset_debugging!
        # TODO: remove the slicing when done testing
        @casks ||= T.let(T.must(tap.cask_files.slice(0, 2)).to_h do |path|
          debug_load!(path.stem, type: :cask)
          cask = ::Cask::CaskLoader.load(path)
          [cask.token, cask.to_hash_with_variations]
        rescue
          onoe "Error while generating data for cask '#{path.stem}'."
          raise
        end, T.nilable(T::Hash[String, T.untyped]))
      end

      sig { params(title: String, type: Symbol).returns(String) }
      def html_template(title, type:)
        redirect_from_string = ("redirect_from: /formula-linux/#{title}\n" if type == :formula)

        <<~EOS
          ---
          title: '#{title}'
          layout: #{type}
          #{redirect_from_string}---
          {{ content }}
        EOS
      end

      sig { params(type: Symbol).returns(String) }
      def json_template(type:)
        <<~EOS
          ---
          layout: #{type}_json
          ---
          {{ content }}
        EOS
      end

      sig { void }
      def reset_debugging!
        @first_letter = nil
      end

      sig { params(name: String, type: Symbol).void }
      def debug_load!(name, type:)
        return if name[0] == @first_letter
        return unless Context.current.verbose?

        @first_letter = name[0]
        puts "Loading #{type} starting with letter #{@first_letter}"
      end
    end

    module CompactSerializable
      extend T::Helpers

      requires_ancestor { T::Struct }

      sig { params(args: T.untyped).returns(String) }
      def to_json(*args)
        # TODO: this should recursively remove nils from nested hashes/arrays too
        serialize.compact.to_json(*args)
      end
    end

    class InternalFormulaHash < T::Struct
      include CompactSerializable

      # TODO: simplify these types when possible
      PROPERTIES = T.let({
        aliases:                         T::Array[String],
        # TODO: only include the relevant bottle info
        #       I think sample code used to live in `generate-formula-api`, but this commit removes it...
        bottle:                          T::Hash[String, T.untyped],
        caveats:                         T::Array[String],
        conflicts_with:                  T::Array[String],
        conflicts_with_reasons:          T::Array[String],
        dependencies:                    T::Array[String],
        deprecation_date:                String,
        deprecation_reason:              String,
        deprecation_replacement_cask:    String,
        deprecation_replacement_formula: String,
        desc:                            String,
        disable_date:                    String,
        disable_reason:                  String,
        disable_replacement_cask:        String,
        disable_replacement_formula:     String,
        head_dependencies:               T::Array[String],
        homepage:                        String,
        keg_only_reason:                 String,
        license:                         String,
        link_overwrite:                  T::Array[String],
        no_autobump_msg:                 String,
        oldnames:                        T::Array[String],
        post_install_defined:            T::Boolean,
        pour_bottle_only_if:             T::Hash[String, T.untyped],
        requirements:                    T::Array[String],
        revision:                        Integer,
        ruby_source_checksum:            T::Hash[String, T.untyped],
        ruby_source_path:                String,
        service:                         T::Hash[String, T.untyped],
        tap_git_head:                    String,
        urls:                            T::Hash[String, T.untyped],
        uses_from_macos:                 T::Array[String],
        uses_from_macos_bounds:          T::Array[T::Hash[String, T.untyped]],
        version_scheme:                  Integer,
        versioned_formulae:              T::Array[String],
        versions:                        T::Hash[String, T.untyped],
      }.freeze, T::Hash[Symbol, T.untyped])

      PROPERTIES.each do |property, type|
        const property, T.nilable(type)
      end

      sig { params(hash: T::Hash[String, T.untyped], bottle_tag: ::Utils::Bottles::Tag).returns(InternalFormulaHash) }
      def self.from_hash(hash, bottle_tag:)
        hash = Homebrew::API.merge_variations(hash, bottle_tag: bottle_tag).transform_keys(&:to_sym)
        new(**hash.slice(*PROPERTIES.keys))
      end
    end

    class InternalCaskHash < T::Struct
      include CompactSerializable

      # TODO: simplify these types when possible
      PROPERTIES = T.let({
        artifacts:          T::Array[T.untyped],
        auto_updates:       T::Boolean,
        caveats:            T::Array[String],
        conflicts_with:     T::Array[String],
        container:          T::Hash[String, T.untyped],
        depends_on:         ::Cask::DSL::DependsOn,
        deprecation_date:   String,
        deprecation_reason: String,
        desc:               String,
        disable_date:       String,
        disable_reason:     String,
        homepage:           String,
        name:               T::Array[String],
        rename:             T::Array[String],
        sha256:             Checksum,
        url:                ::Cask::URL,
        url_specs:          T::Hash[Symbol, T.untyped],
        version:            String,
      }.freeze, T::Hash[Symbol, T.untyped])

      PROPERTIES.each do |property, type|
        const property, T.nilable(type)
      end

      sig { params(hash: T::Hash[String, T.untyped], bottle_tag: ::Utils::Bottles::Tag).returns(InternalCaskHash) }
      def self.from_hash(hash, bottle_tag:)
        hash = Homebrew::API.merge_variations(hash, bottle_tag: bottle_tag).transform_keys(&:to_sym)
        new(**hash.slice(*PROPERTIES.keys))
      end
    end
  end
end
