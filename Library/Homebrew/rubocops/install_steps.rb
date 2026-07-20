# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/install_steps_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks declarative install step usage.
      class InstallSteps < FormulaCop
        extend AutoCorrector
        include InstallStepsHelper

        # TODO: Re-enable when formula `post_install` and `post_install_steps`
        # cannot coexist after the incremental conversion bridge is removed.
        # CONFLICT_MSG = "`post_install` and `post_install_steps` cannot both be used."
        POST_INSTALL_STEPS_ORDER_MSG = "`post_install_steps` must appear before `post_install` to match run order."
        REDUNDANT_SERVICE_PATH_DIRS_MSG = "`%<block>s` only creates directories created by `brew services`."
        CERTIFICATE_REMOVE_SOURCE = 'rm(pkgetc/"cert.pem") if (pkgetc/"cert.pem").exist?'
        CERTIFICATE_INSTALL_SYMLINK_SOURCE =
          'pkgetc.install_symlink Formula["ca-certificates"].pkgetc/"cert.pem"'
        GITHUB_ACTIONS_GUARD_SOURCE = "return if ENV[\"HOMEBREW_GITHUB_ACTIONS\"]"
        MYSQL_FORMULA_CLASS_REGEX = /\AMysql(?:AT\d+)?\z/
        MYSQL_DATADIR_METHOD_SOURCE = "def datadir var/\"mysql\" end"
        MYSQL_INITIALISE_SOURCE = T.let(
          <<~'RUBY'.gsub(/\s+/, " ").strip.freeze,
            unless (datadir/"mysql/general_log.CSM").exist?
              ENV["TMPDIR"] = nil
              system bin/"mysqld", "--initialize-insecure", "--user=#{ENV["USER"]}",
                                   "--basedir=#{prefix}", "--datadir=#{datadir}", "--tmpdir=/tmp"
            end
          RUBY
          String,
        )
        MARIADB_INITIALISE_SOURCE = T.let(
          <<~'RUBY'.gsub(/\s+/, " ").strip.freeze,
            unless File.exist? "#{var}/mysql/mysql/user.frm"
              ENV["TMPDIR"] = nil
              system bin/"mysql_install_db", "--verbose", "--user=#{ENV["USER"]}",
                "--basedir=#{prefix}", "--datadir=#{var}/mysql", "--tmpdir=/tmp"
            end
          RUBY
          String,
        )
        POSTGRESQL_DATADIR_METHOD_SOURCE = "def postgresql_datadir var/name end"
        POSTGRESQL_MARKER_METHOD_SOURCE = "def pg_version_exists? (postgresql_datadir/\"PG_VERSION\").exist? end"
        POSTGRESQL_INIT_SOURCE_REGEX = Regexp.new(
          '\Asystem bin/"initdb", "--locale=(C|en_US\\.UTF-8)", "-E", "UTF-8", ' \
          'postgresql_datadir unless pg_version_exists\\?\\z',
        ).freeze
        POSTGRESQL_LINK_DIR_SOURCE = T.let(
          <<~RUBY.gsub(/\s+/, " ").strip.freeze,
            %w[include lib share].each do |dir|
              dst_dir = HOMEBREW_PREFIX/dir/name
              src_dir = prefix/dir/"postgresql"
              src_dir.find do |src|
                dst = dst_dir/src.relative_path_from(src_dir)
                next if dst.directory? && !dst.symlink? && src.directory? && !src.symlink?

                rm_r(dst) if dst.exist? || dst.symlink?
                if src.symlink? || src.file?
                  Find.prune if src.basename.to_s == ".DS_Store"
                  dst.parent.install_symlink src
                elsif src.directory?
                  dst.mkpath
                end
              end
            end
          RUBY
          String,
        )
        POSTGRESQL_LINK_CHILDREN_SOURCE =
          "bin.each_child { |f| (HOMEBREW_PREFIX/\"bin\").install_symlink " \
          "f => \"\#{f.basename}-\#{version.major}\" }"

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          service_path_dirs = service_path_dirs(find_block(body_node, :service))
          post_install_steps_block = find_block(body_node, :post_install_steps)
          post_install_method = find_method_def(body_node, :post_install)

          # TODO: Re-enable when formula `post_install` and
          # `post_install_steps` cannot coexist after the incremental
          # conversion bridge is removed.
          # if post_install_steps_block && post_install_method
          #   offending_node(post_install_steps_block)
          #   problem CONFLICT_MSG
          # end

          add_post_install_steps_order_offense(post_install_steps_block, post_install_method)
          audit_step_block(post_install_steps_block)
          add_redundant_service_path_dirs_offense(post_install_steps_block, service_path_dirs, :post_install_steps)
          redundant_post_install = post_install_method.present? &&
                                   redundant_service_path_dirs_block?(post_install_method, service_path_dirs,
                                                                      :post_install)
          add_redundant_service_path_dirs_offense(post_install_method, service_path_dirs, :post_install)
          return if redundant_post_install

          audit_post_install_method(post_install_method, post_install_steps_block,
                                    body_node, formula_nodes.class_node.const_name)
        end

        private

        sig {
          params(
            post_install_steps_block: T.nilable(RuboCop::AST::BlockNode),
            post_install_method:      T.nilable(RuboCop::AST::Node),
          ).void
        }
        def add_post_install_steps_order_offense(post_install_steps_block, post_install_method)
          return if post_install_steps_block.nil? || post_install_method.nil?
          return if post_install_steps_block.loc.line < post_install_method.loc.line

          offending_node(post_install_steps_block)
          problem POST_INSTALL_STEPS_ORDER_MSG
        end

        sig { params(block_node: T.nilable(RuboCop::AST::BlockNode)).void }
        def audit_step_block(block_node)
          return unless (offense_node = install_step_block_offense_node(block_node))

          offending_node(offense_node)
          problem STEP_BLOCK_MSG
        end

        sig {
          params(
            post_install_method:      T.nilable(RuboCop::AST::Node),
            post_install_steps_block: T.nilable(RuboCop::AST::BlockNode),
            formula_body:             RuboCop::AST::Node,
            formula_class:            String,
          ).void
        }
        def audit_post_install_method(post_install_method, post_install_steps_block, formula_body, formula_class)
          return if post_install_method.nil?
          return unless post_install_method.def_type?

          post_install_def = T.cast(post_install_method, RuboCop::AST::DefNode)
          return if post_install_steps_block && post_install_steps_block.loc.line > post_install_def.loc.line

          step_nodes = T.let({}, T::Hash[RuboCop::AST::Node, T::Array[String]])
          removable_methods = T.let([], T::Array[RuboCop::AST::Node])
          direct_nodes = direct_install_step_nodes(post_install_def.body)
          add_postgresql_step_nodes(direct_nodes, formula_body, step_nodes, removable_methods)
          if formula_class.match?(MYSQL_FORMULA_CLASS_REGEX)
            add_mysql_step_nodes(direct_nodes, formula_body, step_nodes)
          end
          add_mariadb_step_nodes(direct_nodes, step_nodes)
          add_postgresql_link_step_nodes(direct_nodes, step_nodes)
          add_certificate_symlink_step_nodes(direct_nodes, step_nodes)
          unless step_nodes.empty?
            add_formula_step_conversion_offense(post_install_def, post_install_steps_block, direct_nodes, step_nodes,
                                                removable_methods)
            return
          end

          return if post_install_steps_block

          step_lines = simple_install_step_lines(post_install_def.body,
                                                 default_base:        :var,
                                                 default_source_base: :prefix,
                                                 default_target_base: :prefix)
          return if step_lines.blank?

          add_offense(post_install_method,
                      message: format(SIMPLE_STEP_CONVERSION_MSG, steps_block: "post_install_steps")) do |corrector|
            corrector.replace(
              post_install_method.source_range,
              install_steps_block_source(:post_install_steps, step_lines, post_install_method.source_range.column),
            )
          end
        end

        sig {
          params(
            direct_nodes:      T::Array[RuboCop::AST::Node],
            formula_body:      RuboCop::AST::Node,
            step_nodes:        T::Hash[RuboCop::AST::Node, T::Array[String]],
            removable_methods: T::Array[RuboCop::AST::Node],
          ).void
        }
        def add_postgresql_step_nodes(direct_nodes, formula_body, step_nodes, removable_methods)
          log_node = direct_nodes.find { |node| normalised_install_step_source(node) == '(var/"log").mkpath' }
          datadir_node = direct_nodes.find do |node|
            normalised_install_step_source(node) == "postgresql_datadir.mkpath"
          end
          guard_node = direct_nodes.find do |node|
            normalised_install_step_source(node) == GITHUB_ACTIONS_GUARD_SOURCE
          end
          init_node = direct_nodes.find do |node|
            normalised_install_step_source(node).match?(POSTGRESQL_INIT_SOURCE_REGEX)
          end
          return if log_node.nil? || datadir_node.nil? || guard_node.nil? || init_node.nil?
          return unless nodes_in_source_order?([log_node, datadir_node, guard_node, init_node])

          datadir_method = find_method_def(formula_body, :postgresql_datadir)
          marker_method = find_method_def(formula_body, :pg_version_exists?)
          return if datadir_method.nil? || marker_method.nil?
          return if normalised_install_step_source(datadir_method) != POSTGRESQL_DATADIR_METHOD_SOURCE
          return if normalised_install_step_source(marker_method) != POSTGRESQL_MARKER_METHOD_SOURCE

          match = normalised_install_step_source(init_node).match(POSTGRESQL_INIT_SOURCE_REGEX)
          return if match.nil?

          locale = match[1]
          step_nodes[log_node] = ["mkdir_p \"log\""]
          step_nodes[datadir_node] = []
          step_nodes[guard_node] = []
          init_step_line = "init_data_dir formula_name, using: :postgresql"
          init_step_line += ', locale: "C"' if locale == "C"
          step_nodes[init_node] = [init_step_line]
          pg_version_calls = formula_body.each_descendant(:send).count do |node|
            T.cast(node, RuboCop::AST::SendNode).method_name == :pg_version_exists?
          end
          removable_methods << marker_method if pg_version_calls == 1
        end

        sig {
          params(
            direct_nodes: T::Array[RuboCop::AST::Node],
            formula_body: RuboCop::AST::Node,
            step_nodes:   T::Hash[RuboCop::AST::Node, T::Array[String]],
          ).void
        }
        def add_mysql_step_nodes(direct_nodes, formula_body, step_nodes)
          datadir_method = find_method_def(formula_body, :datadir)
          return if datadir_method.nil?
          return if normalised_install_step_source(datadir_method) != MYSQL_DATADIR_METHOD_SOURCE

          add_mysql_data_step_nodes(direct_nodes, step_nodes, MYSQL_INITIALISE_SOURCE, :mysql)
        end

        sig {
          params(
            direct_nodes: T::Array[RuboCop::AST::Node],
            step_nodes:   T::Hash[RuboCop::AST::Node, T::Array[String]],
          ).void
        }
        def add_mariadb_step_nodes(direct_nodes, step_nodes)
          add_mysql_data_step_nodes(direct_nodes, step_nodes, MARIADB_INITIALISE_SOURCE, :mariadb)
        end

        sig {
          params(
            direct_nodes:      T::Array[RuboCop::AST::Node],
            step_nodes:        T::Hash[RuboCop::AST::Node, T::Array[String]],
            initialise_source: String,
            using:             Symbol,
          ).void
        }
        def add_mysql_data_step_nodes(direct_nodes, step_nodes, initialise_source, using)
          datadir_node = direct_nodes.find { |node| normalised_install_step_source(node) == '(var/"mysql").mkpath' }
          guard_node = direct_nodes.find do |node|
            normalised_install_step_source(node) == GITHUB_ACTIONS_GUARD_SOURCE
          end
          init_node = direct_nodes.find do |node|
            normalised_install_step_source(node) == initialise_source
          end
          return if datadir_node.nil? || guard_node.nil? || init_node.nil?
          return unless nodes_in_source_order?([datadir_node, guard_node, init_node])

          step_nodes[datadir_node] = []
          step_nodes[guard_node] = []
          step_nodes[init_node] = ["init_data_dir \"mysql\", using: :#{using}"]
        end

        sig {
          params(
            direct_nodes: T::Array[RuboCop::AST::Node],
            step_nodes:   T::Hash[RuboCop::AST::Node, T::Array[String]],
          ).void
        }
        def add_postgresql_link_step_nodes(direct_nodes, step_nodes)
          direct_nodes.each do |node|
            case normalised_install_step_source(node)
            when POSTGRESQL_LINK_DIR_SOURCE
              step_nodes[node] = [
                "symlink_tree \"include/postgresql\", \"include/\#{formula_name}\"",
                "symlink_tree \"lib/postgresql\", \"lib/\#{formula_name}\"",
                "symlink_tree \"share/postgresql\", \"share/\#{formula_name}\"",
              ]
            when POSTGRESQL_LINK_CHILDREN_SOURCE
              step_nodes[node] = ["symlink_children \"bin\", suffix: \"-\#{version.major}\""]
            end
          end
        end

        sig {
          params(
            direct_nodes: T::Array[RuboCop::AST::Node],
            step_nodes:   T::Hash[RuboCop::AST::Node, T::Array[String]],
          ).void
        }
        def add_certificate_symlink_step_nodes(direct_nodes, step_nodes)
          (0...(direct_nodes.length - 1)).each do |index|
            remove_node = direct_nodes.fetch(index)
            symlink_node = direct_nodes.fetch(index + 1)
            next if normalised_install_step_source(remove_node) != CERTIFICATE_REMOVE_SOURCE
            next if normalised_install_step_source(symlink_node) != CERTIFICATE_INSTALL_SYMLINK_SOURCE

            step_nodes[remove_node] = []
            step_nodes[symlink_node] = [<<~RUBY.chomp]
              symlink "cert.pem", "cert.pem",
                      source_formula: "ca-certificates",
                      source_base: :formula_pkgetc,
                      target_base: :pkgetc,
                      overwrite: true
            RUBY
          end
        end

        sig { params(nodes: T::Array[RuboCop::AST::Node]).returns(T::Boolean) }
        def nodes_in_source_order?(nodes)
          nodes.each_index.all? do |index|
            index.zero? || nodes.fetch(index - 1).source_range.begin_pos < nodes.fetch(index).source_range.begin_pos
          end
        end

        sig {
          params(
            post_install_def:         RuboCop::AST::DefNode,
            post_install_steps_block: T.nilable(RuboCop::AST::BlockNode),
            direct_nodes:             T::Array[RuboCop::AST::Node],
            step_nodes:               T::Hash[RuboCop::AST::Node, T::Array[String]],
            removable_methods:        T::Array[RuboCop::AST::Node],
          ).void
        }
        def add_formula_step_conversion_offense(post_install_def, post_install_steps_block, direct_nodes, step_nodes,
                                                removable_methods)
          step_lines = step_nodes.sort_by { |node, _| node.source_range.begin_pos }.flat_map(&:last)
          remaining_nodes = direct_nodes.reject { |node| step_nodes.key?(node) }
          add_offense(post_install_def,
                      message: format(SIMPLE_STEP_CONVERSION_MSG, steps_block: "post_install_steps")) do |corrector|
            if post_install_steps_block
              append_install_step_lines(corrector, post_install_steps_block, step_lines)
            elsif remaining_nodes.empty?
              corrector.replace(
                post_install_def.source_range,
                install_steps_block_source(:post_install_steps, step_lines, post_install_def.source_range.column),
              )
            else
              corrector.insert_before(
                post_install_def.source_range,
                "#{install_steps_block_source(:post_install_steps, step_lines,
                                              post_install_def.source_range.column)}\n\n" \
                "#{" " * post_install_def.source_range.column}",
              )
            end

            if post_install_steps_block || remaining_nodes.present?
              matched_install_step_node_groups(direct_nodes, step_nodes).each do |nodes|
                corrector.remove(range_for_install_step_node_group(nodes))
              end
              if remaining_nodes.empty?
                corrector.remove(range_with_surrounding_space(range: post_install_def.source_range, side: :left))
              end
            end
            removable_methods.each do |method|
              corrector.remove(range_with_surrounding_space(range: method.source_range, side: :left))
            end
          end
        end

        sig {
          params(
            direct_nodes: T::Array[RuboCop::AST::Node],
            step_nodes:   T::Hash[RuboCop::AST::Node, T::Array[String]],
          ).returns(T::Array[T::Array[RuboCop::AST::Node]])
        }
        def matched_install_step_node_groups(direct_nodes, step_nodes)
          direct_nodes.chunk_while { |left, right| step_nodes.key?(left) && step_nodes.key?(right) }
                      .select { |nodes| step_nodes.key?(nodes.fetch(0)) }
        end

        sig { params(nodes: T::Array[RuboCop::AST::Node]).returns(::Parser::Source::Range) }
        def range_for_install_step_node_group(nodes)
          first_range = range_by_whole_lines(nodes.fetch(0).source_range)
          last_range = range_by_whole_lines(nodes.fetch(-1).source_range, include_final_newline: true)
          range = ::Parser::Source::Range.new(processed_source.buffer, first_range.begin_pos, last_range.end_pos)
          prefix = processed_source.buffer.source[...range.begin_pos]
          preceding_blank_lines = prefix[/\n(?:[ \t]*\n)+\z/].to_s.length
          preceding_blank_lines -= 1 if preceding_blank_lines.positive?
          blank_lines = processed_source.buffer.source[range.end_pos..].to_s[/\A(?:[ \t]*\n)*/].to_s
          range.adjust(begin_pos: -preceding_blank_lines, end_pos: blank_lines.length)
        end

        sig {
          params(
            node:              T.nilable(RuboCop::AST::Node),
            service_path_dirs: T::Array[InstallStepPath],
            block_name:        Symbol,
          ).void
        }
        def add_redundant_service_path_dirs_offense(node, service_path_dirs, block_name)
          return if node.nil? || service_path_dirs.empty?
          return unless redundant_service_path_dirs_block?(node, service_path_dirs, block_name)

          add_offense(node, message: format(REDUNDANT_SERVICE_PATH_DIRS_MSG, block: block_name)) do |corrector|
            corrector.remove(range_with_surrounding_space(range: node.source_range, side: :left))
          end
        end

        sig {
          params(
            node:              RuboCop::AST::Node,
            service_path_dirs: T::Array[InstallStepPath],
            block_name:        Symbol,
          ).returns(T::Boolean)
        }
        def redundant_service_path_dirs_block?(node, service_path_dirs, block_name)
          body = if node.def_type?
            T.cast(node, RuboCop::AST::DefNode).body
          elsif node.block_type?
            T.cast(node, RuboCop::AST::BlockNode).body
          end
          return false if body.nil?

          direct_nodes = body.begin_type? ? body.child_nodes : [body]
          direct_nodes.all? do |direct_node|
            service_path_dirs.any? do |path_dir|
              redundant_service_path_dir?(direct_node, path_dir, block_name)
            end
          end
        end

        sig {
          params(
            node:       RuboCop::AST::Node,
            path_dir:   InstallStepPath,
            block_name: Symbol,
          ).returns(T::Boolean)
        }
        def redundant_service_path_dir?(node, path_dir, block_name)
          return false unless node.send_type?

          send_node = T.cast(node, RuboCop::AST::SendNode)
          path = if block_name == :post_install && send_node.method_name == :mkpath && send_node.arguments.empty?
            install_step_path(send_node.receiver)
          else
            return false unless [:mkdir, :mkdir_p].include?(send_node.method_name)

            fileutils_receiver = block_name == :post_install &&
                                 send_node.receiver&.const_type? &&
                                 send_node.receiver&.const_name == "FileUtils"
            return false if send_node.receiver.present? && !fileutils_receiver

            install_step_path_with_base(send_node.arguments.first, send_node.last_argument, default_base: :var)
          end
          paths_match?(path, path_dir)
        end

        sig { params(block_node: T.nilable(RuboCop::AST::BlockNode)).returns(T::Array[InstallStepPath]) }
        def service_path_dirs(block_node)
          return [] if block_node.nil?

          body = block_node.body
          return [] if body.nil?

          direct_nodes = body.begin_type? ? body.child_nodes : [body]
          paths = direct_nodes.filter_map do |node|
            next unless node.send_type?

            send_node = T.cast(node, RuboCop::AST::SendNode)
            next if send_node.receiver.present? || send_node.arguments.empty?

            path = install_step_path(send_node.arguments.first)
            case send_node.method_name
            when :working_dir, :root_dir
              path
            when :input_path, :log_path, :error_log_path
              path_parent(path)
            end
          end
          paths.uniq { |path| path_key(path) }
        end

        sig {
          params(
            node:         T.nilable(RuboCop::AST::Node),
            last_arg:     T.nilable(RuboCop::AST::Node),
            default_base: Symbol,
          ).returns(T.nilable(InstallStepPath))
        }
        def install_step_path_with_base(node, last_arg, default_base:)
          path = install_step_path(node)
          return if path.nil?

          base = install_step_path_hash_base(last_arg)
          return InstallStepPath.new(path: path.path, base:) if base
          if path.base.nil? && !absolute_install_step_path?(path)
            return InstallStepPath.new(path: path.path,
                                       base: default_base)
          end

          path
        end

        sig { params(node: T.nilable(RuboCop::AST::Node)).returns(T.nilable(Symbol)) }
        def install_step_path_hash_base(node)
          return unless node&.hash_type?

          T.cast(node, RuboCop::AST::HashNode).pairs.each do |pair|
            key = pair.key
            next unless key.sym_type?
            next if T.cast(key, RuboCop::AST::SymbolNode).value != :base

            value = pair.value
            return T.cast(value, RuboCop::AST::SymbolNode).value if value.sym_type?
          end
          nil
        end

        sig { params(path: T.nilable(InstallStepPath)).returns(T.nilable(InstallStepPath)) }
        def path_parent(path)
          return if path.nil?

          parent_path = Pathname.new(path.path).dirname.to_s
          return if parent_path == "."

          InstallStepPath.new(path: parent_path, base: path.base)
        end

        sig { params(path: T.nilable(InstallStepPath), other_path: InstallStepPath).returns(T::Boolean) }
        def paths_match?(path, other_path)
          return false if path.nil?

          path_key(path) == path_key(other_path)
        end

        sig { params(path: InstallStepPath).returns([T.nilable(Symbol), String]) }
        def path_key(path)
          [path.base, path.path]
        end
      end
    end
  end
end
