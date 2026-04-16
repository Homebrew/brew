# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "utils/git"
require "formulary"
require "software_spec"
require "tap"

module Homebrew
  module DevCmd
    class Extract < AbstractCommand
      BOTTLE_BLOCK_REGEX = /  bottle (?:do.+?end|:[a-z]+)\n\n/m

      cmd_args do
        usage_banner "`extract` [`--version=`] [`--git-revision=`] [`--force`] <formula> <tap>"
        description <<~EOS
          Look through repository history to find the most recent version of <formula> and
          create a copy in <tap>. Specifically, the command will create the new
          formula file at <tap>`/Formula/`<formula>`@`<version>`.rb`. If the tap is not
          installed yet, attempt to install/clone the tap before continuing. To extract
          a formula from a tap that is not `homebrew/core` use its fully-qualified form of
          <user>`/`<repo>`/`<formula>.
        EOS
        flag   "--git-revision=",
               description: "Search for the specified <version> of <formula> starting at <revision> instead of HEAD."
        flag   "--version=",
               description: "Extract the specified <version> of <formula> instead of the most recent."
        switch "-f", "--force",
               description: "Overwrite the destination formula if it already exists."

        named_args [:formula, :tap], number: 2, without_api: true
      end

      sig { override.void }
      def run
        if (tap_with_name = args.named.first&.then { Tap.with_formula_name(it) })
          source_tap, name = tap_with_name
        else
          name = args.named.fetch(0).downcase
          source_tap = CoreTap.instance
        end
        raise TapFormulaUnavailableError.new(source_tap, name) unless source_tap.installed?

        destination_tap = Tap.fetch(args.named.fetch(1))
        unless Homebrew::EnvConfig.developer?
          odie "Cannot extract formula to homebrew/core!" if destination_tap.core_tap?
          odie "Cannot extract formula to homebrew/cask!" if destination_tap.core_cask_tap?
          odie "Cannot extract formula to the same tap!" if destination_tap == source_tap
        end
        destination_tap.install unless destination_tap.installed?

        repo = source_tap.path
        start_rev = args.git_revision || "HEAD"
        pattern = if source_tap.core_tap?
          [source_tap.new_formula_path(name), repo/"Formula/#{name}.rb"].uniq
        else
          # A formula can technically live in the root directory of a tap or in any of its subdirectories
          [repo/"#{name}.rb", repo/"**/#{name}.rb"]
        end

        rev = T.let(nil, T.nilable(String))
        if args.version
          ohai "Searching repository history"
          version = args.version
          version_segments = Gem::Version.new(version).segments if Gem::Version.correct?(version)
          test_formula = T.let(nil, T.nilable(Formula))
          result = ""
          loop do
            rev = rev.nil? ? start_rev : "#{rev}~1"
            rev, (path,) = Utils::Git.last_revision_commit_of_files(repo, pattern, before_commit: rev)
            if rev.nil? && source_tap.shallow?
              odie <<~EOS
                Could not find #{name} but #{source_tap} is a shallow clone!
                Try again after running:
                  git -C "#{source_tap.path}" fetch --unshallow
              EOS
            elsif rev.nil?
              odie "Could not find #{name}! The formula or version may not have existed."
            end

            file = repo/T.must(path)
            result = Utils::Git.last_revision_of_file(repo, file, before_commit: rev)
            if result.empty?
              odebug "Skipping revision #{rev} - file is empty at this revision"
              next
            end

            test_formula = formula_at_revision(repo, name, file, rev)
            break if test_formula.nil? || test_formula.version == version

            if version_segments && Gem::Version.correct?(test_formula.version)
              test_formula_version_segments = Gem::Version.new(test_formula.version).segments
              if version_segments.length < test_formula_version_segments.length
                odebug "Apply semantic versioning with #{test_formula_version_segments}"
                break if version_segments == test_formula_version_segments.first(version_segments.length)
              end
            end

            odebug "Trying #{test_formula.version} from revision #{rev} against desired #{version}"
          end
          odie "Could not find #{name}! The formula or version may not have existed." if test_formula.nil?
        else
          # Search in the root directory of `repository` as well as recursively in all of its subdirectories.
          files = if start_rev == "HEAD"
            Dir[repo/"{,**/}"].filter_map do |dir|
              Pathname.glob("#{dir}/#{name}.rb").find(&:file?)
            end
          else
            []
          end

          if files.empty?
            ohai "Searching repository history"
            rev, (path,) = Utils::Git.last_revision_commit_of_files(repo, pattern, before_commit: start_rev)
            odie "Could not find #{name}! The formula or version may not have existed." if rev.nil?
            file = repo/T.must(path)
            version = T.must(formula_at_revision(repo, name, file, rev)).version
            result = Utils::Git.last_revision_of_file(repo, file)
          else
            file = files.fetch(0).realpath
            rev = "HEAD"
            version = Formulary.factory(file).version
            result = File.read(file)
          end
        end

        # The class name has to be renamed to match the new filename,
        # e.g. Foo version 1.2.3 becomes FooAT123 and resides in Foo@1.2.3.rb.
        class_name = Formulary.class_s(name)

        # The version can only contain digits with decimals in between.
        version_string = version.to_s
                                .sub(/\D*(.+?)\D*$/, "\\1")
                                .gsub(/\D+/, ".")

        # Remove any existing version suffixes, as a new one will be added later.
        name.sub!(/\b@(.*)\z/i, "")
        versioned_name = Formulary.class_s("#{name}@#{version_string}")
        result.sub!("class #{class_name} < Formula", "class #{versioned_name} < Formula")

        # Remove bottle blocks, as they won't work.
        result.sub!(BOTTLE_BLOCK_REGEX, "")

        path = destination_tap.path/"Formula/#{name}@#{version_string}.rb"
        if path.exist?
          unless args.force?
            odie <<~EOS
              Destination formula already exists: #{path}
              To overwrite it and continue anyways, run:
                brew extract --force --version=#{version} #{name} #{destination_tap.name}
            EOS
          end
          odebug "Overwriting existing formula at #{path}"
          path.delete
        end
        ohai "Writing formula for #{name} at #{version} from revision #{rev} to:", path
        path.dirname.mkpath
        path.write result
      end

      private

      sig { params(repo: Pathname, name: String, file: Pathname, rev: String).returns(T.nilable(Formula)) }
      def formula_at_revision(repo, name, file, rev)
        return if rev.empty?

        contents = Utils::Git.last_revision_of_file(repo, file, before_commit: rev)
        contents.gsub!("@url=", "url ")
        contents.gsub!("require 'brewkit'", "require 'formula'")
        contents.sub!(BOTTLE_BLOCK_REGEX, "")
        with_monkey_patch { Formulary.from_contents(name, file, contents, ignore_errors: true) }
      end

      sig { params(klass: T::Module[T.anything], method_name: Symbol).returns(T.nilable(Symbol)) }
      def method_visibility(klass, method_name)
        if klass.private_method_defined?(method_name, false)
          :private
        elsif klass.method_defined?(method_name, false)
          klass.public_method_defined?(method_name) ? :public : :protected
        end
      end

      sig { type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
      def with_monkey_patch(&_block)
        bs_vis = method_visibility(BottleSpecification, :method_missing)
        mod_vis = method_visibility(Module, :method_missing)
        res_vis = method_visibility(Resource, :method_missing)
        dc_vis = method_visibility(DependencyCollector, :parse_symbol_spec)

        bs_mm = BottleSpecification.instance_method(:method_missing) if bs_vis
        mod_mm = Module.instance_method(:method_missing) if mod_vis
        res_mm = Resource.instance_method(:method_missing) if res_vis
        dc_pss = DependencyCollector.instance_method(:parse_symbol_spec) if dc_vis

        BottleSpecification.class_eval { private define_method(:method_missing) { |*_| nil } }
        Module.class_eval { private define_method(:method_missing) { |*_| nil } }
        Resource.class_eval { private define_method(:method_missing) { |*_| nil } }
        DependencyCollector.class_eval { private define_method(:parse_symbol_spec) { |*_| nil } }

        yield
      ensure
        if (mm = bs_mm) && (vis = bs_vis)
          BottleSpecification.class_eval do
            define_method(:method_missing, mm)
            private(:method_missing) if vis == :private
            protected(:method_missing) if vis == :protected
          end
        else
          BottleSpecification.class_eval { remove_method(:method_missing) }
        end
        if (mm = mod_mm) && (vis = mod_vis)
          Module.class_eval do
            define_method(:method_missing, mm)
            private(:method_missing) if vis == :private
            protected(:method_missing) if vis == :protected
          end
        else
          Module.class_eval { remove_method(:method_missing) }
        end
        if (mm = res_mm) && (vis = res_vis)
          Resource.class_eval do
            define_method(:method_missing, mm)
            private(:method_missing) if vis == :private
            protected(:method_missing) if vis == :protected
          end
        else
          Resource.class_eval { remove_method(:method_missing) }
        end
        if (pss = dc_pss) && (vis = dc_vis)
          DependencyCollector.class_eval do
            define_method(:parse_symbol_spec, pss)
            private(:parse_symbol_spec) if vis == :private
            protected(:parse_symbol_spec) if vis == :protected
          end
        else
          DependencyCollector.class_eval { remove_method(:parse_symbol_spec) }
        end
      end
    end
  end
end
