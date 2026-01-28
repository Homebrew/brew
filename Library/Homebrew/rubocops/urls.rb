# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/url_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `url`s and `mirror`s in formulae.
      class Urls < FormulaCop
        include UrlHelper

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          urls = find_every_func_call_by_name(body_node, :url)
          mirrors = find_every_func_call_by_name(body_node, :mirror)

          # Identify livecheck URLs, to skip some checks for them
          livecheck_url = if (livecheck = find_every_func_call_by_name(body_node, :livecheck).first) &&
                             (livecheck_url = find_every_func_call_by_name(livecheck.parent, :url).first)
            string_content(parameters(livecheck_url).first)
          end

          audit_url(:formula, urls, mirrors, livecheck_url:)

          return if formula_tap != "homebrew-core"

          # Check for binary URLs
          audit_urls(urls, /(darwin|macos|osx)/i) do |match, url|
            next if T.must(@formula_name).include?(match.to_s.downcase)
            next if url.match?(/.(patch|diff)(\?full_index=1)?$/)
            next if tap_style_exception? :not_a_binary_url_prefix_allowlist
            next if tap_style_exception? :binary_bootstrap_formula_urls_allowlist

            problem "#{url} looks like a binary package, not a source archive; " \
                    "homebrew/core is source-only."
          end
        end
      end

      # This cop makes sure that `url`s use HTTPS.
      class HttpUrls < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?
          return if formula_tap != "homebrew-core"
          # TODO: Remove the deprecated/disabled check after homebrew/core has no more
          # deprecated/disabled formulae using http:// URLs
          return if method_called_ever?(body_node, :deprecate!) || method_called_ever?(body_node, :disable!)

          urls = find_every_func_call_by_name(body_node, :url)

          # Identify livecheck URL to skip checking it (symbols like :homepage are implicitly skipped)
          livecheck_url = if (livecheck = find_every_func_call_by_name(body_node, :livecheck).first) &&
                             (livecheck_url_node = find_every_func_call_by_name(livecheck.parent, :url).first)
            string_content(parameters(livecheck_url_node).first)
          end

          urls.each do |url_node|
            url_string_node = parameters(url_node).first
            url_string = string_content(url_string_node)

            next unless url_string.start_with?("http://")
            next if url_string == livecheck_url

            offending_node(url_string_node)
            problem "Formulae in homebrew/core should not use http:// URLs" do |corrector|
              corrector.replace(url_string_node.source_range, url_string_node.source.sub("http://", "https://"))
            end
          end
        end
      end

      # This cop makes sure that the correct format for PyPI URLs is used.
      class PyPiUrls < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          urls = find_every_func_call_by_name(body_node, :url)
          mirrors = find_every_func_call_by_name(body_node, :mirror)
          urls += mirrors

          # Check pypi URLs
          pypi_pattern = %r{^https?://pypi\.python\.org/}
          audit_urls(urls, pypi_pattern) do |_, url|
            problem "Use the \"Source\" URL found on the PyPI downloads page (#{get_pypi_url(url)})"
          end

          # Require long files.pythonhosted.org URLs
          pythonhosted_pattern = %r{^https?://files\.pythonhosted\.org/packages/source/}
          audit_urls(urls, pythonhosted_pattern) do |_, url|
            problem "Use the \"Source\" URL found on the PyPI downloads page (#{get_pypi_url(url)})"
          end
        end

        sig { params(url: String).returns(String) }
        def get_pypi_url(url)
          package_file = File.basename(url)
          package_name = T.must(package_file.match(/^(.+)-[a-z0-9.]+$/))[1]
          "https://pypi.org/project/#{package_name}/#files"
        end
      end

      # This cop makes sure that git URLs have a `revision`.
      class GitUrls < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?
          return if formula_tap != "homebrew-core"

          find_method_calls_by_name(body_node, :url).each do |url|
            next unless string_content(parameters(url).first).match?(/\.git$/)
            next if url_has_revision?(parameters(url).last)

            offending_node(url)
            problem "Formulae in homebrew/core should specify a revision for Git URLs"
          end
        end

        def_node_matcher :url_has_revision?, <<~EOS
          (hash <(pair (sym :revision) str) ...>)
        EOS
      end
    end

    module FormulaAuditStrict
      # This cop makes sure that git URLs have a `tag`.
      class GitUrls < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?
          return if formula_tap != "homebrew-core"

          find_method_calls_by_name(body_node, :url).each do |url|
            next unless string_content(parameters(url).first).match?(/\.git$/)
            next if url_has_tag?(parameters(url).last)

            offending_node(url)
            problem "Formulae in homebrew/core should specify a tag for Git URLs"
          end
        end

        def_node_matcher :url_has_tag?, <<~EOS
          (hash <(pair (sym :tag) str) ...>)
        EOS
      end
    end
  end
end
