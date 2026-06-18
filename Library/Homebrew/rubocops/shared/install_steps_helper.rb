# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module InstallStepsHelper
      FILE_PREPARATION_STEP_METHODS = T.let(
        [:mkdir, :mkdir_p, :touch, :move, :mv, :move_children, :symlink, :ln_s, :ln_sf].freeze,
        T::Array[Symbol],
      )
      CONFIG_WRITE_STEP_METHODS = T.let(
        [:write].freeze,
        T::Array[Symbol],
      )
      REBUILD_ACTION_STEP_METHODS = T.let(
        [:compile_gsettings_schemas, :gio_querymodules, :gdk_pixbuf_query_loaders, :gtk_update_icon_cache,
         :update_mime_database, :update_desktop_database].freeze,
        T::Array[Symbol],
      )
      ALLOWED_STEP_METHODS = T.let(
        [*FILE_PREPARATION_STEP_METHODS, *CONFIG_WRITE_STEP_METHODS, *REBUILD_ACTION_STEP_METHODS].freeze,
        T::Array[Symbol],
      )
      CASK_ALLOWED_STEP_METHODS = T.let(
        [*FILE_PREPARATION_STEP_METHODS, *CONFIG_WRITE_STEP_METHODS].freeze,
        T::Array[Symbol],
      )

      # `dstr` covers non-interpolated heredocs such as `write` content; any
      # interpolation adds `begin`/`send` descendants that remain disallowed.
      ALLOWED_STEP_ARGUMENT_NODE_TYPES = T.let(
        [:array, :dstr, :hash, :nil, :pair, :str, :sym].freeze,
        T::Array[Symbol],
      )

      STEP_BLOCK_MSG = T.let(
        "Steps blocks may only contain install step DSL calls: " \
        "#{ALLOWED_STEP_METHODS.map { |method| "`#{method}`" }.join(", ")}.".freeze,
        String,
      )
      SIMPLE_STEP_CONVERSION_MSG = T.let("Use `%<steps_block>s` for simple file preparation.", String)
      REBUILD_ACTION_STEP_LINES = T.let(
        T.let([
          [
            "system Formula[\"glib\"].opt_bin/\"glib-compile-schemas\", " \
            "HOMEBREW_PREFIX/\"share/glib-2.0/schemas\"",
            "compile_gsettings_schemas",
          ],
          [
            "system Formula[\"glib\"].opt_bin/\"gio-querymodules\", " \
            "HOMEBREW_PREFIX/\"lib/gio/modules\"",
            "gio_querymodules",
          ],
          [
            "system Formula[\"gdk-pixbuf\"].opt_bin/\"gdk-pixbuf-query-loaders\", " \
            "\"--update-cache\"",
            "gdk_pixbuf_query_loaders",
          ],
          [
            "system Formula[\"gtk+3\"].opt_bin/\"gtk3-update-icon-cache\", " \
            "\"-q\", \"-t\", \"-f\", HOMEBREW_PREFIX/\"share/icons/hicolor\"",
            "gtk_update_icon_cache",
          ],
          [
            "system Formula[\"shared-mime-info\"].opt_bin/\"update-mime-database\", " \
            "HOMEBREW_PREFIX/\"share/mime\"",
            "update_mime_database",
          ],
          [
            "system Formula[\"desktop-file-utils\"].opt_bin/\"update-desktop-database\", " \
            "HOMEBREW_PREFIX/\"share/applications\"",
            "update_desktop_database",
          ],
        ], T::Array[[String, String]]).to_h.freeze,
        T::Hash[String, String],
      )

      sig { params(allowed_methods: T::Array[Symbol]).returns(String) }
      def step_block_msg(allowed_methods)
        "Steps blocks may only contain install step DSL calls: " \
          "#{allowed_methods.map { |method| "`#{method}`" }.join(", ")}."
      end

      class InstallStepPath < T::Struct
        const :path, String
        const :base, T.nilable(Symbol)
      end

      sig {
        params(
          block_node:      T.nilable(RuboCop::AST::BlockNode),
          allowed_methods: T::Array[Symbol],
        ).returns(T.nilable(RuboCop::AST::Node))
      }
      def install_step_block_offense_node(block_node, allowed_methods: ALLOWED_STEP_METHODS)
        return if block_node.nil?
        return if (body = block_node.body).nil?

        direct_nodes = body.begin_type? ? body.child_nodes : [body]
        direct_nodes.each do |node|
          return node unless node.send_type?

          send_node = T.cast(node, RuboCop::AST::SendNode)
          return node if send_node.receiver.present? || !allowed_methods.include?(send_node.method_name)

          invalid_argument_node = send_node.each_descendant.find do |descendant|
            next false if descendant.false_type? || descendant.true_type?

            !ALLOWED_STEP_ARGUMENT_NODE_TYPES.include?(descendant.type)
          end
          return T.cast(invalid_argument_node, RuboCop::AST::Node) if invalid_argument_node
        end

        nil
      end

      sig {
        params(
          body_node:           T.nilable(RuboCop::AST::Node),
          default_base:        Symbol,
          default_source_base: Symbol,
          default_target_base: Symbol,
          rebuild_actions:     T::Boolean,
        ).returns(T.nilable(T::Array[String]))
      }
      def simple_install_step_lines(body_node, default_base:, default_source_base:, default_target_base:,
                                    rebuild_actions: true)
        return if body_node.nil?

        direct_nodes = body_node.begin_type? ? body_node.child_nodes : [body_node]
        step_lines = direct_nodes.map do |node|
          simple_install_step_line(node, default_base:, default_source_base:, default_target_base:, rebuild_actions:)
        end
        return if step_lines.any?(&:nil?)

        T.cast(step_lines, T::Array[String])
      end

      sig { params(block_name: Symbol, step_lines: T::Array[String], indent: Integer).returns(String) }
      def install_steps_block_source(block_name, step_lines, indent)
        block_indent = " " * indent
        step_indent = " " * (indent + 2)
        [
          "#{block_name} do",
          *step_lines.map { |step_line| "#{step_indent}#{step_line}" },
          "#{block_indent}end",
        ].join("\n")
      end

      private

      sig {
        params(
          node:                RuboCop::AST::Node,
          default_base:        Symbol,
          default_source_base: Symbol,
          default_target_base: Symbol,
          rebuild_actions:     T::Boolean,
        ).returns(T.nilable(String))
      }
      def simple_install_step_line(node, default_base:, default_source_base:, default_target_base:, rebuild_actions:)
        return unless node.send_type?

        send_node = T.cast(node, RuboCop::AST::SendNode)
        if rebuild_actions && send_node.receiver.nil? && send_node.method_name == :system
          return REBUILD_ACTION_STEP_LINES[send_node.source.gsub(/\s+/, " ")]
        end

        if send_node.method_name == :mkpath && send_node.arguments.empty? && send_node.receiver
          path = install_step_path(send_node.receiver)
          return mkdir_step_line(:mkdir_p, path, default_base)
        end

        return unless fileutils_or_no_receiver?(send_node)

        case send_node.method_name
        when :mkdir, :mkdir_p
          return if send_node.arguments.length != 1

          mkdir_step_line(send_node.method_name, install_step_path(send_node.arguments.first), default_base)
        when :touch
          return if send_node.arguments.length != 1

          touch_step_line(install_step_path(send_node.arguments.first), default_base)
        when :mv
          return if send_node.arguments.length != 2

          move_step_line(install_step_path(send_node.arguments.fetch(0)),
                         install_step_path(send_node.arguments.fetch(1)),
                         default_source_base, default_target_base)
        when :ln_s, :ln_sf
          return if send_node.arguments.length != 2

          symlink_step_line(send_node.method_name,
                            install_step_path(send_node.arguments.fetch(0)),
                            install_step_path(send_node.arguments.fetch(1)),
                            default_source_base, default_target_base)
        end
      end

      sig {
        params(
          method_name:  Symbol,
          path:         T.nilable(InstallStepPath),
          default_base: Symbol,
        ).returns(T.nilable(String))
      }
      def mkdir_step_line(method_name, path, default_base)
        return if path.nil? || relative_install_step_path?(path)

        "mkdir#{"_p" if method_name == :mkdir_p} #{install_step_path_source(path)}" \
          "#{install_step_path_keywords(path, base: default_base, keyword: :base)}"
      end

      sig {
        params(
          path:         T.nilable(InstallStepPath),
          default_base: Symbol,
        ).returns(T.nilable(String))
      }
      def touch_step_line(path, default_base)
        return if path.nil? || relative_install_step_path?(path)

        "touch #{install_step_path_source(path)}#{install_step_path_keywords(path, base:    default_base,
                                                                                   keyword: :base)}"
      end

      sig {
        params(
          source:              T.nilable(InstallStepPath),
          target:              T.nilable(InstallStepPath),
          default_source_base: Symbol,
          default_target_base: Symbol,
        ).returns(T.nilable(String))
      }
      def move_step_line(source, target, default_source_base, default_target_base)
        return if source.nil? || target.nil?
        return if relative_install_step_path?(source) || relative_install_step_path?(target)

        kwargs = [
          install_step_path_keyword(source, base: default_source_base, keyword: :source_base),
          install_step_path_keyword(target, base: default_target_base, keyword: :target_base),
        ].compact
        "mv #{install_step_path_source(source)}, #{install_step_path_source(target)}#{install_step_kwargs(kwargs)}"
      end

      sig {
        params(
          method_name:         Symbol,
          source:              T.nilable(InstallStepPath),
          target:              T.nilable(InstallStepPath),
          default_source_base: Symbol,
          default_target_base: Symbol,
        ).returns(T.nilable(String))
      }
      def symlink_step_line(method_name, source, target, default_source_base, default_target_base)
        return if source.nil? || target.nil?
        return if relative_install_step_path?(target)

        source_keyword = if relative_install_step_path?(source)
          "source_base: :relative"
        else
          install_step_path_keyword(source, base: default_source_base, keyword: :source_base)
        end
        kwargs = [
          source_keyword,
          install_step_path_keyword(target, base: default_target_base, keyword: :target_base),
        ].compact
        "#{method_name} #{install_step_path_source(source)}, #{install_step_path_source(target)}" \
          "#{install_step_kwargs(kwargs)}"
      end

      sig { params(send_node: RuboCop::AST::SendNode).returns(T::Boolean) }
      def fileutils_or_no_receiver?(send_node)
        receiver = send_node.receiver
        receiver.nil? || (receiver.const_type? && receiver.const_name == "FileUtils")
      end

      sig { params(node: T.nilable(RuboCop::AST::Node)).returns(T.nilable(InstallStepPath)) }
      def install_step_path(node)
        return if node.nil?
        return install_step_path(node.child_nodes.first) if node.begin_type? && node.child_nodes.length == 1

        return InstallStepPath.new(path: T.cast(node, RuboCop::AST::StrNode).str_content, base: nil) if node.str_type?
        return unless node.send_type?

        send_node = T.cast(node, RuboCop::AST::SendNode)
        return if send_node.method_name != :/ || send_node.arguments.length != 1

        path_node = send_node.arguments.first
        return unless path_node&.str_type?
        return unless (base = install_step_path_base(send_node.receiver))

        InstallStepPath.new(path: T.cast(path_node, RuboCop::AST::StrNode).str_content, base:)
      end

      sig { params(node: T.nilable(RuboCop::AST::Node)).returns(T.nilable(Symbol)) }
      def install_step_path_base(node)
        return if node.nil?
        return :homebrew_prefix if node.const_type? && node.const_name == "HOMEBREW_PREFIX"
        return unless node.send_type?

        send_node = T.cast(node, RuboCop::AST::SendNode)
        return if send_node.receiver

        base = send_node.method_name
        base if [:etc, :home, :opt_prefix, :pkgetc, :prefix, :staged_path, :var].include?(base)
      end

      sig { params(path: InstallStepPath).returns(T::Boolean) }
      def relative_install_step_path?(path)
        path.base.nil? && !absolute_install_step_path?(path)
      end

      sig { params(path: InstallStepPath).returns(T::Boolean) }
      def absolute_install_step_path?(path)
        path.path.start_with?("/", "~/")
      end

      sig { params(path: InstallStepPath).returns(String) }
      def install_step_path_source(path)
        path.path.inspect
      end

      sig { params(path: InstallStepPath, base: Symbol, keyword: Symbol).returns(String) }
      def install_step_path_keywords(path, base:, keyword:)
        keyword_source = install_step_path_keyword(path, base:, keyword:)
        keyword_source ? ", #{keyword_source}" : ""
      end

      sig { params(path: InstallStepPath, base: Symbol, keyword: Symbol).returns(T.nilable(String)) }
      def install_step_path_keyword(path, base:, keyword:)
        return if path.base.nil? || path.base == base

        "#{keyword}: :#{path.base}"
      end

      sig { params(kwargs: T::Array[String]).returns(String) }
      def install_step_kwargs(kwargs)
        kwargs.empty? ? "" : ", #{kwargs.join(", ")}"
      end
    end
  end
end
