# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module InstallStepsHelper
      OFFICIAL_HOMEBREW_TAP_PATH_REGEX = %r{(?:\A|/)Taps/homebrew/homebrew-[\w-]+/}i
      FILE_PREPARATION_STEP_METHODS =
        [:mkdir, :mkdir_p, :touch, :move, :mv, :move_children, :move_contents, :copy, :remove, :inreplace,
         :symlink,
         :ln_s, :ln_sf].freeze
      LINK_STEP_METHODS = [:link_dir, :link_children, :symlink_tree, :symlink_children].freeze
      CONFIG_WRITE_STEP_METHODS = [:write, :write_file].freeze
      SERVICE_DATA_STEP_METHODS = [:init_data_dir].freeze
      REBUILD_ACTION_STEP_METHODS =
        [:compile_gsettings_schemas, :gio_querymodules, :update_gio_modules_cache, :gdk_pixbuf_query_loaders,
         :update_gdk_pixbuf_loaders_cache, :gtk_update_icon_cache, :update_gtk_icon_cache,
         :update_mime_database, :update_desktop_database].freeze
      KEYCHAIN_STEP_METHODS = [:delete_keychain_certificate, :delete_keychain_certificates].freeze
      PERMISSION_STEP_METHODS = [:set_permissions, :set_ownership].freeze
      COMMAND_STEP_METHODS = [:run, :terminate_process].freeze
      MACHO_STEP_METHODS = [:change_dylib_id].freeze
      NOTICE_STEP_METHODS = [:warn].freeze
      FORMULA_ACTION_STEP_METHODS =
        [:configure_gcc_runtime, :install_gzipped_executable, :configure_glibc_runtime,
         :configure_clang_system, :configure_php, :bootstrap_cpython, :bootstrap_pypy].freeze
      STEP_SCOPE_METHODS = [:if_path_exists, :unless_path_exists, :on_macos, :on_linux].freeze
      COMPATIBILITY_STEP_METHOD_REPLACEMENTS = T.let(
        {
          mkdir:                       :mkdir_p,
          mv:                          :move,
          move_children:               :move_contents,
          ln_s:                        :symlink,
          ln_sf:                       :symlink,
          link_dir:                    :symlink_tree,
          link_children:               :symlink_children,
          write:                       :write_file,
          gio_querymodules:            :update_gio_modules_cache,
          gdk_pixbuf_query_loaders:    :update_gdk_pixbuf_loaders_cache,
          gtk_update_icon_cache:       :update_gtk_icon_cache,
          delete_keychain_certificate: :delete_keychain_certificates,
        }.freeze,
        T::Hash[Symbol, Symbol],
      )
      COMPATIBILITY_STEP_METHODS = T.let(COMPATIBILITY_STEP_METHOD_REPLACEMENTS.keys.freeze, T::Array[Symbol])
      COMPATIBILITY_STEP_KEYWORD_REPLACEMENTS = T.let(
        {
          move:                         { force: :overwrite }.freeze,
          mv:                           { force: :overwrite }.freeze,
          symlink:                      { force: :overwrite, uninstall: :remove_on_uninstall }.freeze,
          ln_s:                         { force: :overwrite, uninstall: :remove_on_uninstall }.freeze,
          ln_sf:                        { uninstall: :remove_on_uninstall }.freeze,
          delete_keychain_certificate:  { matching_certificate: :fingerprint_of }.freeze,
          delete_keychain_certificates: { matching_certificate: :fingerprint_of }.freeze,
        }.freeze,
        T::Hash[Symbol, T::Hash[Symbol, Symbol]],
      )
      ALLOWED_STEP_METHODS = T.let(
        [*FILE_PREPARATION_STEP_METHODS, *LINK_STEP_METHODS, *CONFIG_WRITE_STEP_METHODS, *SERVICE_DATA_STEP_METHODS,
         *REBUILD_ACTION_STEP_METHODS, :set_permissions, *COMMAND_STEP_METHODS, *NOTICE_STEP_METHODS,
         *MACHO_STEP_METHODS, *FORMULA_ACTION_STEP_METHODS, *STEP_SCOPE_METHODS].freeze,
        T::Array[Symbol],
      )
      CASK_ALLOWED_STEP_METHODS = T.let(
        [*FILE_PREPARATION_STEP_METHODS, *CONFIG_WRITE_STEP_METHODS, *KEYCHAIN_STEP_METHODS,
         *PERMISSION_STEP_METHODS, *COMMAND_STEP_METHODS, *MACHO_STEP_METHODS, *STEP_SCOPE_METHODS].freeze,
        T::Array[Symbol],
      )

      # `dstr` covers heredocs such as `write` content; interpolation is limited
      # to known template values below.
      ALLOWED_STEP_ARGUMENT_NODE_TYPES = [:array, :dstr, :hash, :int, :nil, :pair, :regexp, :regopt, :str,
                                          :sym].freeze

      STEP_BLOCK_MSG = T.let(
        "Steps blocks may only contain install step DSL calls. Prefer canonical calls: " \
        "#{(ALLOWED_STEP_METHODS - COMPATIBILITY_STEP_METHODS).map { |method| "`#{method}`" }.join(", ")}.".freeze,
        String,
      )
      BREW_RUBY_STEP_MSG = "Install steps must not use `brew ruby` because it enables developer mode."
      LEGACY_STEP_METHOD_MSG = "Use `%<replacement>s` instead of legacy install step `%<method>s`."
      LEGACY_STEP_KEYWORD_MSG = "Use `%<replacement>s:` instead of legacy install step keyword `%<keyword>s:`."
      SIMPLE_STEP_CONVERSION_MSG = "Use `%<steps_block>s` for simple file preparation."
      REBUILD_ACTION_STEP_LINES = T.let(
        T.let([
          [
            "system Formula[\"glib\"].opt_bin/\"glib-compile-schemas\", " \
            "HOMEBREW_PREFIX/\"share/glib-2.0/schemas\"",
            "compile_gsettings_schemas",
          ],
          [
            "system Formula[\"gdk-pixbuf\"].opt_bin/\"gdk-pixbuf-query-loaders\", " \
            "\"--update-cache\"",
            "update_gdk_pixbuf_loaders_cache",
          ],
          [
            "system Formula[\"gtk+3\"].opt_bin/\"gtk3-update-icon-cache\", " \
            "\"-q\", \"-t\", \"-f\", HOMEBREW_PREFIX/\"share/icons/hicolor\"",
            "update_gtk_icon_cache",
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

      sig { params(file_path: String).returns(T::Boolean) }
      def official_homebrew_tap?(file_path)
        file_path.match?(OFFICIAL_HOMEBREW_TAP_PATH_REGEX)
      end

      sig { params(allowed_methods: T::Array[Symbol]).returns(String) }
      def step_block_msg(allowed_methods)
        "Steps blocks may only contain install step DSL calls. Prefer canonical calls: " \
          "#{(allowed_methods - COMPATIBILITY_STEP_METHODS).map { |method| "`#{method}`" }.join(", ")}."
      end

      sig {
        params(
          block_node:      RuboCop::AST::BlockNode,
          allowed_methods: T::Array[Symbol],
        ).void
      }
      def add_compatibility_step_offenses(block_node, allowed_methods: ALLOWED_STEP_METHODS)
        block_node.each_descendant(:send) do |node|
          send_node = T.cast(node, RuboCop::AST::SendNode)
          method = send_node.method_name
          next if send_node.receiver || !allowed_methods.include?(method)

          if (replacement = COMPATIBILITY_STEP_METHOD_REPLACEMENTS[method])
            add_offense(send_node.loc.selector,
                        message: Kernel.format(LEGACY_STEP_METHOD_MSG, method:, replacement:)) do |corrector|
              corrector.replace(send_node.loc.selector, replacement.to_s)
              add_compatibility_step_method_corrections(corrector, send_node)
            end
          end
          add_compatibility_step_keyword_offenses(send_node)
        end
      end

      class InstallStepPath < T::Struct
        const :path, String
        const :base, T.nilable(Symbol)
        const :source, T.nilable(String), default: nil
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
          offense_node = install_step_offense_node(node, allowed_methods)
          return offense_node if offense_node
        end

        nil
      end

      sig { params(block_node: T.nilable(RuboCop::AST::BlockNode)).returns(T.nilable(RuboCop::AST::Node)) }
      def brew_ruby_step_node(block_node)
        return if block_node.nil?

        block_node.each_descendant(:send).each do |node|
          send_node = T.cast(node, RuboCop::AST::SendNode)
          next if send_node.receiver.present? || send_node.method_name != :run

          command = send_node.first_argument
          next unless command&.str_type?
          next if command.str_content != "{{HOMEBREW_BREW_FILE}}"

          options = send_node.arguments.last
          next unless options&.hash_type?

          args = T.cast(options, RuboCop::AST::HashNode).pairs.find do |pair|
            pair.key.sym_type? && pair.key.value == :args
          end&.value
          next unless args&.array_type?

          first_arg = args.child_nodes.first
          return command if first_arg&.str_type? && first_arg.str_content == "ruby"
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
          permission_actions:  T::Boolean,
        ).returns(T.nilable(T::Array[String]))
      }
      def simple_install_step_lines(body_node, default_base:, default_source_base:, default_target_base:,
                                    rebuild_actions: true, permission_actions: false)
        return if body_node.nil?

        direct_nodes = body_node.begin_type? ? body_node.child_nodes : [body_node]
        step_lines = direct_nodes.map do |node|
          simple_install_step_line(node, default_base:, default_source_base:, default_target_base:, rebuild_actions:,
                                   permission_actions:)
        end
        return if step_lines.any?(&:nil?)

        T.cast(step_lines, T::Array[String])
      end

      sig { params(block_name: Symbol, step_lines: T::Array[String], indent: Integer).returns(String) }
      def install_steps_block_source(block_name, step_lines, indent)
        block_indent = " " * indent
        [
          "#{block_name} do",
          *indented_install_step_lines(step_lines, indent + 2),
          "#{block_indent}end",
        ].join("\n")
      end

      sig {
        params(
          corrector:  RuboCop::Cop::Corrector,
          block_node: RuboCop::AST::BlockNode,
          step_lines: T::Array[String],
        ).void
      }
      def append_install_step_lines(corrector, block_node, step_lines)
        block_indent = block_node.source_range.column
        step_source = indented_install_step_lines(step_lines, block_indent + 2).join("\n")
        corrector.insert_before(
          block_node.loc.end,
          "#{step_source.delete_prefix(" " * block_indent)}\n#{" " * block_indent}",
        )
      end

      sig { params(body_node: T.nilable(RuboCop::AST::Node)).returns(T::Array[RuboCop::AST::Node]) }
      def direct_install_step_nodes(body_node)
        return [] if body_node.nil?

        body_node.begin_type? ? body_node.child_nodes : [body_node]
      end

      sig { params(node: RuboCop::AST::Node).returns(String) }
      def normalised_install_step_source(node)
        node.source.lines.reject { |line| line.lstrip.start_with?("#") }.join.gsub(/\s+/, " ").strip
      end

      private

      sig { params(send_node: RuboCop::AST::SendNode).void }
      def add_compatibility_step_keyword_offenses(send_node)
        replacements = COMPATIBILITY_STEP_KEYWORD_REPLACEMENTS[send_node.method_name]
        return if replacements.nil?

        options = send_node.last_argument
        return unless options&.hash_type?

        options = T.cast(options, RuboCop::AST::HashNode)
        options.pairs.each do |pair|
          next unless pair.key.sym_type?
          next unless (replacement = replacements[pair.key.value])

          message = Kernel.format(LEGACY_STEP_KEYWORD_MSG, keyword: pair.key.value, replacement:)
          add_offense(pair.key.source_range, message:) do |corrector|
            correct_compatibility_step_keyword(corrector, send_node, options, pair, replacement)
          end
        end
      end

      sig {
        params(
          corrector:   RuboCop::Cop::Corrector,
          send_node:   RuboCop::AST::SendNode,
          options:     RuboCop::AST::HashNode,
          legacy_pair: RuboCop::AST::PairNode,
          replacement: Symbol,
        ).void
      }
      def correct_compatibility_step_keyword(corrector, send_node, options, legacy_pair, replacement)
        if replacement == :fingerprint_of
          corrector.replace(legacy_pair.key.source_range, replacement.to_s)
          return
        end
        return if !legacy_pair.value.true_type? && !legacy_pair.value.false_type?

        canonical_pair = options.pairs.find do |pair|
          pair != legacy_pair && pair.key.sym_type? && pair.key.value == replacement
        end
        if legacy_pair.value.true_type? && canonical_pair.nil?
          corrector.replace(legacy_pair.key.source_range, replacement.to_s)
          return
        end

        if legacy_pair.value.true_type? && canonical_pair && !canonical_pair.value.true_type?
          corrector.replace(canonical_pair.value.source_range, "true")
        end
        pairs = options.pairs
        index = pairs.index(legacy_pair)
        return if index.nil?

        range = if (next_pair = pairs[index + 1])
          legacy_pair.source_range.begin.join(next_pair.source_range.begin)
        elsif (previous_pair = pairs[index - 1]) && index.positive?
          previous_pair.source_range.end.join(legacy_pair.source_range.end)
        else
          send_node.arguments.fetch(-2).source_range.end.join(legacy_pair.source_range.end)
        end
        corrector.remove(range)
      end

      sig {
        params(
          corrector: RuboCop::Cop::Corrector,
          send_node: RuboCop::AST::SendNode,
        ).void
      }
      def add_compatibility_step_method_corrections(corrector, send_node)
        case send_node.method_name
        when :ln_sf
          add_step_keyword(corrector, send_node, "overwrite: true")
        when :write
          options = send_node.last_argument
          overwrite = options&.hash_type? && T.cast(options, RuboCop::AST::HashNode).pairs.any? do |pair|
            pair.key.sym_type? && pair.key.value == :overwrite
          end
          keyword = "append_newline: true"
          keyword = "overwrite: false, #{keyword}" unless overwrite
          add_step_keyword(corrector, send_node, keyword)
        end
      end

      sig {
        params(
          corrector: RuboCop::Cop::Corrector,
          send_node: RuboCop::AST::SendNode,
          keyword:   String,
        ).void
      }
      def add_step_keyword(corrector, send_node, keyword)
        options = send_node.last_argument
        if options&.hash_type?
          options = T.cast(options, RuboCop::AST::HashNode)
          if (pair = options.pairs.last)
            corrector.insert_after(pair.source_range, ", #{keyword}")
          else
            corrector.replace(options, keyword)
          end
        elsif (argument = send_node.last_argument)
          range = if argument.loc.respond_to?(:heredoc_end) && argument.loc.heredoc_end
            argument.loc.expression
          else
            argument.source_range
          end
          corrector.insert_after(range, ", #{keyword}")
        end
      end

      sig {
        params(
          node:            RuboCop::AST::Node,
          allowed_methods: T::Array[Symbol],
        ).returns(T.nilable(RuboCop::AST::Node))
      }
      def install_step_offense_node(node, allowed_methods)
        if node.block_type?
          block_node = T.cast(node, RuboCop::AST::BlockNode)
          send_node = block_node.send_node
          return node if send_node.receiver.present? || !STEP_SCOPE_METHODS.include?(send_node.method_name)
          return node unless allowed_methods.include?(send_node.method_name)

          invalid_argument = invalid_step_argument_node(send_node)
          return invalid_argument if invalid_argument

          direct_install_step_nodes(block_node.body).each do |child|
            offense_node = install_step_offense_node(child, allowed_methods)
            return offense_node if offense_node
          end
          return
        end
        return node unless node.send_type?

        send_node = T.cast(node, RuboCop::AST::SendNode)
        return node if send_node.receiver.present? || !allowed_methods.include?(send_node.method_name)
        return node if STEP_SCOPE_METHODS.include?(send_node.method_name)

        invalid_step_argument_node(send_node)
      end

      sig { params(send_node: RuboCop::AST::SendNode).returns(T.nilable(RuboCop::AST::Node)) }
      def invalid_step_argument_node(send_node)
        invalid_argument_node = send_node.each_descendant.find do |descendant|
          !allowed_step_argument_node?(descendant)
        end
        T.cast(invalid_argument_node, T.nilable(RuboCop::AST::Node))
      end

      sig { params(step_lines: T::Array[String], indent: Integer).returns(T::Array[String]) }
      def indented_install_step_lines(step_lines, indent)
        step_lines.flat_map do |step_line|
          if step_line.include?("<<~")
            ["#{" " * indent}#{step_line}"]
          else
            step_line.lines(chomp: true).map { |line| "#{" " * indent}#{line}" }
          end
        end
      end

      sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
      def allowed_step_argument_node?(node)
        return true if node.false_type? || node.true_type?
        return true if ALLOWED_STEP_ARGUMENT_NODE_TYPES.include?(node.type)

        allowed_step_template_node?(node)
      end

      sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
      def allowed_step_template_node?(node)
        if node.begin_type?
          return false if node.child_nodes.length != 1

          return allowed_step_template_node?(node.child_nodes.first)
        end
        return false unless node.send_type?

        send_node = T.cast(node, RuboCop::AST::SendNode)
        return false if send_node.arguments.present?
        return [:formula_name, :name, :token, :version].include?(send_node.method_name) if send_node.receiver.nil?

        return false unless (receiver = send_node.receiver)&.send_type?

        receiver_node = T.cast(receiver, RuboCop::AST::SendNode)
        return false if receiver_node.receiver.present?
        return false if receiver_node.arguments.present?
        return false if receiver_node.method_name != :version

        [:major, :major_minor].include?(send_node.method_name)
      end

      sig {
        params(
          node:                RuboCop::AST::Node,
          default_base:        Symbol,
          default_source_base: Symbol,
          default_target_base: Symbol,
          rebuild_actions:     T::Boolean,
          permission_actions:  T::Boolean,
        ).returns(T.nilable(String))
      }
      def simple_install_step_line(node, default_base:, default_source_base:, default_target_base:, rebuild_actions:,
                                   permission_actions:)
        return unless node.send_type?

        send_node = T.cast(node, RuboCop::AST::SendNode)
        if rebuild_actions && send_node.receiver.nil? && send_node.method_name == :system
          return REBUILD_ACTION_STEP_LINES[send_node.source.gsub(/\s+/, " ")]
        end

        if send_node.method_name == :mkpath && send_node.arguments.empty? && send_node.receiver
          path = install_step_path(send_node.receiver)
          return mkdir_step_line(path, default_base)
        end

        if [:write, :atomic_write].include?(send_node.method_name)
          if send_node.receiver&.const_type? && send_node.receiver&.const_name == "File"
            return if send_node.method_name != :write || send_node.arguments.length != 2

            return write_step_line(
              install_step_path(send_node.arguments.fetch(0)),
              send_node.arguments.fetch(1),
              default_base,
            )
          end

          return if send_node.receiver.nil? || send_node.arguments.length != 1

          return write_step_line(install_step_path(send_node.receiver), send_node.arguments.fetch(0), default_base)
        end

        if permission_actions && send_node.receiver.nil?
          case send_node.method_name
          when :set_permissions
            return set_permissions_step_line(send_node, default_base)
          when :set_ownership
            return set_ownership_step_line(send_node, default_base)
          end
        end

        return unless fileutils_or_no_receiver?(send_node)

        case send_node.method_name
        when :mkdir, :mkdir_p
          return if send_node.arguments.length != 1

          mkdir_step_line(install_step_path(send_node.arguments.first), default_base)
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

          symlink_step_line(send_node.method_name == :ln_sf,
                            install_step_path(send_node.arguments.fetch(0)),
                            install_step_path(send_node.arguments.fetch(1)),
                            default_source_base, default_target_base)
        end
      end

      sig {
        params(
          path:         T.nilable(InstallStepPath),
          default_base: Symbol,
        ).returns(T.nilable(String))
      }
      def mkdir_step_line(path, default_base)
        return if path.nil? || relative_install_step_path?(path)

        "mkdir_p #{install_step_path_source(path)}" \
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
        "move #{install_step_path_source(source)}, #{install_step_path_source(target)}#{install_step_kwargs(kwargs)}"
      end

      sig {
        params(
          overwrite:           T::Boolean,
          source:              T.nilable(InstallStepPath),
          target:              T.nilable(InstallStepPath),
          default_source_base: Symbol,
          default_target_base: Symbol,
        ).returns(T.nilable(String))
      }
      def symlink_step_line(overwrite, source, target, default_source_base, default_target_base)
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
          ("overwrite: true" if overwrite),
        ].compact
        "symlink #{install_step_path_source(source)}, #{install_step_path_source(target)}" \
          "#{install_step_kwargs(kwargs)}"
      end

      sig {
        params(
          path:         T.nilable(InstallStepPath),
          content_node: RuboCop::AST::Node,
          default_base: Symbol,
        ).returns(T.nilable(String))
      }
      def write_step_line(path, content_node, default_base)
        return if path.nil? || relative_install_step_path?(path)

        kwargs = [
          install_step_path_keyword(path, base: default_base, keyword: :base),
        ].compact
        return unless (content_source = write_content_source(content_node, kwargs))

        "write_file #{install_step_path_source(path)}, #{content_source}"
      end

      sig { params(content_node: RuboCop::AST::Node, kwargs: T::Array[String]).returns(T.nilable(String)) }
      def write_content_source(content_node, kwargs)
        return unless content_node.str_type?
        unless content_node.loc.respond_to?(:heredoc_end)
          return "#{content_node.source}#{install_step_kwargs(kwargs)}"
        end

        heredoc_end = content_node.loc.heredoc_end
        return "#{content_node.source}#{install_step_kwargs(kwargs)}" if heredoc_end.nil?

        "#{content_node.loc.expression.source}#{install_step_kwargs(kwargs)}" \
          "#{::Parser::Source::Range.new(content_node.loc.expression.source_buffer,
                                         content_node.loc.expression.end_pos, heredoc_end.end_pos).source}"
      end

      sig {
        params(
          send_node:    RuboCop::AST::SendNode,
          default_base: Symbol,
        ).returns(T.nilable(String))
      }
      def set_permissions_step_line(send_node, default_base)
        return if send_node.arguments.length != 2

        permissions_node = send_node.arguments.fetch(1)
        return unless permissions_node.str_type?
        return unless (paths = permission_paths_source(send_node.arguments.fetch(0), default_base))

        path_source, base = paths
        "set_permissions #{path_source}, #{permissions_node.source}" \
          "#{install_step_path_keywords_for_base(base, default_base)}"
      end

      sig {
        params(
          send_node:    RuboCop::AST::SendNode,
          default_base: Symbol,
        ).returns(T.nilable(String))
      }
      def set_ownership_step_line(send_node, default_base)
        return unless [1, 2].include?(send_node.arguments.length)
        return unless (paths = permission_paths_source(send_node.arguments.fetch(0), default_base))

        kwargs = T.let([], T::Array[String])
        if send_node.arguments.length == 2
          options = send_node.arguments.fetch(1)
          return unless options.hash_type?

          pairs = T.cast(options, RuboCop::AST::HashNode).pairs
          return if pairs.empty?
          return unless pairs.all? do |pair|
            pair.key.sym_type? && [:user, :group].include?(pair.key.value) && pair.value.str_type?
          end
          return if pairs.map { |pair| pair.key.value }.uniq.length != pairs.length

          kwargs.concat(pairs.map(&:source))
        end

        path_source, base = paths
        kwargs << "base: :#{base}" if base && base != default_base
        "set_ownership #{path_source}#{install_step_kwargs(kwargs)}"
      end

      sig {
        params(
          node:         RuboCop::AST::Node,
          default_base: Symbol,
        ).returns(T.nilable([String, T.nilable(Symbol)]))
      }
      def permission_paths_source(node, default_base)
        path_nodes = node.array_type? ? node.child_nodes : [node]
        return if path_nodes.empty?

        paths = path_nodes.filter_map { |path_node| cask_permission_path(path_node) }
        return if paths.length != path_nodes.length

        absolute_paths, relative_paths = paths.partition { |path| absolute_install_step_path?(path) }
        return if absolute_paths.present? && relative_paths.present?

        base = if relative_paths.present?
          bases = relative_paths.map { |path| path.base || default_base }.uniq
          return if bases.length != 1

          bases.fetch(0)
        end
        source = if node.array_type?
          "[#{paths.map { |path| install_step_path_source(path) }.join(", ")}]"
        else
          install_step_path_source(paths.fetch(0))
        end
        [source, base]
      end

      sig { params(node: RuboCop::AST::Node).returns(T.nilable(InstallStepPath)) }
      def cask_permission_path(node)
        path = install_step_path(node)
        return path if path
        if normalised_install_step_source(node) == "staged_path.to_s"
          return InstallStepPath.new(path: ".", base: :staged_path)
        end
        return unless node.dstr_type?

        dstr_permission_path(T.cast(node, RuboCop::AST::DstrNode))
      end

      sig { params(node: RuboCop::AST::DstrNode).returns(T.nilable(InstallStepPath)) }
      def dstr_permission_path(node)
        children = node.child_nodes
        return if children.empty?

        base = interpolated_path_base(children.first)
        children = children.drop(1) if base
        return if children.empty? || !children.first.str_type?

        first_content = T.cast(children.first, RuboCop::AST::StrNode).str_content
        if base
          return unless first_content.start_with?("/")

          first_content = first_content.delete_prefix("/")
        elsif !first_content.start_with?("/", "~/")
          return
        end

        path = +first_content
        source = +first_content.dump.delete_prefix('"').delete_suffix('"')
        valid_children = children.drop(1).all? do |child|
          if child.str_type?
            content = T.cast(child, RuboCop::AST::StrNode).str_content
            path << content
            source << content.dump.delete_prefix('"').delete_suffix('"')
            true
          elsif child.begin_type? && allowed_step_template_node?(child)
            interpolation = "\#{#{child.source}}"
            path << interpolation
            source << interpolation
            true
          else
            false
          end
        end
        return unless valid_children

        InstallStepPath.new(path:, base:, source: "\"#{source}\"")
      end

      sig { params(node: RuboCop::AST::Node).returns(T.nilable(Symbol)) }
      def interpolated_path_base(node)
        return unless node.begin_type?
        return if node.child_nodes.length != 1

        value = node.child_nodes.first
        return :homebrew_prefix if value.const_type? && value.const_name == "HOMEBREW_PREFIX"
        return unless value.send_type?

        send_node = T.cast(value, RuboCop::AST::SendNode)
        return if send_node.receiver || send_node.arguments.present?

        send_node.method_name if [:appdir, :staged_path].include?(send_node.method_name)
      end

      sig { params(base: T.nilable(Symbol), default_base: Symbol).returns(String) }
      def install_step_path_keywords_for_base(base, default_base)
        (base && base != default_base) ? ", base: :#{base}" : ""
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
        base if [:appdir, :etc, :home, :opt_prefix, :pkgetc, :prefix, :staged_path, :var].include?(base)
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
        path.source || path.path.inspect
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
