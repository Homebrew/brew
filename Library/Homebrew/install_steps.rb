# typed: strict
# frozen_string_literal: true

module Homebrew
  # Declarative install steps that can be serialised through the JSON APIs.
  module InstallSteps
    Step = T.type_alias { T::Hash[String, T.untyped] }
    Steps = T.type_alias { T::Array[Step] }

    class DSL
      ((instance_methods + private_instance_methods) -
        (BasicObject.instance_methods + BasicObject.private_instance_methods) -
        [:__callee__, :__method__, :class, :object_id]).each { |method| undef_method method }

      sig {
        params(
          default_base:        ::T.nilable(::T.any(::String, ::Symbol)),
          default_source_base: ::T.nilable(::T.any(::String, ::Symbol)),
          default_target_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).void
      }
      def initialize(default_base: nil, default_source_base: nil, default_target_base: nil)
        @default_base = ::T.let(default_base, ::T.nilable(::T.any(::String, ::Symbol)))
        @default_source_base = ::T.let(default_source_base, ::T.nilable(::T.any(::String, ::Symbol)))
        @default_target_base = ::T.let(default_target_base, ::T.nilable(::T.any(::String, ::Symbol)))
        @steps = ::T.let([], Steps)
      end

      sig { returns(Steps) }
      attr_reader :steps

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

      sig { params(steps: ::T::Array[::T.untyped]).returns(Steps) }
      def self.normalise_steps(steps)
        steps.map do |step|
          ::T.cast(normalise_step_value(step), Step)
        end
      end

      sig { params(obj: ::T.untyped).returns(::T.untyped) }
      def self.normalise_step_value(obj)
        case obj
        when Symbol
          obj.to_s
        when Hash
          obj.to_h { |key, value| [key.to_s, normalise_step_value(value)] }
        when Array
          obj.map { |value| normalise_step_value(value) }
        else
          obj
        end
      end
      private_class_method :normalise_step_value

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
        ).void
      }
      def move(source, target, source_base: nil, target_base: nil, force: false)
        add_step("move",
                 "source" => path_spec(source, base: source_base, default_base: @default_source_base),
                 "target" => path_spec(target, base: target_base, default_base: @default_target_base),
                 "force"  => force)
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
      def symlink(source, target, source_base: nil, target_base: nil, source_formula: nil, target_formula: nil,
                  force: false, uninstall: false)
        add_step("symlink",
                 "source"    => path_spec(source, base: source_base, formula: source_formula,
                                           default_base: @default_source_base),
                 "target"    => path_spec(target, base: target_base, formula: target_formula,
                                           default_base: @default_target_base),
                 "force"     => force,
                 "uninstall" => uninstall)
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

      private

      sig { params(type: ::String, fields: ::T.untyped).void }
      def add_step(type, **fields)
        step = fields.transform_keys(&:to_s)
        step["type"] = type
        @steps << ::T.cast(::Utils.deep_compact_blank(step), Step)
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
        ).returns(Step)
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
          path:         ::T.any(::String, ::Pathname),
          default_base: ::T.nilable(::T.any(::String, ::Symbol)),
        ).returns(::T.nilable(::T.any(::String, ::Symbol)))
      }
      def default_base_for(path, default_base)
        path = path.to_s
        return if path.start_with?("/", "~")

        default_base
      end
    end

    class Runner
      # Path tokens reuse the step base resolution; `HOMEBREW_PREFIX`, `version`
      # and `version.major_minor` are resolved separately. Anything else is left
      # verbatim so literal braces in templates are never rewritten.
      CONTENT_PATH_TOKENS = T.let(
        %w[prefix opt_prefix bin var etc pkgetc staged_path appdir].freeze,
        T::Array[String],
      )

      sig { params(context: T.untyped).void }
      def initialize(context:)
        @context = context
      end

      sig { params(steps: Steps, phase: Symbol).void }
      def run(steps, phase: :install)
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
        case step.fetch("type")
        when "mkdir"
          resolve_path(step.fetch("path")).mkdir
        when "mkdir_p"
          resolve_path(step.fetch("path")).mkpath
        when "touch"
          path = resolve_path(step.fetch("path"))
          path.dirname.mkpath
          FileUtils.touch path
        when "move"
          source = resolve_path(step.fetch("source"))
          target = resolve_path(step.fetch("target"))
          target.dirname.mkpath
          FileUtils.mv source, target, force: step["force"] == true
        when "move_children"
          source = resolve_path(step.fetch("source"))
          target = resolve_path(step.fetch("target"))
          target.mkpath
          children = source.children.reject { |child| child == target }
          return if children.empty?

          FileUtils.mv children, target
        when "symlink"
          target = resolve_path(step.fetch("target"))
          target.dirname.mkpath
          FileUtils.rm_f target if step["force"] == true
          File.symlink link_source(step.fetch("source")), target
        when "write"
          content = step["content"]
          raise ArgumentError, "install step write requires non-empty content" if content.blank?

          path = resolve_path(step.fetch("path"))
          if step["overwrite"] == true || !path.exist?
            path.dirname.mkpath
            path.write(expand_content_tokens(content))
          end
        when "compile_gsettings_schemas"
          run_formula_tool("glib", "glib-compile-schemas", resolve_path(step.fetch("path")))
        when "gio_querymodules"
          run_formula_tool("glib", "gio-querymodules", resolve_path(step.fetch("path")))
        when "gdk_pixbuf_query_loaders"
          run_formula_tool("gdk-pixbuf", "gdk-pixbuf-query-loaders", "--update-cache")
        when "gtk_update_icon_cache"
          run_formula_tool("gtk+3", "gtk3-update-icon-cache", "-q", "-t", "-f", resolve_path(step.fetch("path")))
        when "update_mime_database"
          run_formula_tool("shared-mime-info", "update-mime-database", resolve_path(step.fetch("path")))
        when "update_desktop_database"
          run_formula_tool("desktop-file-utils", "update-desktop-database", resolve_path(step.fetch("path")))
        else
          raise ArgumentError, "unknown install step: #{step.fetch("type")}"
        end
      end

      sig { params(step: Step).void }
      def run_uninstall_step(step)
        return if step.fetch("type") != "symlink"
        return if step["uninstall"] != true

        target = resolve_path(step.fetch("target"))
        FileUtils.rm_f target if target.symlink?
      end

      sig { params(content: String).returns(String) }
      def expand_content_tokens(content)
        content.gsub(/\{\{([A-Za-z_][\w.]*)\}\}/) do |match|
          value = content_token_value(T.must(Regexp.last_match(1)))
          value.nil? ? match : value.to_s
        end
      end

      sig { params(token: String).returns(T.untyped) }
      def content_token_value(token)
        case token
        when "HOMEBREW_PREFIX"
          HOMEBREW_PREFIX
        when "version"
          context_version
        when "version.major_minor"
          context_version&.major_minor
        else
          root_path(token, nil) if CONTENT_PATH_TOKENS.include?(token)
        end
      end

      sig { returns(T.untyped) }
      def context_version
        @context.version if @context.respond_to?(:version)
      end

      sig { params(spec: T.untyped).returns(Pathname) }
      def resolve_path(spec)
        path_spec = normalise_path_spec(spec)
        path = Pathname(path_spec.fetch("path"))
        base = path_spec["base"]

        return path.expand_path if base.blank? || base == "absolute"
        return path if base == "relative"

        root_path(base, path_spec["formula"])/path
      end

      sig { params(spec: T.untyped).returns(String) }
      def link_source(spec)
        path_spec = normalise_path_spec(spec)
        return path_spec.fetch("path") if path_spec["base"] == "relative"

        resolve_path(path_spec).to_s
      end

      sig { params(spec: T.untyped).returns(Step) }
      def normalise_path_spec(spec)
        case spec
        when Hash
          T.cast(Utils.deep_stringify_symbols(spec), Step)
        else
          { "path" => spec.to_s }
        end
      end

      sig { params(formula: String, executable: String, args: T.untyped).void }
      def run_formula_tool(formula, executable, *args)
        @context.send(:safe_system, Formula[formula].opt_bin/executable, *args)
      end

      sig { params(base: String, formula: T.nilable(String)).returns(Pathname) }
      def root_path(base, formula)
        case base
        when "home"
          Pathname(Dir.home)
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
        if @context.respond_to?(method)
          Pathname(T.unsafe(@context).public_send(method))
        elsif @context.respond_to?(:config) && T.unsafe(@context.config).respond_to?(method)
          Pathname(T.unsafe(@context.config).public_send(method))
        else
          raise ArgumentError, "unknown install step base: #{base}"
        end
      end

      sig { params(formula: T.nilable(String), method: Symbol).returns(Pathname) }
      def formula_base(formula, method)
        raise ArgumentError, "missing formula for install step base" if formula.blank?

        Pathname(T.unsafe(::Formula[formula]).public_send(method))
      end
    end
  end
end
