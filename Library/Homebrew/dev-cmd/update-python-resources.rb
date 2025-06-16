# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "utils/pypi"

module Homebrew
  module DevCmd
    class UpdatePythonResources < AbstractCommand
      cmd_args do
        description <<~EOS
          Update versions for PyPI resource blocks in <formula>.
        EOS
        switch "-p", "--print-only",
               description: "Print the updated resource blocks instead of changing <formula>."
        switch "-s", "--silent",
               description: "Suppress any output."
        switch "--ignore-errors",
               description: "Record all discovered resources, even those that can't be resolved successfully. " \
                            "This option is ignored for homebrew/core formulae."
        switch "--ignore-non-pypi-packages",
               description: "Don't fail if <formula> is not a PyPI package."
        switch "--install-dependencies",
               description: "Install missing dependencies required to update resources."
        flag   "--version=",
               description: "Use the specified <version> when finding resources for <formula>. " \
                            "If no version is specified, the current version for <formula> will be used."
        flag   "--package-name=",
               description: "Use the specified <package-name> when finding resources for <formula>. " \
                            "If no package name is specified, it will be inferred from the formula's stable URL."
        comma_array "--extra-packages",
                    description: "Include these additional packages when finding resources."
        comma_array "--exclude-packages",
                    description: "Exclude these packages when finding resources."

        named_args :formula, min: 1, without_api: true
      end

      sig { override.void }
      def run
        args.named.to_formulae.each do |formula|
          ignore_errors = if formula.tap&.official?
            false
          else
            args.ignore_errors?
          end
          PyPI.update_python_resources! formula,
                                        version:                  args.version,
                                        package_name:             args.package_name,
                                        extra_packages:           args.extra_packages,
                                        exclude_packages:         args.exclude_packages,
                                        install_dependencies:     args.install_dependencies?,
                                        print_only:               args.print_only?,
                                        silent:                   args.silent?,
                                        verbose:                  args.verbose?,
                                        ignore_errors:            ignore_errors,
                                        ignore_non_pypi_packages: args.ignore_non_pypi_packages?
        end
      end
    end
  end
end
