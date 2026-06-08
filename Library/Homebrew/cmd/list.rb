# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "metafiles"
require "formula"
require "cli/parser"
require "cask/list"
require "system_command"
require "tab"

module Homebrew
  module Cmd
    class List < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          List all installed formulae and casks.
          If <formula> is provided, summarise the paths within its current keg.
          If <cask> is provided, list its artifacts.
        EOS
        switch "--formula", "--formulae",
               description: "List only formulae, or treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "List only casks, or treat all named arguments as casks."
        switch "--full-name",
               description: "Print formulae with fully-qualified names. Unless `--full-name`, `--versions` " \
                            "or `--pinned` are passed, other options (i.e. `-1`, `-l`, `-r` and `-t`) are " \
                            "passed to `ls`(1) which produces the actual output."
        switch "--versions",
               description: "Show the version number for installed formulae, or only the specified " \
                            "formulae if <formula> are provided."
        switch "--json",
               description: "Output installed formulae and casks with versions, linked and opt-linked formula " \
                            "versions and pinned versions as JSON using the fast Bash command path. Requires " \
                            "`--versions`, no named arguments and `jq`."
        switch "--multiple",
               description: "Only show formulae with multiple versions installed. Implies `--versions`."
        switch "--pinned",
               description: "List only pinned packages, or only the specified (pinned) packages if <formula> or " \
                            "<cask> are provided. See also `pin`, `unpin`."
        switch "--installed-on-request",
               description: "List the formulae installed on request."
        switch "--installed-as-dependency",
               description: "List the formulae installed as dependencies.",
               odeprecated: true,
               replacement: "--no-installed-on-request"
        switch "--poured-from-bottle",
               description: "List the formulae installed from a bottle."
        switch "--built-from-source",
               description: "List the formulae compiled from source."

        # passed through to ls
        switch "-1",
               description: "Force output to be one entry per line. " \
                            "This is the default when output is not to a terminal."
        switch "-l",
               description: "List formulae and/or casks in long format. " \
                            "Has no effect when a formula or cask name is passed as an argument."
        switch "-r",
               description: "Reverse the order of formula and/or cask sorting to list the oldest entries first. " \
                            "Has no effect when a formula or cask name is passed as an argument."
        switch "-t",
               description: "Sort formulae and/or casks by time modified, listing most recently modified first. " \
                            "Has no effect when a formula or cask name is passed as an argument."

        conflicts "--formula", "--cask"
        conflicts "--multiple", "--cask"
        conflicts "--pinned", "--multiple"
        ["--installed-on-request", "--installed-as-dependency",
         "--poured-from-bottle", "--built-from-source"].each do |flag|
          conflicts "--cask", flag
          conflicts "--versions", flag
          conflicts "--multiple", flag
          conflicts "--pinned", flag
          conflicts "-l", flag
        end
        ["-1", "-l", "-r", "-t"].each do |flag|
          conflicts "--versions", flag
          conflicts "--multiple", flag
          conflicts "--pinned", flag
        end
        ["--versions", "--multiple", "--pinned", "-l", "-r", "-t"].each do |flag|
          conflicts "--full-name", flag
        end

        named_args [:installed_formula, :installed_cask]
      end

      sig { override.void }
      def run
        if args.json?
          raise UsageError, "`brew list --json` requires `--versions`." unless args.versions?
          raise UsageError, "`brew list --versions --json` does not support named arguments." unless args.no_named?

          raise UsageError, "`brew list --versions --json` is only supported by the fast Bash path with `jq`."
        end

        if args.full_name? &&
           !(args.installed_on_request? || args.installed_as_dependency? ||
             args.poured_from_bottle? || args.built_from_source?)
          unless args.cask?
            formula_names = args.no_named? ? Formula.installed : args.named.to_resolved_formulae
            full_formula_names = formula_names.map(&:full_name).sort(&Cask::List::TAP_AND_NAME_COMPARISON)
            full_formula_names = Formatter.columns(full_formula_names) unless args.public_send(:"1?")
            puts full_formula_names if full_formula_names.present?
          end
          if args.cask? || (!args.formula? && args.no_named?)
            cask_names = if args.no_named?
              Cask::Caskroom.casks
            else
              args.named.to_formulae_and_casks(only: :cask, method: :resolve)
            end
            # The cast is because `Keg`` does not define `full_name`
            full_cask_names = T.cast(cask_names, T::Array[T.any(Formula, Cask::Cask)])
                               .map(&:full_name).sort(&Cask::List::TAP_AND_NAME_COMPARISON)
            full_cask_names = Formatter.columns(full_cask_names) unless args.public_send(:"1?")
            puts full_cask_names if full_cask_names.present?
          end
        elsif args.pinned?
          pinned = if args.no_named?
            entries = T.let([], T::Array[String])
            unless args.cask?
              Formula.racks.each do |rack|
                entry = pinned_formula_entry(rack.basename.to_s)
                entries << entry if entry
              end
            end

            if !args.formula? && Cask::Caskroom.path.directory?
              Cask::Caskroom.path.children.reject(&:file?).each do |path|
                entry = pinned_cask_entry(path.basename.to_s)
                entries << entry if entry
              end
            end
            entries
          else
            args.named.filter_map do |name|
              entry = T.let(nil, T.nilable(String))
              package_found = T.let(false, T::Boolean)
              package_name = T.let(nil, T.nilable(String))

              unless args.cask?
                rack = Formulary.to_rack(name)
                if rack.exist?
                  package_found = true
                  package_name = rack.basename.to_s
                  entry ||= pinned_formula_entry(rack.basename.to_s)
                end
              end

              unless args.formula?
                token = ::Utils.name_from_full_name(name).to_s
                caskroom_path = Cask::Caskroom.path/token
                if caskroom_path.exist? || caskroom_path.symlink?
                  package_found = true
                  package_name ||= token
                  entry ||= pinned_cask_entry(token)
                end
              end

              if package_found && entry.nil?
                opoo "#{package_name || name} not pinned"
              elsif !package_found
                Homebrew.failed = true
              end
              entry
            end
          end

          puts pinned.sort(&Cask::List::TAP_AND_NAME_COMPARISON)
        elsif args.versions? || args.multiple?
          filtered_list unless args.cask?
          list_casks if args.cask? || (!args.formula? && !args.multiple? && args.no_named?)
        elsif args.installed_on_request? ||
              args.installed_as_dependency? ||
              args.poured_from_bottle? ||
              args.built_from_source?
          flags = []
          flags << "`--installed-on-request`" if args.installed_on_request?
          flags << "`--installed-as-dependency`" if args.installed_as_dependency?
          flags << "`--poured-from-bottle`" if args.poured_from_bottle?
          flags << "`--built-from-source`" if args.built_from_source?

          raise UsageError, "Cannot use #{flags.join(", ")} with formula arguments." unless args.no_named?

          formulae = if args.t?
            # See https://ruby-doc.org/3.2/Kernel.html#method-i-test
            Formula.installed.sort_by { |formula| T.cast(test("M", formula.rack.to_s), Time) }.reverse!
          elsif args.full_name?
            Formula.installed.sort { |a, b| Cask::List::TAP_AND_NAME_COMPARISON.call(a.full_name, b.full_name) }
          else
            Formula.installed.sort
          end
          formulae.reverse! if args.r?
          formulae.each do |formula|
            tab = Tab.for_formula(formula)

            statuses = []
            statuses << "installed on request" if args.installed_on_request? && tab.installed_on_request
            statuses << "installed as dependency" if args.installed_as_dependency? && !tab.installed_on_request
            statuses << "poured from bottle" if args.poured_from_bottle? && tab.poured_from_bottle
            statuses << "built from source" if args.built_from_source? && !tab.poured_from_bottle
            next if statuses.empty?

            name = args.full_name? ? formula.full_name : formula.name
            if flags.count > 1
              puts "#{name}: #{statuses.join(", ")}"
            else
              puts name
            end
          end
        elsif args.no_named?
          ENV["CLICOLOR"] = nil

          ls_args = []
          ls_args << "-1" if args.public_send(:"1?")
          ls_args << "-l" if args.l?
          ls_args << "-r" if args.r?
          ls_args << "-t" if args.t?

          if !args.cask? && HOMEBREW_CELLAR.exist? && HOMEBREW_CELLAR.children.any?
            ohai "Formulae" if $stdout.tty? && !args.formula?
            system_command! "ls", args: [*ls_args, HOMEBREW_CELLAR], print_stdout: true
            puts if $stdout.tty? && !args.formula?
          end
          if !args.formula? && Cask::Caskroom.any_casks_installed?
            ohai "Casks" if $stdout.tty? && !args.cask?
            system_command! "ls", args: [*ls_args, Cask::Caskroom.path], print_stdout: true
          end
        else
          kegs, casks = args.named.to_kegs_to_casks

          if args.verbose? || !$stdout.tty?
            find_args = %w[-not -type d -not -name .DS_Store -print]
            system_command! "find", args: kegs.map(&:to_s) + find_args, print_stdout: true if kegs.present?
            system_command! "find", args: casks.map(&:caskroom_path) + find_args, print_stdout: true if casks.present?
          else
            kegs.each { |keg| PrettyListing.new keg } if kegs.present?
            Cask::List.list_casks(*casks, one: args.public_send(:"1?")) if casks.present?
          end
        end
      end

      private

      sig { params(name: String).returns(T.nilable(String)) }
      def pinned_formula_entry(name)
        pin_path = HOMEBREW_PINNED_KEGS/name
        return unless pin_path.symlink?

        "#{name}#{" #{pin_path.readlink.basename}" if args.versions?}"
      end

      sig { params(token: String).returns(T.nilable(String)) }
      def pinned_cask_entry(token)
        pin_path = HOMEBREW_PINNED_CASKS/token
        return if !pin_path.symlink? || !pin_path.exist?

        "#{token}#{" #{pin_path.resolved_path.basename}" if args.versions?}"
      end

      sig { void }
      def filtered_list
        names = if args.no_named?
          Formula.racks
        else
          racks = args.named.map { |n| Formulary.to_rack(n) }
          racks.select do |rack|
            Homebrew.failed = true unless rack.exist?
            rack.exist?
          end
        end
        names.sort.each do |d|
          versions = d.subdirs.map { |pn| pn.basename.to_s }
          next if args.multiple? && versions.length < 2

          puts "#{d.basename} #{versions * " "}"
        end
      end

      sig { void }
      def list_casks
        casks = if args.no_named?
          cask_paths = Cask::Caskroom.path.children.reject(&:file?).map do |path|
            if path.symlink?
              real_path = path.realpath
              real_path.basename.to_s
            else
              path.basename.to_s
            end
          end.uniq.sort
          cask_paths.map { |name| Cask::CaskLoader.load(name) }
        else
          filtered_args = args.named.dup.delete_if do |n|
            Homebrew.failed = true unless Cask::Caskroom.path.join(n).exist?
            !Cask::Caskroom.path.join(n).exist?
          end
          # NamedAargs subclasses array
          T.cast(filtered_args, Homebrew::CLI::NamedArgs).to_formulae_and_casks(only: :cask)
        end
        return if casks.blank?

        Cask::List.list_casks(
          *casks,
          one:       args.public_send(:"1?"),
          full_name: args.full_name?,
          versions:  args.versions?,
        )
      end
    end

    class PrettyListing
      sig { params(path: T.any(String, Pathname, Keg)).void }
      def initialize(path)
        valid_lib_extensions = [".cps", ".dylib", ".pc"]
        Pathname.new(path).children.sort_by { |p| p.to_s.downcase }.each do |pn|
          case pn.basename.to_s
          when "bin", "sbin"
            pn.find { |pnn| puts pnn unless pnn.directory? }
          when "lib"
            print_dir pn do |pnn|
              # dylibs have multiple symlinks and we don't care about them
              valid_lib_extensions.include?(pnn.extname) && !pnn.symlink?
            end
          when ".brew"
            next # Ignore .brew
          else
            if pn.directory?
              if pn.symlink?
                puts "#{pn} -> #{pn.readlink}"
              else
                print_dir pn
              end
            elsif Metafiles.list?(pn.basename.to_s)
              puts pn
            end
          end
        end
      end

      private

      sig { params(root: Pathname, block: T.nilable(T.proc.params(arg0: Pathname).returns(T::Boolean))).void }
      def print_dir(root, &block)
        dirs = []
        remaining_root_files = []
        other = ""

        root.children.sort.each do |pn|
          if pn.directory?
            dirs << pn
          elsif block && yield(pn)
            puts pn
            other = "other "
          elsif pn.basename.to_s != ".DS_Store"
            remaining_root_files << pn
          end
        end

        dirs.each do |d|
          files = []
          d.find { |pn| files << pn unless pn.directory? }
          print_remaining_files files, d
        end

        print_remaining_files remaining_root_files, root, other
      end

      sig { params(files: T::Array[Pathname], root: Pathname, other: String).void }
      def print_remaining_files(files, root, other = "")
        if files.length == 1
          puts files
        elsif files.length > 1
          puts "#{root}/ (#{files.length} #{other}files)"
        end
      end
    end
  end
end
