# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"

module Homebrew
  module DevCmd
    class Typecheck < AbstractCommand
      include FileUtils

      cmd_args do
        description <<~EOS
          Check for typechecking errors using Sorbet.
        EOS
        switch "--fix",
               description: "Automatically fix type errors."
        switch "-q", "--quiet",
               description: "Silence all non-critical errors."
        switch "--update",
               description: "Update RBI files."
        switch "--update-all",
               description: "Update all RBI files rather than just updated gems."
        switch "--suggest-typed",
               depends_on:  "--update",
               description: "Try upgrading `typed` sigils."
        switch "--lsp",
               description: "Start the Sorbet LSP server."
        flag   "--dir=",
               description: "Typecheck all files in a specific directory."
        flag   "--file=",
               description: "Typecheck a single file."
        flag   "--ignore=",
               description: "Ignores input files that contain the given string " \
                            "in their paths (relative to the input path passed to Sorbet)."

        conflicts "--dir", "--file"
        conflicts "--lsp", "--update"
        conflicts "--lsp", "--update-all"
        conflicts "--lsp", "--fix"

        named_args :tap
      end

      sig { override.void }
      def run
        if (args.dir.present? || args.file.present?) && args.named.present?
          raise UsageError, "Cannot use `--dir` or `--file` when specifying a tap."
        elsif args.fix? && args.named.present?
          raise UsageError, "Cannot use `--fix` when specifying a tap."
        end

        update = args.update? || args.update_all?
        groups = update ? Homebrew.valid_gem_groups : ["typecheck"]
        Homebrew.install_bundler_gems!(groups:)

        # Sorbet doesn't use bash privileged mode so we align EUID and UID here.
        Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid

        HOMEBREW_LIBRARY_PATH.cd do
          if update
            workers = args.debug? ? ["--workers=1"] : []
            safe_system "bundle", "exec", "tapioca", "annotations"
            safe_system "bundle", "exec", "tapioca", "dsl", *workers
            # Prefer adding args here: Library/Homebrew/sorbet/tapioca/config.yml
            tapioca_args = args.update_all? ? ["--all"] : []

            ohai "Updating Tapioca RBI files..."
            safe_system "bundle", "exec", "tapioca", "gem", *tapioca_args

            ohai "Trimming RuboCop RBI because by default it's massive..."
            trim_rubocop_rbi

            if args.suggest_typed?
              ohai "Checking if we can bump Sorbet `typed` sigils..."
              # --sorbet needed because of https://github.com/Shopify/spoom/issues/488
              system "bundle", "exec", "spoom", "srb", "bump", "--from", "false", "--to", "true",
                     "--sorbet", "#{Gem.bin_path("sorbet", "srb")} tc"
              system "bundle", "exec", "spoom", "srb", "bump", "--from", "true", "--to", "strict",
                     "--sorbet", "#{Gem.bin_path("sorbet", "srb")} tc"
            end

            return
          end

          srb_exec = %w[bundle exec srb tc]

          srb_exec << "--quiet" if args.quiet?

          if args.fix?
            # Auto-correcting method names is almost always wrong.
            srb_exec << "--suppress-error-code" << "7003"

            srb_exec << "--autocorrect"
          end

          if args.lsp?
            srb_exec << "--lsp"
            if (watchman = which("watchman", ORIGINAL_PATHS))
              srb_exec << "--watchman-path" << watchman
            else
              srb_exec << "--disable-watchman"
            end
          end

          srb_exec += ["--ignore", args.ignore] if args.ignore.present?
          if args.file.present? || args.dir.present? || (tap_dir = args.named.to_paths(only: :tap).first).present?
            cd("sorbet") do
              srb_exec += ["--file", "../#{args.file}"] if args.file
              srb_exec += ["--dir", "../#{args.dir}"] if args.dir
              srb_exec += ["--dir", tap_dir.to_s] if tap_dir
            end
          end
          success = system(*srb_exec)
          return if success

          $stderr.puts "Check #{Formatter.url("https://docs.brew.sh/Typechecking")} for " \
                       "more information on how to resolve these errors."
          Homebrew.failed = true
        end
      end

      sig { params(path: T.any(String, Pathname)).void }
      def trim_rubocop_rbi(path: HOMEBREW_LIBRARY_PATH/"sorbet/rbi/gems/rubocop@*.rbi")
        rbi_file = Dir.glob(path).first
        return unless rbi_file.present?
        return unless (rbi_path = Pathname.new(rbi_file)).exist?

        require "prism"
        original_content = rbi_path.read
        parsed = Prism.parse(original_content)
        return unless parsed.success?

        allowlist = %w[
          Parser::Source
          RuboCop::AST::Node
          RuboCop::AST::NodePattern
          RuboCop::AST::ProcessedSource
          RuboCop::CLI
          RuboCop::Config
          RuboCop::Cop::AllowedPattern
          RuboCop::Cop::AllowedMethods
          RuboCop::Cop::AutoCorrector
          RuboCop::Cop::AutocorrectLogic
          RuboCop::Cop::Base
          RuboCop::Cop::CommentsHelp
          RuboCop::Cop::ConfigurableFormatting
          RuboCop::Cop::ConfigurableNaming
          RuboCop::Cop::Corrector
          RuboCop::Cop::IgnoredMethods
          RuboCop::Cop::IgnoredNode
          RuboCop::Cop::IgnoredPattern
          RuboCop::Cop::MethodPreference
          RuboCop::Cop::Offense
          RuboCop::Cop::RangeHelp
          RuboCop::Cop::Registry
          RuboCop::Cop::Util
          RuboCop::DirectiveComment
          RuboCop::Error
          RuboCop::ExcludeLimit
          RuboCop::Ext::Comment
          RuboCop::Ext::ProcessedSource
          RuboCop::Ext::Range
          RuboCop::FileFinder
          RuboCop::Formatter::TextUtil
          RuboCop::Formatter::PathUtil
          RuboCop::Options
          RuboCop::ResultCache
          RuboCop::Runner
          RuboCop::TargetFinder
          RuboCop::Version
        ].freeze

        nodes_to_keep = Set.new

        parsed.value.statements.body.each do |node|
          case node
          when Prism::ModuleNode, Prism::ClassNode
            # Keep if it's in our allowlist or is a top-level essential node.
            full_name = extract_full_name(node)
            nodes_to_keep << node if full_name.blank? || allowlist.any? { |name| full_name.start_with?(name) }
          when Prism::ConstantWriteNode # Keep essential constants.
            nodes_to_keep << node if node.name.to_s.match?(/^[[:digit:][:upper:]_]+$/)
          else # Keep other top-level nodes (comments, etc.)
            nodes_to_keep << node
          end
        end

        new_content = generate_trimmed_rbi(original_content, nodes_to_keep, parsed)
        rbi_path.write(new_content)
      end

      private

      sig { params(node: Prism::Node).returns(String) }
      def extract_full_name(node)
        case node
        when Prism::ModuleNode, Prism::ClassNode
          parts = []

          constant_path = node.constant_path
          if constant_path.is_a?(Prism::ConstantReadNode)
            parts << constant_path.name.to_s
          elsif constant_path.is_a?(Prism::ConstantPathNode)
            parts.concat(extract_constant_path_parts(constant_path))
          end

          parts.join("::")
        else
          ""
        end
      end

      sig { params(constant_path: T.any(Prism::ConstantPathNode, Prism::Node)).returns(T::Array[String]) }
      def extract_constant_path_parts(constant_path)
        parts = []
        current = T.let(constant_path, T.nilable(Prism::Node))

        while current
          case current
          when Prism::ConstantPathNode
            parts.unshift(current.name.to_s)
            current = current.parent
          when Prism::ConstantReadNode
            parts.unshift(current.name.to_s)
            break
          else
            break
          end
        end

        parts
      end

      sig {
        params(
          original_content: String,
          nodes_to_keep:    T::Set[Prism::Node],
          parsed:           Prism::ParseResult,
        ).returns(String)
      }
      def generate_trimmed_rbi(original_content, nodes_to_keep, parsed)
        lines = original_content.lines
        output_lines = []

        first_node = parsed.value.statements.body.first
        if first_node
          first_line = first_node.location.start_line - 1
          (0...first_line).each { |i| output_lines << lines[i] if lines[i] }
        end

        parsed.value.statements.body.each do |node|
          next unless nodes_to_keep.include?(node)

          start_line = node.location.start_line - 1
          end_line = node.location.end_line - 1

          (start_line..end_line).each { |i| output_lines << lines[i] if lines[i] }
          output_lines << "\n"
        end

        header = <<~EOS.chomp
          # typed: true

          # This file is autogenerated. Do not edit it by hand.
          # To regenerate, run `brew typecheck --update rubocop`.
        EOS

        return header if output_lines.empty?

        output_lines.join
      end
    end
  end
end
