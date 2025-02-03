# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks for various problems in a formula's source code.
      class Text < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          node = formula_nodes.node
          full_source_content = source_buffer(node).source

          if (match = full_source_content.match(/^require ['"]formula['"]$/))
            range = source_range(source_buffer(node), match.pre_match.count("\n") + 1, 0, match[0].length)
            add_offense(range, message: "`#{match}` is now unnecessary") do |corrector|
              corrector.remove(range_with_surrounding_space(range:))
            end
          end

          return if (body_node = formula_nodes.body_node).nil?

          if find_method_def(body_node, :plist)
            problem "`def plist` is deprecated. Please use services instead: https://docs.brew.sh/Formula-Cookbook#service-files"
          end

          if (depends_on?("openssl") || depends_on?("openssl@3")) && depends_on?("libressl")
            problem "Formulae should not depend on both OpenSSL and LibreSSL (even optionally)."
          end

          if formula_tap == "homebrew-core"
            if depends_on?("veclibfort") || depends_on?("lapack")
              problem "Formulae in homebrew/core should use OpenBLAS as the default serial linear algebra library."
            end

            if find_node_method_by_name(body_node, :keg_only)&.source&.include?("HOMEBREW_PREFIX")
              problem "`keg_only` reason should not include `HOMEBREW_PREFIX` " \
                      "as it creates confusing `brew info` output."
            end
          end

          unless method_called_ever?(body_node, :go_resource)
            # processed_source.ast is passed instead of body_node because `require` would be outside body_node
            find_method_with_args(processed_source.ast, :require, "language/go") do
              problem "require \"language/go\" is unnecessary unless using `go_resource`s"
            end
          end

          find_instance_method_call(body_node, "Formula", :factory) do
            problem "\"Formula.factory(name)\" is deprecated in favor of \"Formula[name]\""
          end

          find_method_with_args(body_node, :revision, 0) do
            problem "\"revision 0\" is unnecessary"
          end

          find_method_with_args(body_node, :system, "xcodebuild") do
            problem %q(use "xcodebuild *args" instead of "system 'xcodebuild', *args")
          end

          if !depends_on?(:xcode) && method_called_ever?(body_node, :xcodebuild)
            problem "`xcodebuild` needs an Xcode dependency"
          end

          if (method_node = find_method_def(body_node, :install))
            find_method_with_args(method_node, :system, "go", "get") do
              problem "Do not use `go get`. Please ask upstream to implement Go vendoring"
            end

            find_method_with_args(method_node, :system, "cargo", "build") do |m|
              next if parameters_passed?(m, [/--lib/])

              problem "use \"cargo\", \"install\", *std_cargo_args"
            end
          end

          find_method_with_args(body_node, :system, "dep", "ensure") do |d|
            next if parameters_passed?(d, [/vendor-only/])
            next if @formula_name == "goose" # needed in 2.3.0

            problem "use \"dep\", \"ensure\", \"-vendor-only\""
          end

          find_every_method_call_by_name(body_node, :system).each do |m|
            next unless parameters_passed?(m, [/make && make/])

            offending_node(m)
            problem "Use separate `make` calls"
          end

          body_node.each_descendant(:dstr) do |dstr_node|
            dstr_node.each_descendant(:begin) do |interpolation_node|
              next unless interpolation_node.source.match?(/#\{\w+\s*\+\s*['"][^}]+\}/)

              offending_node(interpolation_node)
              problem "Do not concatenate paths in string interpolation"
            end
          end

          prefix_path(body_node) do |prefix_node, path|
            next unless (match = path.match(%r{^(bin|include|libexec|lib|sbin|share|Frameworks)(?:/| |$)}))

            offending_node(prefix_node)
            problem "Use `#{match[1].downcase}` instead of `prefix + \"#{match[1]}\"`"
          end
        end

        # Find: prefix + "foo"
        def_node_search :prefix_path, <<~EOS
          $(send (send nil? :prefix) :+ (str $_))
        EOS
      end
    end

    module FormulaAuditStrict
      # This cop contains stricter checks for various problems in a formula's source code.
      class Text < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          find_method_with_args(body_node, :go_resource) do
            problem "`go_resource`s are deprecated. Please ask upstream to implement Go vendoring"
          end

          find_method_with_args(body_node, :env, :userpaths) do
            problem "`env :userpaths` in homebrew/core formulae is deprecated"
          end

          share_path_starts_with(body_node, @formula_name) do |share_node|
            offending_node(share_node)
            problem "Use `pkgshare` instead of `share/\"#{@formula_name}\"`"
          end

          interpolated_share_path_starts_with(body_node, "/#{@formula_name}") do |share_node|
            offending_node(share_node)
            problem "Use `\#{pkgshare}` instead of `\#{share}/#{@formula_name}`"
          end

          interpolated_bin_path_starts_with(body_node, "/#{@formula_name}") do |bin_node|
            next if bin_node.ancestors.any?(&:array_type?)

            offending_node(bin_node)
            cmd = bin_node.source.match(%r{\#{bin}/(\S+)})[1]&.delete_suffix('"') || @formula_name
            problem "Use `bin/\"#{cmd}\"` instead of `\"\#{bin}/#{cmd}\"`" do |corrector|
              corrector.replace(bin_node.loc.expression, "bin/\"#{cmd}\"")
            end
          end

          return if formula_tap != "homebrew-core"

          find_method_with_args(body_node, :env, :std) do
            problem "`env :std` in homebrew/core formulae is deprecated"
          end
        end

        # Check whether value starts with the formula name and then a "/", " " or EOS.
        # If we're checking for "#{bin}", we also check for "-" since similar binaries also don't need interpolation.
        sig { params(path: String, starts_with: String, bin: T::Boolean).returns(T::Boolean) }
        def path_starts_with?(path, starts_with, bin: false)
          ending = bin ? "/|-|$" : "/| |$"
          path.match?(/^#{Regexp.escape(starts_with)}(#{ending})/)
        end

        sig { params(path: String, starts_with: String).returns(T::Boolean) }
        def path_starts_with_bin?(path, starts_with)
          return false if path.include?(" ")

          path_starts_with?(path, starts_with, bin: true)
        end

        # Find "#{share}/foo"
        def_node_search :interpolated_share_path_starts_with, <<~EOS
          $(dstr (begin (send nil? :share)) (str #path_starts_with?(%1)))
        EOS

        # Find "#{bin}/foo" and "#{bin}/foo-bar"
        def_node_search :interpolated_bin_path_starts_with, <<~EOS
          $(dstr (begin (send nil? :bin)) (str #path_starts_with_bin?(%1)))
        EOS

        # Find share/"foo"
        def_node_search :share_path_starts_with, <<~EOS
          $(send (send nil? :share) :/ (str #path_starts_with?(%1)))
        EOS
      end
    end
  end
end
