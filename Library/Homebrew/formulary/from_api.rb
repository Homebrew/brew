# typed: strict
# frozen_string_literal: true

module Formulary
  # Construct formula classes from API metadata without evaluating Ruby source.
  module FromAPI
    extend T::Helpers

    requires_ancestor { T.class_of(Formulary) }

    sig {
      params(
        name:           String,
        formula_struct: Homebrew::API::FormulaStruct,
        api_source:     T::Hash[String, T.untyped],
        tap_git_head:   String,
        flags:          T::Array[String],
        internal_api:   T::Boolean,
      ).returns(T.class_of(Formula))
    }
    def load_formula_from_struct!(name, formula_struct, api_source:, tap_git_head:, flags:, internal_api: false)
      namespace = :"FormulaNamespaceAPI#{namespace_key(api_source.to_json)}"

      mod = Module.new
      remove_const(namespace) if const_defined?(namespace)
      const_set(namespace, mod)

      mod.const_set(:BUILD_FLAGS, flags)

      class_name = class_s(name)
      ruby_source_path = "Formula/#{CoreTap.instance.new_formula_subdirectory(name)}/#{name.downcase}.rb"

      klass = Class.new(::Formula) do
        @loaded_from_api = T.let(true, T.nilable(T::Boolean))
        @loaded_from_internal_api = T.let(internal_api, T.nilable(T::Boolean))
        @api_source = T.let(api_source, T.nilable(T::Hash[String, T.untyped]))

        desc formula_struct.desc
        homepage formula_struct.homepage
        license formula_struct.license
        revision formula_struct.revision
        version_scheme formula_struct.version_scheme
        compatibility_version formula_struct.compatibility_version

        if formula_struct.stable?
          stable do
            url(*formula_struct.stable_url_args)
            version formula_struct.stable_version
            if (checksum = formula_struct.stable_checksum)
              sha256 checksum
            end

            formula_struct.stable_patches.each do |patch_hash|
              patch patch_hash.fetch("strip", patch_hash[:strip]).to_sym do
                T.bind(self, Resource::Patch)

                if (patch_url = patch_hash.fetch("url", patch_hash[:url]))
                  url patch_url
                  if (patch_sha256 = patch_hash.fetch("sha256", patch_hash[:sha256]))
                    sha256 patch_sha256
                  end
                  apply patch_hash.fetch("apply", patch_hash[:apply]) if patch_hash.fetch("apply", patch_hash[:apply])
                  if (patch_directory = patch_hash.fetch("directory", patch_hash[:directory]))
                    directory patch_directory
                  end
                elsif (patch_file = patch_hash.fetch("file", patch_hash[:file]))
                  file patch_file
                end

                if (patch_resolves = patch_hash.fetch("resolves", patch_hash[:resolves]))
                  resolves(*patch_resolves.map { |resolved| resolved.fetch("id", resolved[:id]) })
                end
              end
            end

            formula_struct.stable_dependencies.each do |dep|
              depends_on dep
            end

            formula_struct.stable_uses_from_macos.each do |args|
              uses_from_macos(*args)
            end
          end
        end

        if formula_struct.head?
          head do
            url(*formula_struct.head_url_args)

            formula_struct.head_dependencies.each do |dep|
              depends_on dep
            end

            formula_struct.head_uses_from_macos.each do |args|
              uses_from_macos(*args)
            end
          end
        end

        no_autobump!(**formula_struct.no_autobump_args) if formula_struct.no_autobump?

        if formula_struct.bottle?
          bottle do
            if Homebrew::EnvConfig.bottle_domain_custom?
              root_url Homebrew::EnvConfig.bottle_domain
            else
              root_url HOMEBREW_BOTTLE_DEFAULT_DOMAIN
            end
            rebuild formula_struct.bottle_rebuild
            formula_struct.bottle_checksums.each do |args|
              sha256(**args)
            end
          end
        end

        pour_bottle?(**formula_struct.pour_bottle_args) if formula_struct.pour_bottle?

        keg_only(*formula_struct.keg_only_args) if formula_struct.keg_only?

        deprecate!(**formula_struct.deprecate_args) if formula_struct.deprecate?
        disable!(**formula_struct.disable_args) if formula_struct.disable?

        formula_struct.conflicts.each do |name, args|
          conflicts_with(name, **args)
        end

        formula_struct.link_overwrite_paths.each do |path|
          link_overwrite path
        end

        @post_install_steps = T.let(
          formula_struct.post_install_steps,
          T.nilable(Homebrew::InstallSteps::Steps),
        )
        @post_install_steps_defined = T.let(formula_struct.post_install_steps.present?, T.nilable(T::Boolean))

        define_method(:install) do
          raise NotImplementedError, "Cannot build from source from abstract formula."
        end

        @post_install_defined_boolean = T.let(formula_struct.post_install_defined, T.nilable(T::Boolean))
        define_method(:post_install_defined?) do
          self.class.instance_variable_get(:@post_install_defined_boolean)
        end

        if formula_struct.service?
          service do
            run(*formula_struct.service_run_args, **formula_struct.service_run_kwargs) if formula_struct.service_run?
            name(**formula_struct.service_name_args) if formula_struct.service_name?

            formula_struct.service_args.each do |key, arg|
              public_send(key, arg)
            end
          end
        end

        @caveats_string = T.let(formula_struct.caveats, T.nilable(String))
        define_method(:caveats) do
          self.class.instance_variable_get(:@caveats_string)
        end

        @tap_git_head_string = T.let(tap_git_head, T.nilable(String))
        define_method(:tap_git_head) do
          self.class.instance_variable_get(:@tap_git_head_string)
        end

        @oldnames_array = T.let(formula_struct.oldnames, T.nilable(T::Array[String]))
        define_method(:oldnames) do
          self.class.instance_variable_get(:@oldnames_array)
        end

        @aliases_array = T.let(formula_struct.aliases, T.nilable(T::Array[String]))
        define_method(:aliases) do
          self.class.instance_variable_get(:@aliases_array)
        end

        @versioned_formulae_array = T.let(formula_struct.versioned_formulae, T.nilable(T::Array[String]))
        define_method(:versioned_formulae_names) do
          self.class.instance_variable_get(:@versioned_formulae_array)
        end

        @ruby_source_path_string = T.let(ruby_source_path, T.nilable(String))
        define_method(:ruby_source_path) do
          self.class.instance_variable_get(:@ruby_source_path_string)
        end

        @ruby_source_checksum_string = T.let(formula_struct.ruby_source_checksum, T.nilable(String))
        define_method(:ruby_source_checksum) do
          checksum = self.class.instance_variable_get(:@ruby_source_checksum_string)
          Checksum.new(checksum) if checksum
        end

        define_method(:local_patch_checksums) do
          formula_struct.local_patch_checksums
        end
      end

      mod.const_set(class_name, klass)

      platform_cache[:api] ||= {}
      platform_cache.fetch(:api)[name] = klass
    end
  end
end
