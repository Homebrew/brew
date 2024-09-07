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
        switch "--multiple",
               depends_on:  "--versions",
               description: "Only show formulae with multiple versions installed."
        switch "--pinned",
               description: "List only pinned formulae, or only the specified (pinned) " \
                            "formulae if <formula> are provided. See also `pin`, `unpin`."
        switch "--installed-on-request",
               description: "List the formulae installed on request."
        switch "--installed-as-dependency",
               description: "List the formulae installed as dependencies."
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
               description: "Reverse the order of the formulae and/or casks sort to list the oldest entries first. " \
                            "Has no effect when a formula or cask name is passed as an argument."
        switch "-t",
               description: "Sort formulae and/or casks by time modified, listing most recently modified first. " \
                            "Has no effect when a formula or cask name is passed as an argument."

        conflicts "--formula", "--cask"
        conflicts "--pinned", "--cask"
        conflicts "--multiple", "--cask"
        conflicts "--pinned", "--multiple"
        ["--installed-on-request", "--installed-as-dependency",
         "--poured-from-bottle", "--built-from-source"].each do |flag|
          conflicts "--cask", flag
          conflicts "--versions", flag
          conflicts "--pinned", flag
        end
        ["-1", "-l", "-r", "-t"].each do |flag|
          conflicts "--versions", flag
          conflicts "--pinned", flag
        end
        ["--versions", "--pinned",
         "---installed-on-request", "--installed-as-dependency",
         "--poured-from-bottle", "--built-from-source",
         "-l", "-r", "-t"].each do |flag|
          conflicts "--full-name", flag
        end

        named_args [:installed_formula, :installed_cask]
      end

      sig { override.void }
      def run
        if args.full_name?
          unless args.cask?
            formula_names = args.no_named? ? Formula.installed : args.named.to_resolved_formulae
            full_formula_names = formula_names.map(&:full_name).sort(&tap_and_name_comparison)
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
                               .map(&:full_name).sort(&tap_and_name_comparison)
            full_cask_names = Formatter.columns(full_cask_names) unless args.public_send(:"1?")
            puts full_cask_names if full_cask_names.present?
          end
        elsif args.pinned?
          filtered_list
        elsif args.versions?
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

          Formula.installed.sort.each do |formula|
            tab = Tab.for_formula(formula)

            statuses = []
            statuses << "installed on request" if args.installed_on_request? && tab.installed_on_request
            statuses << "installed as dependency" if args.installed_as_dependency? && tab.installed_as_dependency
            statuses << "poured from bottle" if args.poured_from_bottle? && tab.poured_from_bottle
            statuses << "built from source" if args.built_from_source? && !tab.poured_from_bottle
            next if statuses.empty?

            if flags.count > 1
              puts "#{formula.name}: #{statuses.join(", ")}"
            else
              puts formula.name
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
            safe_system "ls", *ls_args, HOMEBREW_CELLAR
            puts if $stdout.tty? && !args.formula?
          end
          if !args.formula? && Cask::Caskroom.any_casks_installed?
            ohai "Casks" if $stdout.tty? && !args.cask?
            safe_system "ls", *ls_args, Cask::Caskroom.path
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
        if args.pinned?
          pinned_versions = {}
          names.sort.each do |d|
            keg_pin = (HOMEBREW_PINNED_KEGS/d.basename.to_s)
            pinned_versions[d] = keg_pin.readlink.basename.to_s if keg_pin.exist? || keg_pin.symlink?
          end
          pinned_versions.each do |d, version|
            puts d.basename.to_s.concat(args.versions? ? " #{version}" : "")
          end
        else # --versions without --pinned
          names.sort.each do |d|
            versions = d.subdirs.map { |pn| pn.basename.to_s }
            next if args.multiple? && versions.length < 2

            puts "#{d.basename} #{versions * " "}"
          end
        end
      end

      sig { void }
      def list_casks
        casks = if args.no_named?
          Cask::Caskroom.casks
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
        Pathname.new(path).children.sort_by { |p| p.to_s.downcase }.each do |pn|
          case pn.basename.to_s
          when "bin", "sbin"
            pn.find { |pnn| puts pnn unless pnn.directory? }
          when "lib"
            print_dir pn do |pnn|
              # dylibs have multiple symlinks and we don't care about them
              (pnn.extname == ".dylib" || pnn.extname == ".pc") && !pnn.symlink?
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
