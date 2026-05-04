# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `patch`es in formulae.
      class Patches < FormulaCop
        extend AutoCorrector

        PLATFORM_CONDITIONALS = T.let([:on_macos, :on_linux].freeze, T::Array[Symbol])

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          node = formula_nodes.node
          @full_source_content = T.let(source_buffer(node).source, T.nilable(String))

          return if (body_node = formula_nodes.body_node).nil?

          find_all_blocks(body_node, :patch).each do |patch_block|
            file_nodes = find_every_method_call_by_name(patch_block, :file)
            if file_nodes.present?
              local_patch_problems(patch_block, file_nodes)
              next
            end

            url_node = find_every_method_call_by_name(patch_block, :url).first
            next unless url_node

            url_string = parameters(url_node).fetch(0)
            sha256_node = find_every_method_call_by_name(patch_block, :sha256).first
            sha256_string = parameters(sha256_node).first if sha256_node
            patch_problems(url_string, sha256_string)
          end

          inline_patches = find_every_method_call_by_name(body_node, :patch)
          inline_patches.each { |patch| inline_patch_problems(patch) }

          if inline_patches.empty? && patch_end?
            offending_patch_end_node(node)
            add_offense(@offense_source_range, message: "Patch is missing `patch :DATA`")
          end

          patches_node = find_method_def(body_node, :patches)
          return if patches_node.nil?

          legacy_patches = find_strings(patches_node)
          problem "Use the `patch` DSL instead of defining a `patches` method"
          legacy_patches.each { |p| patch_problems(p, nil) }
        end

        private

        sig { params(patch_url_node: RuboCop::AST::Node, sha256_node: T.nilable(RuboCop::AST::Node)).void }
        def patch_problems(patch_url_node, sha256_node)
          patch_url = string_content(patch_url_node)

          if regex_match_group(patch_url_node, %r{https://github.com/[^/]*/[^/]*/pull})
            problem "Use a commit hash URL rather than an unstable pull request URL: #{patch_url}"
          end

          if regex_match_group(patch_url_node, %r{.*gitlab.*/merge_request.*})
            problem "Use a commit hash URL rather than an unstable merge request URL: #{patch_url}"
          end

          if regex_match_group(patch_url_node, %r{https://github.com/[^/]*/[^/]*/commit/[a-fA-F0-9]*\.diff})
            problem "GitHub patches should end with .patch, not .diff: #{patch_url}" do |corrector|
              # Replace .diff with .patch, keeping either the closing quote or query parameter start
              correct = patch_url_node.source.sub(/\.diff(["?])/, '.patch\1')
              corrector.replace(patch_url_node.source_range, correct)
              corrector.replace(sha256_node.source_range, '""') if sha256_node
            end
          end

          bitbucket_regex = %r{bitbucket\.org/([^/]+)/([^/]+)/commits/([a-f0-9]+)/raw}i
          if regex_match_group(patch_url_node, bitbucket_regex)
            owner, repo, commit = patch_url_node.source.match(bitbucket_regex).captures
            correct_url = "https://api.bitbucket.org/2.0/repositories/#{owner}/#{repo}/diff/#{commit}"
            problem "Bitbucket patches should use the API URL: #{correct_url}" do |corrector|
              corrector.replace(patch_url_node.source_range, %Q("#{correct_url}"))
              corrector.replace(sha256_node.source_range, '""') if sha256_node
            end
          end

          # Only .diff passes `--full-index` to `git diff` and there is no documented way
          # to get .patch to behave the same for GitLab.
          if regex_match_group(patch_url_node, %r{.*gitlab.*/commit/[a-fA-F0-9]*\.patch})
            problem "GitLab patches should end with .diff, not .patch: #{patch_url}" do |corrector|
              # Replace .patch with .diff, keeping either the closing quote or query parameter start
              correct = patch_url_node.source.sub(/\.patch(["?])/, '.diff\1')
              corrector.replace(patch_url_node.source_range, correct)
              corrector.replace(sha256_node.source_range, '""') if sha256_node
            end
          end

          gh_patch_param_pattern = %r{https?://github\.com/.+/.+/(?:commit|pull)/[a-fA-F0-9]*.(?:patch|diff)}
          if regex_match_group(patch_url_node, gh_patch_param_pattern) && !patch_url.match?(/\?full_index=\w+$/)
            problem "GitHub patches should use the full_index parameter: #{patch_url}?full_index=1" do |corrector|
              correct = patch_url_node.source.sub(/"$/, '?full_index=1"')
              corrector.replace(patch_url_node.source_range, correct)
              corrector.replace(sha256_node.source_range, '""') if sha256_node
            end
          end

          gh_patch_patterns = Regexp.union([%r{/raw\.github\.com/},
                                            %r{/raw\.githubusercontent\.com/},
                                            %r{gist\.github\.com/raw},
                                            %r{gist\.github\.com/.+/raw},
                                            %r{gist\.githubusercontent\.com/.+/raw}])
          if regex_match_group(patch_url_node, gh_patch_patterns) && !patch_url.match?(%r{/[a-fA-F0-9]{6,40}/})
            problem "GitHub/Gist patches should specify a revision: #{patch_url}"
          end

          gh_patch_diff_pattern =
            %r{https?://patch-diff\.githubusercontent\.com/raw/(.+)/(.+)/pull/(.+)\.(?:diff|patch)}
          if regex_match_group(patch_url_node, gh_patch_diff_pattern)
            problem "Use a commit hash URL rather than patch-diff: #{patch_url}"
          end

          if regex_match_group(patch_url_node, %r{macports/trunk})
            problem "MacPorts patches should specify a revision instead of trunk: #{patch_url}"
          end

          if regex_match_group(patch_url_node, %r{^http://trac\.macports\.org})
            problem "Patches from MacPorts Trac should be https://, not http: #{patch_url}" do |corrector|
              corrector.replace(patch_url_node.source_range,
                                patch_url_node.source.sub(%r{\A"http://}, '"https://'))
            end
          end

          return unless regex_match_group(patch_url_node, %r{^http://bugs\.debian\.org})

          problem "Patches from Debian should be https://, not http: #{patch_url}" do |corrector|
            corrector.replace(patch_url_node.source_range,
                              patch_url_node.source.sub(%r{\A"http://}, '"https://'))
          end
        end

        sig { params(patch_block: RuboCop::AST::Node, file_nodes: T::Array[RuboCop::AST::Node]).void }
        def local_patch_problems(patch_block, file_nodes)
          file_nodes.each do |file_node|
            file_path_node = parameters(file_node).first
            next unless file_path_node&.str_type?

            file_path = Pathname(string_content(file_path_node)).cleanpath
            next if !file_path.absolute? && file_path.to_s != ".." && !file_path.to_s.start_with?("../")

            offending_node(file_node)
            problem "Patch file must be a relative path within the repository."
          end

          {
            url:       "Patch cannot have both `file` and `url`.",
            sha256:    "Patch cannot use `sha256` with `file`.",
            directory: "Patch cannot use `directory` with `file`.",
            apply:     "Patch cannot use `apply` with `file`.",
          }.each do |method_name, message|
            find_every_method_call_by_name(patch_block, method_name).each do |node|
              next unless conflicts_with_file?(node, file_nodes, patch_block)

              offending_node(node)
              problem message
            end
          end
        end

        sig {
          params(
            node:        RuboCop::AST::Node,
            file_nodes:  T::Array[RuboCop::AST::Node],
            patch_block: RuboCop::AST::Node,
          ).returns(T::Boolean)
        }
        def conflicts_with_file?(node, file_nodes, patch_block)
          file_nodes.any? do |file_node|
            !mutually_exclusive_platform_conditionals?(node, file_node, patch_block)
          end
        end

        sig {
          params(
            node:        RuboCop::AST::Node,
            other_node:  RuboCop::AST::Node,
            patch_block: RuboCop::AST::Node,
          ).returns(T::Boolean)
        }
        def mutually_exclusive_platform_conditionals?(node, other_node, patch_block)
          platform_conditional(node, patch_block).then do |platform|
            other_platform = platform_conditional(other_node, patch_block)
            platform.present? && other_platform.present? && platform != other_platform
          end
        end

        sig { params(node: RuboCop::AST::Node, patch_block: RuboCop::AST::Node).returns(T.nilable(Symbol)) }
        def platform_conditional(node, patch_block)
          node.each_ancestor do |ancestor|
            break if ancestor.equal?(patch_block)
            next unless ancestor.block_type?

            method_name = ancestor.method_name
            return method_name if PLATFORM_CONDITIONALS.include?(method_name)
          end

          nil
        end

        sig { params(patch: RuboCop::AST::Node).void }
        def inline_patch_problems(patch)
          return if !patch_data?(patch) || patch_end?

          offending_node(patch)
          problem "Patch is missing `__END__`"
        end

        def_node_search :patch_data?, <<~AST
          (send nil? :patch (:sym :DATA))
        AST

        sig { returns(T::Boolean) }
        def patch_end?
          /^__END__$/.match?(@full_source_content)
        end

        sig { params(node: RuboCop::AST::Node).void }
        def offending_patch_end_node(node)
          @offensive_node = T.let(node, T.nilable(RuboCop::AST::Node))
          @source_buf = T.let(source_buffer(node), T.nilable(Parser::Source::Buffer))
          @line_no = T.let(node.loc.last_line + 1, T.nilable(Integer))
          @column = T.let(0, T.nilable(Integer))
          @length = T.let(7, T.nilable(Integer)) # "__END__".size
          @offense_source_range = T.let(
            source_range(@source_buf, @line_no, @column, @length),
            T.nilable(Parser::Source::Range),
          )
        end
      end
    end
  end
end
