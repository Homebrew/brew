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
        formula = T.let(nil, T.nilable(Formula))
        version = args.version
        ohai "Searching repository history"
        if args.version
          version_segments = Gem::Version.new(version).segments if Gem::Version.correct?(version)
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
            elsif rev.nil? || path.nil?
              odie "Could not find #{name}! The formula or version may not have existed."
            end

            file = repo/path
            result = Utils::Git.last_revision_of_file(repo, file, before_commit: rev)
            if result.empty?
              odebug "Skipping revision #{rev} - file is empty at this revision"
              next
            end

            formula = formula_at_revision(repo, name, file, rev)
            break if formula.nil? || formula.version == version

            if version_segments && Gem::Version.correct?(formula.version)
              test_formula_version_segments = Gem::Version.new(formula.version).segments
              if version_segments.length < test_formula_version_segments.length
                odebug "Apply semantic versioning with #{test_formula_version_segments}"
                break if version_segments == test_formula_version_segments.first(version_segments.length)
              end
            end

            odebug "Trying #{formula.version} from revision #{rev} against desired #{version}"
          end
        else
          rev, (path,) = Utils::Git.last_revision_commit_of_files(repo, pattern, before_commit: start_rev)
          odie "Could not find #{name}! The formula or version may not have existed." if rev.nil? || path.nil?
          file = repo/path
          formula = formula_at_revision(repo, name, file, rev)
          result = Utils::Git.file_at_commit(repo, file, rev)
        end
        odie "Could not find #{name}! The formula or version may not have existed." if formula.nil?
        version ||= formula.version

        # The class name has to be renamed to match the new filename,
        # e.g. Foo version 1.2.3 becomes FooAT123 and resides in Foo@1.2.3.rb.
        class_name = Formulary.class_s(name)

        # The version can only contain digits with decimals in between.
        version_string = version.to_s
                                .sub(/\D*(.+?)\D*$/, "\\1")
                                .gsub(/\D+/, ".")

        # Remove any existing version suffixes, as a new one will be added later.
        name.sub!(/\b@.*\z\b/i, "")
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

        patches = formula.patchlist + formula.resources.flat_map(&:patches)
        patches.grep(LocalPatch).map { |patch| Pathname(patch.file).cleanpath }.uniq.each do |patch_file|
          patch_contents = Utils::Git.file_at_commit(repo, patch_file, rev)
          odie "Could not find #{patch_file} at revision #{rev}!" if patch_contents.blank?

          patch_path = destination_tap.path/patch_file
          if patch_path.exist?
            next if patch_path.read == patch_contents

            odie <<~EOS unless args.force?
              Destination patch already exists: #{patch_path}
              To overwrite it and continue anyways, run:
                brew extract --force --version=#{version} #{name} #{destination_tap.name}
            EOS
            odebug "Overwriting existing patch at #{patch_path}"
            patch_path.delete
          end
          ohai "Writing #{patch_file} from revision #{rev} to:", patch_path
          patch_path.dirname.mkpath
          patch_path.write patch_contents
        end
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

      sig { params(_block: T.proc.void).returns(T.untyped) }
      def with_monkey_patch(&_block)
        DependencyCollector.clear_cache

        BottleSpecification.class_eval do
          if method_defined?(:method_missing) || private_method_defined?(:method_missing)
            send(:alias_method, :old_method_missing, :method_missing)
            send(:private, :old_method_missing)
          end
          define_method(:method_missing) do |*_|
            # do nothing
          end
          send(:private, :method_missing)
        end

        Module.class_eval do
          if method_defined?(:method_missing) || private_method_defined?(:method_missing)
            send(:alias_method, :old_method_missing, :method_missing)
            send(:private, :old_method_missing)
          end
          define_method(:method_missing) do |*_|
            # do nothing
          end
          send(:private, :method_missing)
        end

        Resource.class_eval do
          if method_defined?(:method_missing) || private_method_defined?(:method_missing)
            send(:alias_method, :old_method_missing, :method_missing)
            send(:private, :old_method_missing)
          end
          define_method(:method_missing) do |*_|
            # do nothing
          end
          send(:private, :method_missing)
        end

        DependencyCollector.class_eval do
          if method_defined?(:parse_symbol_spec) || private_method_defined?(:parse_symbol_spec)
            send(:alias_method, :old_parse_symbol_spec, :parse_symbol_spec)
            send(:private, :old_parse_symbol_spec)
          end
          define_method(:parse_symbol_spec) do |*_|
            # do nothing
          end
          send(:private, :parse_symbol_spec)
        end

        yield
      ensure
        BottleSpecification.class_eval do
          if method_defined?(:old_method_missing) || private_method_defined?(:old_method_missing)
            send(:alias_method, :method_missing, :old_method_missing)
            send(:private, :method_missing)
            send(:undef_method, :old_method_missing)
          end
        end

        Module.class_eval do
          if method_defined?(:old_method_missing) || private_method_defined?(:old_method_missing)
            send(:alias_method, :method_missing, :old_method_missing)
            send(:private, :method_missing)
            send(:undef_method, :old_method_missing)
          end
        end

        Resource.class_eval do
          if method_defined?(:old_method_missing) || private_method_defined?(:old_method_missing)
            send(:alias_method, :method_missing, :old_method_missing)
            send(:private, :method_missing)
            send(:undef_method, :old_method_missing)
          end
        end

        DependencyCollector.class_eval do
          if method_defined?(:old_parse_symbol_spec) || private_method_defined?(:old_parse_symbol_spec)
            send(:alias_method, :parse_symbol_spec, :old_parse_symbol_spec)
            send(:private, :parse_symbol_spec)
            send(:undef_method, :old_parse_symbol_spec)
          end
        end
        DependencyCollector.clear_cache
      end
    end
  end
end
