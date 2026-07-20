# typed: strict
# frozen_string_literal: true

require "simulate_system"
require "system_command"
require "utils/output"

module Homebrew
  # Declarative install steps that can be serialised through the JSON APIs.
  module InstallSteps
    PathSpec = T.type_alias { T::Hash[String, String] }
    PathSpecs = T.type_alias { T::Array[PathSpec] }
    StepValue = T.type_alias { T.any(String, Integer, T::Boolean, PathSpec, PathSpecs) }
    Step = T.type_alias { T::Hash[String, StepValue] }
    Steps = T.type_alias { T::Array[Step] }
    Paths = T.type_alias { T.any(String, Pathname, T::Array[T.any(String, Pathname)]) }
    RawPathSpec = T.type_alias { T::Hash[T.any(String, Symbol), T.nilable(T.any(String, Symbol, Pathname))] }
    RawPathSpecs = T.type_alias { T::Array[T.any(String, Symbol, Pathname, RawPathSpec)] }
    RawStepValue =
      T.type_alias { T.nilable(T.any(String, Symbol, Integer, T::Boolean, Pathname, RawPathSpec, RawPathSpecs)) }
    RawStep = T.type_alias { T::Hash[T.any(String, Symbol), RawStepValue] }
    SystemCommandArg = T.type_alias { T.any(String, Pathname) }
    TemplateTokenValue = T.type_alias { T.any(String, Pathname) }

    class DSL
      ((instance_methods + private_instance_methods) -
        (BasicObject.instance_methods + BasicObject.private_instance_methods) -
        [:__callee__, :__method__, :class, :object_id]).each { |method| undef_method method }

      class TemplateVersion
        sig { returns(String) }
        def to_s
          "{{version}}"
        end

        sig { returns(String) }
        def major
          "{{version.major}}"
        end

        sig { returns(String) }
        def major_minor
          "{{version.major_minor}}"
        end
      end
      private_constant :TemplateVersion

      TEMPLATE_VERSION = TemplateVersion.new.freeze
      private_constant :TEMPLATE_VERSION

      ABSOLUTE_TEMPLATE_TOKENS = %w[
        HOMEBREW_PREFIX HOMEBREW_CELLAR prefix opt_prefix bin sbin lib libexec share pkgshare var etc pkgetc
        staged_path appdir caskroom_path temp rack bash_completion zsh_completion fish_completion pwsh_completion
      ].freeze
      private_constant :ABSOLUTE_TEMPLATE_TOKENS

      PRESERVED_STEP_VALUE_KEYS = %w[after args before content env overwrite].freeze
      private_constant :PRESERVED_STEP_VALUE_KEYS

      sig {
        params(
          default_base:        ::T.nilable(::T.any(::String, ::Symbol)),
          default_source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          default_target_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).void
      }
      def initialize(default_base: nil, default_source_base: nil, default_target_base: nil)
        @default_base = default_base
        @default_source_base = default_source_base
        @default_target_base = default_target_base
        @steps = ::T.let([], Steps)
        @guards = ::T.let([], PathSpecs)
        @next_guard_id = ::T.let(0, ::Integer)
      end

      sig { returns(Steps) }
      attr_reader :steps

      # odeprecated
      sig { returns(String) }
      def name
        "{{name}}"
      end

      sig { returns(String) }
      def formula_name
        "{{formula_name}}"
      end

      sig { returns(String) }
      def token
        "{{token}}"
      end

      sig { returns(TemplateVersion) }
      def version
        TEMPLATE_VERSION
      end

      sig {
        params(
          default_base:        ::T.nilable(::T.any(::String, ::Symbol)),
          default_source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          default_target_base: ::T.nilable(::T.any(::String, ::Symbol)),
          block:               ::T.nilable(::T.proc.void),
        ).returns(Steps)
      }
      def self.build(default_base: nil, default_source_base: nil, default_target_base: nil, &block)
        dsl = new(default_base:, default_source_base:, default_target_base:)
        dsl.instance_eval(&block) if block
        dsl.steps
      end

      sig {
        params(
          path:  ::T.any(::String, ::Pathname),
          base:  ::T.nilable(::T.any(::String, ::Symbol)),
          block: ::T.proc.void,
        ).void
      }
      def if_path_exists(path, base: nil, &block)
        with_guard(path_spec(path, base:, default_base: @default_base).merge("condition" => "if_exists"), &block)
      end

      sig {
        params(
          path:  ::T.any(::String, ::Pathname),
          base:  ::T.nilable(::T.any(::String, ::Symbol)),
          block: ::T.proc.void,
        ).void
      }
      def unless_path_exists(path, base: nil, &block)
        with_guard(path_spec(path, base:, default_base: @default_base).merge("condition" => "unless_exists"), &block)
      end

      sig { params(block: ::T.proc.void).void }
      def on_macos(&block)
        with_guard({ "condition" => "on", "value" => "macos" }, &block)
      end

      sig { params(block: ::T.proc.void).void }
      def on_linux(&block)
        with_guard({ "condition" => "on", "value" => "linux" }, &block)
      end

      sig { params(steps: ::T::Array[RawStep]).returns(Steps) }
      def self.normalise_steps(steps)
        steps.map do |step|
          step = step.to_h do |key, value|
            key = key.to_s
            [key, normalise_step_value(key, value)]
          end
          compact_step(step)
        end
      end

      sig { params(step: ::T::Hash[String, ::T.nilable(StepValue)]).returns(Step) }
      def self.compact_step(step)
        compacted_step = ::T.cast(
          ::Utils.deep_compact_blank(step.except(*PRESERVED_STEP_VALUE_KEYS)) || {},
          Step,
        )
        PRESERVED_STEP_VALUE_KEYS.each do |key|
          value = step[key]
          next if value.nil?
          next if %w[args env].include?(key) && [[], {}].include?(value)

          compacted_step[key] = value
        end
        compacted_step
      end
      private_class_method :compact_step

      sig { params(key: String, obj: RawStepValue).returns(::T.nilable(StepValue)) }
      def self.normalise_step_value(key, obj)
        case obj
        when Symbol
          obj.to_s
        when Array
          obj.map { |value| normalise_path_value(value) } if %w[guards paths].include?(key)
        when Hash
          if key == "env"
            ::T.cast(obj.to_h { |env_key, value| [env_key.to_s, value&.to_s] }.compact, PathSpec)
          else
            normalise_path_value(obj)
          end
        when String, Pathname
          if %w[
            path source target command matching_certificate fingerprint_of stdin_path stdout_path chdir
          ].include?(key)
            normalise_path_value(obj)
          else
            obj.to_s
          end
        else
          obj
        end
      end
      private_class_method :normalise_step_value

      sig { params(obj: T.any(String, Symbol, Pathname, RawPathSpec)).returns(PathSpec) }
      def self.normalise_path_value(obj)
        case obj
        when Hash
          ::T.cast(obj.to_h { |key, value| [key.to_s, value&.to_s] }.compact_blank, PathSpec)
        else
          { "path" => obj.to_s }
        end
      end
      private_class_method :normalise_path_value

      # odeprecated
      sig { params(path: ::T.any(::String, ::Pathname), base: ::T.nilable(::T.any(::String, ::Symbol))).void }
      def mkdir(path, base: nil)
        add_step("mkdir", "path" => path_spec(path, base:, default_base: @default_base))
      end

      sig { params(path: ::T.any(::String, ::Pathname), base: ::T.nilable(::T.any(::String, ::Symbol))).void }
      def mkdir_p(path, base: nil)
        add_step("mkdir_p", "path" => path_spec(path, base:, default_base: @default_base))
      end

      sig { params(path: ::T.any(::String, ::Pathname), base: ::T.nilable(::T.any(::String, ::Symbol))).void }
      def touch(path, base: nil)
        add_step("touch", "path" => path_spec(path, base:, default_base: @default_base))
      end

      sig {
        params(
          source:      ::T.any(::String, ::Pathname),
          target:      ::T.any(::String, ::Pathname),
          source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          target_base: ::T.nilable(::T.any(::String, ::Symbol)),
          force:       ::T::Boolean,
          source_glob: ::T::Boolean,
        ).void
      }
      def move(source, target, source_base: nil, target_base: nil, force: false, source_glob: false)
        add_step("move",
                 "source"      => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target"      => path_spec(target, base: target_base, default_base: @default_target_base),
                 "force"       => force,
                 "source_glob" => source_glob)
      end

      alias mv move

      sig {
        params(
          source:      ::T.any(::String, ::Pathname),
          target:      ::T.any(::String, ::Pathname),
          source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          target_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).void
      }
      def move_children(source, target, source_base: nil, target_base: nil)
        add_step("move_children",
                 "source" => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target" => path_spec(target, base: target_base, default_base: @default_target_base))
      end

      sig {
        params(
          source:      ::T.any(::String, ::Pathname),
          target:      ::T.any(::String, ::Pathname),
          source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          target_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).void
      }
      def move_contents(source, target, source_base: nil, target_base: nil)
        add_step("move_contents",
                 "source" => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target" => path_spec(target, base: target_base, default_base: @default_target_base))
      end

      sig {
        params(
          source:      ::T.any(::String, ::Pathname),
          target:      ::T.any(::String, ::Pathname),
          source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          target_base: ::T.nilable(::T.any(::String, ::Symbol)),
          recursive:   ::T::Boolean,
          overwrite:   ::T::Boolean,
          source_glob: ::T::Boolean,
        ).void
      }
      def copy(source, target, source_base: nil, target_base: nil, recursive: false, overwrite: true,
               source_glob: false)
        add_step("copy",
                 "source"      => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target"      => path_spec(target, base: target_base, default_base: @default_target_base),
                 "recursive"   => recursive,
                 "overwrite"   => overwrite,
                 "source_glob" => source_glob)
      end

      sig {
        params(
          paths:                   Paths,
          base:                    ::T.nilable(::T.any(::String, ::Symbol)),
          recursive:               ::T::Boolean,
          sudo:                    ::T.any(::T::Boolean, ::Symbol),
          symlink_target_contains: ::T.nilable(::String),
          content_contains:        ::T.nilable(::String),
        ).void
      }
      def remove(paths, base: nil, recursive: false, sudo: false, symlink_target_contains: nil,
                 content_contains: nil)
        add_step("remove",
                 "paths"                   => path_specs(paths, base:, default_base: @default_base),
                 "recursive"               => recursive,
                 "sudo"                    => sudo.is_a?(::Symbol) ? sudo.to_s : sudo,
                 "symlink_target_contains" => symlink_target_contains,
                 "content_contains"        => content_contains)
      end

      sig {
        params(
          path:         ::T.any(::String, ::Pathname),
          before:       ::T.any(::String, ::Regexp),
          after:        ::String,
          base:         ::T.nilable(::T.any(::String, ::Symbol)),
          audit_result: ::T::Boolean,
          global:       ::T::Boolean,
        ).void
      }
      def inreplace(path, before, after, base: nil, audit_result: true, global: true)
        add_step("inreplace",
                 "path"           => path_spec(path, base:, default_base: @default_base),
                 "before"         => before.is_a?(::Regexp) ? before.source : before,
                 "after"          => after,
                 "regexp"         => before.is_a?(::Regexp),
                 "regexp_options" => (before.options if before.is_a?(::Regexp)),
                 "skip_audit"     => !audit_result,
                 "first_only"     => !global)
      end

      sig {
        params(
          source:         ::T.any(::String, ::Pathname),
          target:         ::T.any(::String, ::Pathname),
          source_base:    ::T.nilable(::T.any(::String, ::Symbol)),
          target_base:    ::T.nilable(::T.any(::String, ::Symbol)),
          source_formula: ::T.nilable(::String),
          target_formula: ::T.nilable(::String),
          force:          ::T::Boolean,
          uninstall:      ::T::Boolean,
          source_glob:    ::T::Boolean,
          sudo:           ::T.any(::T::Boolean, ::Symbol),
        ).void
      }
      def symlink(source, target, source_base: nil, target_base: nil, source_formula: nil, target_formula: nil,
                  force: false, uninstall: false, source_glob: false, sudo: false)
        add_step("symlink",
                 "source"      => path_spec(source, base: source_base, formula: source_formula,
                                           default_base: @default_source_base),
                 "target"      => path_spec(target, base: target_base, formula: target_formula,
                                           default_base: @default_target_base),
                 "force"       => force,
                 "uninstall"   => uninstall,
                 "source_glob" => source_glob,
                 "sudo"        => sudo.is_a?(::Symbol) ? sudo.to_s : sudo)
      end

      sig {
        params(
          source:         ::T.any(::String, ::Pathname),
          target:         ::T.any(::String, ::Pathname),
          source_base:    ::T.nilable(::T.any(::String, ::Symbol)),
          target_base:    ::T.nilable(::T.any(::String, ::Symbol)),
          source_formula: ::T.nilable(::String),
          target_formula: ::T.nilable(::String),
          force:          ::T::Boolean,
          uninstall:      ::T::Boolean,
        ).void
      }
      def ln_s(source, target, source_base: nil, target_base: nil, source_formula: nil, target_formula: nil,
               force: false, uninstall: false)
        symlink(source, target, source_base:, target_base:, source_formula:, target_formula:, force:, uninstall:)
      end

      sig {
        params(
          source:         ::T.any(::String, ::Pathname),
          target:         ::T.any(::String, ::Pathname),
          source_base:    ::T.nilable(::T.any(::String, ::Symbol)),
          target_base:    ::T.nilable(::T.any(::String, ::Symbol)),
          source_formula: ::T.nilable(::String),
          target_formula: ::T.nilable(::String),
          uninstall:      ::T::Boolean,
        ).void
      }
      def ln_sf(source, target, source_base: nil, target_base: nil, source_formula: nil, target_formula: nil,
                uninstall: false)
        symlink(source, target, source_base:, target_base:, source_formula:, target_formula:, force: true, uninstall:)
      end

      sig {
        params(
          source:      ::T.any(::String, ::Pathname),
          target:      ::T.any(::String, ::Pathname),
          source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          target_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).void
      }
      def link_dir(source, target, source_base: nil, target_base: :homebrew_prefix)
        add_step("link_dir",
                 "source" => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target" => path_spec(target, base: target_base, default_base: @default_target_base))
      end

      sig {
        params(
          source:      ::T.any(::String, ::Pathname),
          target:      ::T.nilable(::T.any(::String, ::Pathname)),
          source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          target_base: ::T.nilable(::T.any(::String, ::Symbol)),
          prefix:      ::String,
          suffix:      ::String,
        ).void
      }
      def link_children(source, target = nil, source_base: nil, target_base: :homebrew_prefix, prefix: "", suffix: "")
        add_step("link_children",
                 "source" => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target" => path_spec(target || source, base: target_base, default_base: @default_target_base),
                 "prefix" => prefix,
                 "suffix" => suffix)
      end

      sig {
        params(
          path:      ::T.any(::String, ::Pathname),
          content:   ::String,
          base:      ::T.nilable(::T.any(::String, ::Symbol)),
          overwrite: ::T::Boolean,
        ).void
      }
      def write(path, content, base: nil, overwrite: false)
        content = "#{content}\n" unless content.end_with?("\n")
        add_step("write",
                 "path"      => path_spec(path, base:, default_base: @default_base),
                 "content"   => content,
                 "overwrite" => overwrite)
      end

      sig {
        params(
          path:   ::T.any(::String, ::Pathname),
          using:  ::T.any(::String, ::Symbol),
          base:   ::T.nilable(::T.any(::String, ::Symbol)),
          locale: ::T.nilable(::String),
        ).void
      }
      def init_data_dir(path, using:, base: nil, locale: nil)
        add_step("init_data_dir",
                 "path"   => path_spec(path, base:, default_base: @default_base),
                 "using"  => using.to_s,
                 "locale" => locale)
      end

      sig { void }
      def compile_gsettings_schemas
        add_rebuild_action("compile_gsettings_schemas", "share/glib-2.0/schemas")
      end

      sig { void }
      def gio_querymodules
        add_rebuild_action("gio_querymodules", "lib/gio/modules")
      end

      sig { void }
      def gdk_pixbuf_query_loaders
        add_step("gdk_pixbuf_query_loaders")
      end

      sig { void }
      def gtk_update_icon_cache
        add_rebuild_action("gtk_update_icon_cache", "share/icons/hicolor")
      end

      sig { void }
      def update_mime_database
        add_rebuild_action("update_mime_database", "share/mime")
      end

      sig { void }
      def update_desktop_database
        add_rebuild_action("update_desktop_database", "share/applications")
      end

      sig {
        params(
          name:                 ::String,
          matching_certificate: ::T.nilable(::T.any(::String, ::Pathname)),
          base:                 ::T.nilable(::T.any(::String, ::Symbol)),
        ).void
      }
      def delete_keychain_certificate(name, matching_certificate: nil, base: nil)
        add_step("delete_keychain_certificate",
                 "name"                 => name,
                 "matching_certificate" => (path_spec(matching_certificate, base:, default_base: nil) if
                   matching_certificate))
      end

      sig {
        params(
          paths:       Paths,
          permissions: ::String,
          base:        ::T.nilable(::T.any(::String, ::Symbol)),
          recursive:   ::T::Boolean,
        ).void
      }
      def set_permissions(paths, permissions, base: nil, recursive: true)
        add_step("set_permissions",
                 "paths"         => path_specs(paths, base:, default_base: @default_base),
                 "permissions"   => permissions,
                 "non_recursive" => !recursive)
      end

      sig {
        params(
          paths:     Paths,
          user:      ::T.nilable(::String),
          group:     ::String,
          base:      ::T.nilable(::T.any(::String, ::Symbol)),
          recursive: ::T::Boolean,
        ).void
      }
      def set_ownership(paths, user: nil, group: "staff", base: nil, recursive: true)
        add_step("set_ownership",
                 "paths"         => path_specs(paths, base:, default_base: @default_base),
                 "user"          => user,
                 "group"         => group,
                 "non_recursive" => !recursive)
      end

      private

      sig { params(guard: PathSpec, block: ::T.proc.void).void }
      def with_guard(guard, &block)
        previous_guards = ::T.let(nil, ::T.nilable(PathSpecs))
        previous_guards = @guards
        @next_guard_id += 1
        @guards = [*@guards, guard.merge("id" => @next_guard_id.to_s)]
        instance_eval(&block)
      ensure
        @guards = previous_guards if previous_guards
      end

      sig { params(type: ::String, fields: ::T.nilable(StepValue)).void }
      def add_step(type, **fields)
        step = fields.transform_keys(&:to_s)
        step["guards"] = @guards unless @guards.empty?
        step["type"] = type
        @steps.concat(::Homebrew::InstallSteps::DSL.normalise_steps([step]))
      end

      sig { params(type: ::String, path: ::String).void }
      def add_rebuild_action(type, path)
        add_step(type, "path" => path_spec(path, base: :homebrew_prefix))
      end

      sig {
        params(
          path:         ::T.any(::String, ::Pathname),
          base:         ::T.nilable(::T.any(::String, ::Symbol)),
          formula:      ::T.nilable(::String),
          default_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).returns(PathSpec)
      }
      def path_spec(path, base:, formula: nil, default_base: nil)
        {
          "base"    => (base || default_base_for(path, default_base))&.to_s,
          "formula" => formula,
          "path"    => path.to_s,
        }.compact_blank
      end

      sig {
        params(
          paths:        Paths,
          base:         ::T.nilable(::T.any(::String, ::Symbol)),
          default_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).returns(PathSpecs)
      }
      def path_specs(paths, base:, default_base:)
        paths = [paths] unless paths.is_a?(Array)
        paths.map { |path| path_spec(path, base:, default_base:) }
      end

      sig {
        params(
          path:         ::T.nilable(::T.any(::String, ::Pathname)),
          default_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).returns(::T.nilable(PathSpec))
      }
      def optional_path_spec(path, default_base:)
        path_spec(path, base: nil, default_base:) if path
      end

      sig {
        params(
          path:         ::T.any(::String, ::Pathname),
          default_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).returns(::T.nilable(::T.any(::String, ::Symbol)))
      }
      def default_base_for(path, default_base)
        path = path.to_s
        return if path.start_with?("/", "~")
        return if ABSOLUTE_TEMPLATE_TOKENS.any? { |token| path.start_with?("{{#{token}}}") }

        default_base
      end
    end

    class Runner
      include SystemCommand::Mixin
      include ::Utils::Output::Mixin

      # Path tokens reuse the step base resolution; formula metadata tokens are
      # resolved separately. Anything else is left verbatim so literal braces in
      # templates are never rewritten.
      CONTENT_PATH_TOKENS = %w[
        prefix opt_prefix bin sbin lib libexec share pkgshare var etc pkgetc staged_path appdir caskroom_path
        temp rack
        bash_completion zsh_completion fish_completion pwsh_completion
      ].freeze

      sig { params(context: Object, command: T.class_of(SystemCommand)).void }
      def initialize(context:, command: SystemCommand)
        @context = context
        @command = command
        @guard_results = T.let({}, T::Hash[PathSpec, T::Boolean])
      end

      sig { params(steps: Steps, phase: Symbol).void }
      def run(steps, phase: :install)
        @guard_results.clear
        DSL.normalise_steps(steps).each do |step|
          if phase == :uninstall
            run_uninstall_step(step)
          else
            run_install_step(step)
          end
        end
      end

      private

      sig { params(step: Step).void }
      def run_install_step(step)
        return unless step_guards_match?(step)

        case step.fetch("type")
        when "mkdir"
          resolve_path(step_path(step, "path")).mkdir
        when "mkdir_p"
          resolve_path(step_path(step, "path")).mkpath
        when "init_data_dir"
          run_init_data_dir(step)
        when "touch"
          path = resolve_path(step_path(step, "path"))
          path.dirname.mkpath
          FileUtils.touch path
        when "move"
          source = resolve_step_source(step)
          target = resolve_path(step_path(step, "target"))
          target.dirname.mkpath
          FileUtils.mv source, target, force: step["force"] == true
        when "move_children", "move_contents"
          source = resolve_path(step_path(step, "source"))
          target = resolve_path(step_path(step, "target"))
          target.mkpath
          children = source.children.reject { |child| child == target }
          return if children.empty?

          FileUtils.mv children, target
        when "copy"
          source = resolve_step_source(step)
          target = resolve_path(step_path(step, "target"))
          target.dirname.mkpath
          destination = step_destination(source, target)
          overwrite = step["overwrite"] != false
          raise Errno::EEXIST, destination.to_s if destination.exist? && !overwrite

          if step["recursive"] == true
            FileUtils.cp_r source, target, remove_destination: overwrite
          else
            FileUtils.rm_f destination if overwrite && destination.symlink?
            FileUtils.cp source, target
          end
        when "remove"
          paths = step_paths(step, "paths").flat_map { |path| expand_path_glob(path) }
          if step.key?("symlink_target_contains")
            paths.select! do |path|
              path.symlink? && path.readlink.to_s.include?(step_string(step, "symlink_target_contains"))
            end
          end
          if step.key?("content_contains")
            paths.select! do |path|
              path.file? && path.readable? && path.read.include?(step_string(step, "content_contains"))
            end
          end
          paths.each do |path|
            if step["sudo"] == true || (step["sudo"] == "if_needed" && !path.dirname.writable?)
              require "cask/utils"
              ::Cask::Utils.gain_permissions_remove(path, command: @command)
            elsif step["recursive"] == true
              FileUtils.rm_rf path
            else
              FileUtils.rm_f path
            end
          end
        when "inreplace"
          require "utils/inreplace"

          path = resolve_path(step_path(step, "path"))
          before = expand_template_tokens(step_string(step, "before"))
          after = expand_template_tokens(step_string(step, "after"))
          regexp_options = T.cast(step["regexp_options"], T.nilable(Integer))
          before = Regexp.new(before, regexp_options || 0) if step["regexp"] == true
          Utils::Inreplace.inreplace(path, before, after,
                                     audit_result: step["skip_audit"] != true,
                                     global:       step["first_only"] != true)
        when "link_dir", "symlink_tree"
          source_dir = resolve_path(step_path(step, "source"))
          target_dir = resolve_path(step_path(step, "target"))
          source_dir.find do |source|
            link_target = target_dir/source.relative_path_from(source_dir)
            next if source.basename.to_s == ".DS_Store"
            next if link_target.directory? && !link_target.symlink?

            FileUtils.rm_f(link_target) if link_target.exist? || link_target.symlink?
            if source.symlink? || source.file?
              link_target.parent.install_symlink source
            elsif source.directory?
              link_target.mkpath
            end
          end
        when "link_children"
          target_dir = resolve_path(step_path(step, "target"))
          target_dir.mkpath
          link_prefix = expand_template_tokens(step["prefix"].to_s)
          link_suffix = expand_template_tokens(step["suffix"].to_s)
          resolve_path(step_path(step, "source")).each_child do |source|
            target_dir.install_symlink source => "#{link_prefix}#{source.basename}#{link_suffix}"
          end
        when "symlink"
          target = resolve_path(step_path(step, "target"))
          if step["source_glob"] == true
            sources = expand_path_glob(step_path(step, "source"))
            return if sources.empty?

            if sources.length > 1 || target.directory?
              target.mkpath
              sources.each { |source| create_symlink(source, target/source.basename, step) }
            else
              source = sources.first
              create_symlink(source, target, step) if source
            end
          else
            create_symlink(link_source(step_path(step, "source")), target, step)
          end
        when "write"
          content = T.cast(step["content"], T.nilable(String))
          raise ArgumentError, "install step write requires non-empty content" if content.blank?

          path = resolve_path(step_path(step, "path"))
          if step["overwrite"] == true || !path.exist?
            path.dirname.mkpath
            path.write(expand_template_tokens(content))
          end
        when "set_permissions"
          run_set_permissions(step)
        when "set_ownership"
          run_set_ownership(step)
        when "compile_gsettings_schemas"
          run_formula_tool("glib", "glib-compile-schemas", resolve_path(step_path(step, "path")))
        when "gio_querymodules"
          run_formula_tool("glib", "gio-querymodules", resolve_path(step_path(step, "path")))
        when "gdk_pixbuf_query_loaders"
          run_formula_tool("gdk-pixbuf", "gdk-pixbuf-query-loaders", "--update-cache")
        when "gtk_update_icon_cache"
          require "utils/path"
          if Utils::Path.formula_any_version_installed?("gtk4")
            run_formula_tool("gtk4", "gtk4-update-icon-cache", "-q", "-t", "-f",
                             resolve_path(step_path(step, "path")))
          else
            run_formula_tool("gtk+3", "gtk3-update-icon-cache", "-q", "-t", "-f",
                             resolve_path(step_path(step, "path")))
          end
        when "update_mime_database"
          run_formula_tool("shared-mime-info", "update-mime-database", resolve_path(step_path(step, "path")))
        when "update_desktop_database"
          run_formula_tool("desktop-file-utils", "update-desktop-database", resolve_path(step_path(step, "path")))
        when "delete_keychain_certificate"
          certificate_hash = nil
          if step.key?("matching_certificate")
            certificate = resolve_path(step_path(step, "matching_certificate"))
            return unless certificate.exist?

            certificate_hash = run_command_output("/usr/bin/openssl", "x509", "-fingerprint", "-sha256", "-noout",
                                                  "-in", certificate)
                               .lines
                               .first
                               .to_s
                               .split("=", 2)[1]
                               .to_s
                               .delete(":")
                               .strip
                               .upcase
            return if certificate_hash.blank?
          end

          certificate_hashes = run_command_output(
            "/usr/bin/security", "find-certificate", "-a", "-c", step_string(step, "name"), "-Z",
            sudo: true
          ).lines.filter_map { |line| line[/\ASHA-256 hash:\s*(\S+)/, 1]&.upcase }

          if certificate_hash
            run_command "/usr/bin/security", "delete-certificate", "-Z", certificate_hash, sudo: true if
              certificate_hashes.include?(certificate_hash)
          else
            certificate_hashes.each do |matching_certificate_hash|
              run_command "/usr/bin/security", "delete-certificate", "-Z", matching_certificate_hash, sudo: true
            end
          end
        else
          raise ArgumentError, "unknown install step: #{step.fetch("type")}"
        end
      end

      sig { params(step: Step).returns(T::Boolean) }
      def step_guards_match?(step)
        guards = T.cast(step["guards"], T.nilable(PathSpecs))
        guards.nil? || guards.all? { |guard| guard_matches?(guard) }
      end

      sig { params(guard: PathSpec).returns(T::Boolean) }
      def guard_matches?(guard)
        return @guard_results.fetch(guard) if @guard_results.key?(guard)

        matches = case guard.fetch("condition")
        when "if_exists"
          path_spec_exists?(guard)
        when "unless_exists"
          !path_spec_exists?(guard)
        when "on"
          case guard.fetch("value")
          when "macos" then Homebrew::SimulateSystem.simulating_or_running_on_macos?
          when "linux" then Homebrew::SimulateSystem.simulating_or_running_on_linux?
          else false
          end
        else
          false
        end
        @guard_results[guard] = matches
      end
      sig { params(source: SystemCommandArg, target: Pathname, step: Step).void }
      def create_symlink(source, target, step)
        target.dirname.mkpath
        if step["sudo"] == true || (step["sudo"] == "if_needed" && !target.dirname.writable?)
          args = ["-s"]
          args << "-f" if step["force"] == true
          @command.run!("/bin/ln", args: [*args, source, target], sudo: true)
        else
          FileUtils.rm_f target if step["force"] == true
          File.symlink source, target
        end
      end

      sig { params(step: Step).void }
      def run_set_permissions(step)
        paths = existing_step_paths(step)
        return if paths.empty?

        args = []
        args << "-R" if step["non_recursive"] != true
        @command.run!("chmod", args: [*args, "--", step_string(step, "permissions"), *paths], sudo: false)
      end

      sig { params(step: Step).void }
      def run_set_ownership(step)
        require "cask/quarantine"
        require "utils/user"

        paths = existing_step_paths(step)
        return if paths.empty?

        paths.each do |path|
          next if ::Cask::Quarantine.app_management_permissions_granted?(app: path, command: @command)

          raise ::Cask::CaskError, <<~EOS
            Cannot change the ownership of '#{path}' because your terminal does not have App Management permissions.
            macOS prevents modifying apps without these permissions, even when using `sudo`.
            To fix this, approve the permissions prompt (if one was just shown) or go to
            System Settings → Privacy & Security → App Management and add or enable your terminal.
            Then run this command again.
          EOS
        end

        ohai "Changing ownership of paths required by #{@context} with `sudo` (which may request your password)..."
        args = []
        args << "-R" if step["non_recursive"] != true
        @command.run!("chown", args: [*args, "--", "#{step["user"] || ::User.current}:#{step["group"] || "staff"}",
                                      *paths],
                               sudo: true)
      end

      sig { params(step: Step).void }
      def run_uninstall_step(step)
        return if step.fetch("type") != "symlink"
        return if step["uninstall"] != true

        target = resolve_path(step_path(step, "target"))
        return unless target.symlink?
        return if target.readlink != Pathname(link_source(step_path(step, "source")))

        if step["sudo"] == true || (step["sudo"] == "if_needed" && !target.dirname.writable?)
          require "cask/utils"
          ::Cask::Utils.gain_permissions_remove(target, command: @command)
        else
          FileUtils.rm_f target
        end
      end

      sig { params(step: Step).void }
      def run_init_data_dir(step)
        using = step_string(step, "using")
        marker = case using
        when "postgresql_initdb"
          "PG_VERSION"
        when "mysql_initialize"
          "mysql/general_log.CSM"
        when "mariadb_install_db"
          "mysql/user.frm"
        else
          raise ArgumentError, "unknown data directory initialiser: #{using}"
        end

        path = resolve_path(step_path(step, "path"))
        path.mkpath
        return if ENV["HOMEBREW_GITHUB_ACTIONS"].present?
        return if (path/marker).exist?

        bin = context_path("bin")
        prefix = context_path("prefix")
        case using
        when "postgresql_initdb"
          run_command bin/"initdb", "--locale=#{step["locale"] || "en_US.UTF-8"}", "-E", "UTF-8", path
        when "mysql_initialize"
          with_env(TMPDIR: nil) do
            run_command bin/"mysqld", "--initialize-insecure", "--user=#{ENV.fetch("USER")}",
                        "--basedir=#{prefix}", "--datadir=#{path}", "--tmpdir=/tmp"
          end
        when "mariadb_install_db"
          with_env(TMPDIR: nil) do
            run_command bin/"mysql_install_db", "--verbose", "--user=#{ENV.fetch("USER")}",
                        "--basedir=#{prefix}", "--datadir=#{path}", "--tmpdir=/tmp"
          end
        end
      end

      sig { params(content: String).returns(String) }
      def expand_template_tokens(content)
        content.gsub(/\{\{([A-Za-z_][\w.]*)\}\}/) do |match|
          value = template_token_value(T.must(Regexp.last_match(1)))
          value.nil? ? match : value.to_s
        end
      end

      sig { params(token: String).returns(T.nilable(TemplateTokenValue)) }
      def template_token_value(token)
        case token
        when "HOMEBREW_BREW_FILE"
          HOMEBREW_BREW_FILE
        when "HOMEBREW_CELLAR"
          HOMEBREW_CELLAR
        when "HOMEBREW_PREFIX"
          HOMEBREW_PREFIX
        when "formula_name"
          context_value(:name)&.to_s
        when "name"
          context_name
        when "token"
          context_value(:token)&.to_s
        when "user"
          ENV.fetch("USER")
        when "version"
          context_version
        when "version.major"
          context_version_major
        when "version.major_minor"
          context_version_major_minor
        else
          root_path(token, nil) if CONTENT_PATH_TOKENS.include?(token)
        end
      end

      sig { params(step: Step, key: String).returns(PathSpec) }
      def step_path(step, key)
        T.cast(step.fetch(key), PathSpec)
      end

      sig { params(step: Step, key: String).returns(PathSpecs) }
      def step_paths(step, key)
        T.cast(step.fetch(key), PathSpecs)
      end

      sig { params(step: Step).returns(T::Array[Pathname]) }
      def existing_step_paths(step)
        step_paths(step, "paths").flat_map { |spec| expand_path_glob(spec) }.select(&:exist?)
      end

      sig { params(step: Step).returns(Pathname) }
      def resolve_step_source(step)
        source = resolve_path(step_path(step, "source"))
        return source if step["source_glob"] != true

        sources = Pathname.glob(source.to_s)
        raise ArgumentError, "install step source glob must match exactly one path: #{source}" if sources.length != 1

        sources.fetch(0)
      end

      sig { params(source: Pathname, target: Pathname).returns(Pathname) }
      def step_destination(source, target)
        target.directory? ? target/source.basename : target
      end

      sig { params(spec: PathSpec).returns(T::Array[Pathname]) }
      def expand_path_glob(spec)
        if spec["base"] == "path"
          path = expand_template_tokens(spec.fetch("path"))
          return ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).flat_map do |directory|
            candidate = Pathname(directory)/path
            candidate.to_s.match?(/[?*\[{]/) ? Pathname.glob(candidate.to_s) : [candidate]
          end
        end

        path = resolve_path(spec).expand_path
        return [path] unless path.to_s.match?(/[?*\[{]/)

        Pathname.glob(path.to_s)
      end

      sig { params(spec: PathSpec).returns(T::Boolean) }
      def path_spec_exists?(spec)
        expand_path_glob(spec).any?(&:exist?)
      end

      sig { params(step: Step, key: String).returns(String) }
      def step_string(step, key)
        T.cast(step.fetch(key), String)
      end

      sig { returns(T.nilable(String)) }
      def context_name
        value = context_value(:name) || context_value(:token)
        value&.to_s
      end

      sig { returns(T.nilable(String)) }
      def context_version
        context_value(:version)&.to_s
      end

      sig { returns(T.nilable(String)) }
      def context_version_major
        context_version_value = context_version
        return if context_version_value.blank?

        Version.new(context_version_value).major&.to_s
      end

      sig { returns(T.nilable(String)) }
      def context_version_major_minor
        context_version_value = context_version
        return if context_version_value.blank?

        Version.new(context_version_value).major_minor.to_s
      end

      sig { params(spec: PathSpec).returns(Pathname) }
      def resolve_path(spec)
        path = Pathname(expand_template_tokens(spec.fetch("path")))
        base = spec["base"]

        return path.expand_path if base.blank? || base == "absolute"
        return path if base == "relative"

        root_path(base, spec["formula"])/path
      end

      sig { params(spec: PathSpec).returns(String) }
      def link_source(spec)
        return expand_template_tokens(spec.fetch("path")) if spec["base"] == "relative"

        resolve_path(spec).to_s
      end

      sig { params(formula: String, executable: String, args: SystemCommandArg).void }
      def run_formula_tool(formula, executable, *args)
        # Load the formula so missing helper formulae fail before running a guessed path.
        # rubocop:disable Homebrew/FormulaPathMethods
        run_command Formula[formula].opt_bin/executable, *args
        # rubocop:enable Homebrew/FormulaPathMethods
      end

      sig { params(base: String, formula: T.nilable(String)).returns(Pathname) }
      def root_path(base, formula)
        case base
        when "home"
          Pathname(Dir.home)
        when "temp"
          HOMEBREW_TEMP
        when "homebrew_prefix"
          HOMEBREW_PREFIX
        when "formula_pkgetc"
          formula_base(formula, :pkgetc)
        when "formula_opt_prefix"
          formula_base(formula, :opt_prefix)
        else
          context_path(base)
        end
      end

      sig { params(base: String).returns(Pathname) }
      def context_path(base)
        method = base.to_sym
        value = context_value(method) || context_config_value(method)
        raise ArgumentError, "unknown install step base: #{base}" if value.nil?

        Pathname(value.to_s)
      end

      sig { params(formula: T.nilable(String), method: Symbol).returns(Pathname) }
      def formula_base(formula, method)
        raise ArgumentError, "missing formula for install step base" if formula.blank?

        case method
        when :pkgetc
          ::Formula[formula].pkgetc
        when :opt_prefix
          Utils::Path.formula_opt_prefix(formula)
        else
          raise ArgumentError, "unknown formula install step base: #{method}"
        end
      end

      sig { params(method: Symbol).returns(T.nilable(Object)) }
      def context_value(method)
        @context.public_send(method) if @context.respond_to?(method)
      end

      sig { params(method: Symbol).returns(T.nilable(Object)) }
      def context_config_value(method)
        config = context_value(:config)
        config.public_send(method) if config.respond_to?(method)
      end

      sig { params(command: SystemCommandArg, args: SystemCommandArg, sudo: T::Boolean).void }
      def run_command(command, *args, sudo: false)
        @command.run!(command, args: args, sudo:, print_stdout: true, print_stderr: true, reset_uid: true)
      end

      sig { params(command: SystemCommandArg, args: SystemCommandArg, sudo: T::Boolean).returns(String) }
      def run_command_output(command, *args, sudo: false)
        @command.run!(command, args: args, sudo:, print_stderr: true, reset_uid: true).stdout
      end
    end
  end
end
