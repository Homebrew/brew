# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `patch`es in formulae.
      # TODO: Many of these could be auto-corrected.
      class Patches < FormulaCop
        extend AutoCorrector

        def audit_formula(node, _class_node, _parent_class_node, body)
          @full_source_content = source_buffer(node).source

          return if body.nil?

          external_patches = find_all_blocks(body, :patch)
          external_patches.each do |patch_block|
            url_node = find_every_method_call_by_name(patch_block, :url).first
            url_string = parameters(url_node).first
            patch_problems(url_string)
          end

          inline_patches = find_every_method_call_by_name(body, :patch)
          inline_patches.each { |patch| inline_patch_problems(patch) }

          if inline_patches.empty? && patch_end?
            offending_patch_end_node(node)
            add_offense(@offense_source_range, message: "patch is missing 'DATA'")
          end

          patches_node = find_method_def(body, :patches)
          return if patches_node.nil?

          legacy_patches = find_strings(patches_node)
          problem "Use the patch DSL instead of defining a 'patches' method"
          legacy_patches.each { |p| patch_problems(p) }
        end

        private

        def patch_problems(patch_url_node)
          patch_url = string_content(patch_url_node)

          if regex_match_group(patch_url_node, %r{https://github.com/[^/]*/[^/]*/pull})
            problem "Use a commit hash URL rather than an unstable pull request URL: #{patch_url}"
          end

          if regex_match_group(patch_url_node, %r{.*gitlab.*/merge_request.*})
            problem "Use a commit hash URL rather than an unstable merge request URL: #{patch_url}"
          end

          if regex_match_group(patch_url_node, %r{https://github.com/[^/]*/[^/]*/commit/[a-fA-F0-9]*\.diff})
            problem "GitHub patches should end with .patch, not .diff: #{patch_url}"
          end

          # Only .diff passes `--full-index` to `git diff` and there is no documented way
          # to get .patch to behave the same for GitLab.
          if regex_match_group(patch_url_node, %r{.*gitlab.*/commit/[a-fA-F0-9]*\.patch})
            problem "GitLab patches should end with .diff, not .patch: #{patch_url}"
          end

          gh_patch_param_pattern = %r{https?://github\.com/.+/.+/(?:commit|pull)/[a-fA-F0-9]*.(?:patch|diff)}
          if regex_match_group(patch_url_node, gh_patch_param_pattern) && !patch_url.match?(/\?full_index=\w+$/)
            problem "GitHub patches should use the full_index parameter: #{patch_url}?full_index=1"
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
              correct = patch_url_node.source.gsub(%r{^http://}, "https://")
              corrector.replace(patch_url_node.source_range, correct)
            end
          end

          return unless regex_match_group(patch_url_node, %r{^http://bugs\.debian\.org})

          problem "Patches from Debian should be https://, not http: #{patch_url}" do |corrector|
            correct = patch_url_node.source.gsub(%r{^http://}, "https://")
            corrector.replace(patch_url_node.source_range, correct)
          end
        end

        def inline_patch_problems(patch)
          return if !patch_data?(patch) || patch_end?

          offending_node(patch)
          problem "patch is missing '__END__'"
        end

        def_node_search :patch_data?, <<~AST
          (send nil? :patch (:sym :DATA))
        AST

        sig { returns(T::Boolean) }
        def patch_end?
          /^__END__$/.match?(@full_source_content)
        end

        def offending_patch_end_node(node)
          @offensive_node = node
          @source_buf = source_buffer(node)
          @line_no = node.loc.last_line + 1
          @column = 0
          @length = 7 # "__END__".size
          @offense_source_range = source_range(@source_buf, @line_no, @column, @length)
        end
      end
    end
  end
end
