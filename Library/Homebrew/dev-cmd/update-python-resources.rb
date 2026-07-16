# typed: strict
# frozen_string_literal: true

require "abstract_command"

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
               description: "Suppress any output.",
               odeprecated: true
        switch "--ignore-errors",
               description: "Record all discovered resources, even those that can't be resolved successfully. " \
                            "This option is ignored for homebrew/core formulae."
        switch "--ignore-non-pypi-packages",
               description: "Don't fail if <formula> is not a PyPI package."
        switch "--ignore-main-package-cooldown",
               description: "Bypass the release cooldown for <formula>'s own package when resolving " \
                            "resources. Its dependencies still respect the cooldown. This option is " \
                            "ignored for official taps."
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
        Homebrew.install_bundler_gems!(groups: ["ast"])
        require "utils/pypi"

        args.named.to_formulae.each do |formula|
          # These options may only be used on third-party taps.
          if formula.tap&.official?
            ignore_errors = false
            ignore_main_package_cooldown = false
          else
            ignore_errors = args.ignore_errors?
            ignore_main_package_cooldown = args.ignore_main_package_cooldown?
          end
          PyPI.update_python_resources! formula,
                                        version:                      args.version,
                                        package_name:                 args.package_name,
                                        extra_packages:               args.extra_packages,
                                        exclude_packages:             args.exclude_packages,
                                        install_dependencies:         args.install_dependencies?,
                                        print_only:                   args.print_only?,
                                        quiet:                        args.quiet? || args.silent?,
                                        verbose:                      args.verbose?,
                                        ignore_errors:                ignore_errors,
                                        ignore_non_pypi_packages:     args.ignore_non_pypi_packages?,
                                        ignore_main_package_cooldown: ignore_main_package_cooldown
        end
      end
    end
  end
end
