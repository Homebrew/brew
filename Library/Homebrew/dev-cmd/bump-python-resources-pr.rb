# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "bump"
require "formula"
require "json"
require "utils/github"

module Homebrew
  module DevCmd
    class BumpPythonResourcesPr < AbstractCommand
      Result = T.type_alias { T::Hash[Symbol, T.any(String, T::Boolean)] }

      cmd_args do
        description <<~EOS
          Update vulnerable PyPI resources in <formula>, bump its revision, and create a pull request.
        EOS
        switch "-n", "--dry-run",
               description: "Print what would be done rather than creating a pull request."
        switch "--no-fork",
               description: "Don't try to fork the repository."
        switch "--install-dependencies",
               description: "Install missing dependencies required to update resources."
        comma_array "--packages=",
                    description: "Names of vulnerable Python packages that must be updated."
        flag   "--branch=",
               description: "Branch name to use for the pull request."
        flag   "--message=",
               description: "Message to prepend to the pull request body."
        flag   "--output=",
               description: "Write the JSON result to this file instead of standard output. " \
                            "Use this when parsing the result, as progress is also printed to standard output."

        named_args :formula, number: 1, without_api: true

        hide_from_man_page!
      end

      sig { override.void }
      def run
        raise UsageError, "`--packages` must name at least one vulnerable Python package." if args.packages.blank?

        Utils::GemSetup.install_bundler_gems!(groups: ["ast"])
        require "utils/ast"
        require "utils/pypi"

        packages = args.packages.to_a.map { |package| PyPI.normalize_python_package(package) }.uniq

        formula = args.named.to_formulae.fetch(0)
        write_result(bump_resources(formula, packages))
      end

      private

      sig { params(formula: Formula, packages: T::Array[String]).returns(Result) }
      def bump_resources(formula, packages)
        if formula.deprecated? || formula.disabled?
          return result("Skipped because formula is deprecated or disabled")
        end

        old_urls = vulnerable_resource_urls(formula, packages)
        return result("No matching vulnerable PyPI resources") if old_urls.empty?

        old_contents = formula.path.read
        keep_changes = false

        begin
          bump_revision(formula)

          begin
            PyPI.update_python_resources!(formula,
                                          install_dependencies: args.install_dependencies?,
                                          verbose:              true)
          rescue SystemExit => e
            return result("`update_python_resources!` failed with status #{e.status}")
          rescue => e
            return result("`update_python_resources!` raised `#{e.class}`: #{e.message}")
          end

          Formulary.clear_cache
          updated_formula = Formulary.factory(formula.path)
          new_urls = vulnerable_resource_urls(updated_formula, packages)
          replaced_urls = old_urls - new_urls
          return result("No vulnerable resources were updated") if replaced_urls.empty?

          tap = updated_formula.tap
          if tap.nil? || (remote_repository = tap.remote_repository).nil?
            return result("Formula is not in a Git tap with a remote repository")
          end

          begin
            GitHub.check_for_duplicate_pull_requests(updated_formula.name, remote_repository,
                                                     state:  "open",
                                                     file:   updated_formula.path.relative_path_from(tap.path).to_s,
                                                     quiet:  false,
                                                     strict: true)
          rescue SystemExit
            return result("Existing pull request for this formula")
          end

          commit_message = "#{updated_formula.name}: bump python resources"
          info = Homebrew::Bump::BumpInfo.new(
            commits:     [
              Homebrew::Bump::Commit.new(
                sourcefile_path: updated_formula.path,
                commit_message:,
                old_contents:,
              ),
            ],
            branch_name: args.branch || "bump-python-resources-#{updated_formula.name}-#{Time.now.to_i}",
            pr_message:  pull_request_message(old_urls, replaced_urls),
            package_tap: tap,
            pr_title:    commit_message,
          )
          url = Homebrew::Bump.create_pr(info, no_fork: args.no_fork?, dry_run: args.dry_run?)

          if args.dry_run?
            result("Dry run", attempted: true)
          else
            keep_changes = true
            result(url || "Pull request created", attempted: true, updated: true)
          end
        ensure
          formula.path.atomic_write(old_contents) unless keep_changes
        end
      end

      sig { params(formula: Formula).void }
      def bump_revision(formula)
        formula_ast = Utils::AST::FormulaAST.new(formula.path.read)
        next_revision = formula.revision + 1
        if formula.revision.zero?
          formula_ast.add_stanza(:revision, next_revision)
        else
          formula_ast.replace_stanza(:revision, next_revision)
        end
        formula.path.atomic_write(formula_ast.process)
      end

      sig { params(formula: Formula, packages: T::Array[String]).returns(T::Array[String]) }
      def vulnerable_resource_urls(formula, packages)
        formula.resources.filter_map do |resource|
          url = resource.url
          next unless packages.include?(PyPI.normalize_python_package(resource.name))
          next unless url&.match?(%r{\Ahttps?://files\.pythonhosted\.org/})

          url
        end
      end

      sig { params(old_urls: T::Array[String], replaced_urls: T::Array[String]).returns(String) }
      def pull_request_message(old_urls, replaced_urls)
        intro = args.message.presence || "Created with `brew bump-python-resources-pr`."
        <<~MSG
          #{intro}

          The following resources have known vulnerabilities:

          ```console
          #{old_urls.join("\n")}
          ```

          Of those, the following were replaced:

          ```console
          #{replaced_urls.join("\n")}
          ```
        MSG
      end

      sig {
        params(reason: String, attempted: T::Boolean, updated: T::Boolean).returns(Result)
      }
      def result(reason, attempted: false, updated: false)
        { attempted:, updated:, reason: }
      end

      sig { params(result: Result).void }
      def write_result(result)
        json = JSON.generate(result)
        if (output = args.output)
          File.write(output, "#{json}\n")
        else
          puts json
        end
      end
    end
  end
end
