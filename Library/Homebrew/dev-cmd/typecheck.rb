# typed: true
# frozen_string_literal: true

require "cli/parser"

module Homebrew
  sig { returns(CLI::Parser) }
  def self.typecheck_args
    Homebrew::CLI::Parser.new do
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
      flag   "--dir=",
             description: "Typecheck all files in a specific directory."
      flag   "--file=",
             description: "Typecheck a single file."
      flag   "--ignore=",
             description: "Ignores input files that contain the given string " \
                          "in their paths (relative to the input path passed to Sorbet)."

      conflicts "--dir", "--file"

      named_args :none
    end
  end

  sig { void }
  def self.typecheck
    args = typecheck_args.parse

    update = args.update? || args.update_all?
    groups = update ? Homebrew.valid_gem_groups : ["typecheck"]
    Homebrew.install_bundler_gems!(groups: groups)

    HOMEBREW_LIBRARY_PATH.cd do
      if update
        excluded_gems = [
          "json", # RBI file is already provided by Sorbet
        ]
        tapioca_args = ["--exclude", *excluded_gems, "--pre", "sorbet/tapioca/prerequire.rb"]
        tapioca_args << "--all" if args.update_all?

        ohai "Updating homegrown RBI files..."
        safe_system "bundle", "exec", "ruby", "sorbet/custom_generators/tty.rb"
        safe_system "bundle", "exec", "ruby", "sorbet/custom_generators/env_config.rb"

        ohai "Updating Tapioca RBI files..."
        safe_system "bundle", "exec", "tapioca", "gem", *tapioca_args
        safe_system "bundle", "exec", "parlour"

        safe_system({ "RUBYLIB" => "#{HOMEBREW_LIBRARY_PATH}/sorbet/hidden_definitions_hacks" },
                    "bundle", "exec", "srb", "rbi", "hidden-definitions")
        # HACK: we'll phase out hidden-definitions soon
        tmp_file = "sorbet/rbi/hidden-definitions/hidden.rbi.tmp"
        orig_file = "sorbet/rbi/hidden-definitions/hidden.rbi"
        File.open(tmp_file, "w") do |out_file|
          File.foreach(orig_file) do |line|
            out_file.puts line unless line.include?("def self.new(*args, **arg, &blk); end")
          end
        end
        File.rename(tmp_file, orig_file)

        if args.suggest_typed?
          ohai "Bumping Sorbet `typed` sigils..."
          # --sorbet needed because of https://github.com/Shopify/spoom/issues/488
          safe_system "bundle", "exec", "spoom", "bump", "--dry", "--sorbet", "#{Gem.bin_path("sorbet", "srb")} tc"
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

      srb_exec += ["--ignore", args.ignore] if args.ignore.present?
      if args.file.present? || args.dir.present?
        cd("sorbet") do
          srb_exec += ["--file", "../#{args.file}"] if args.file
          srb_exec += ["--dir", "../#{args.dir}"] if args.dir
        end
      end
      success = system(*srb_exec)
      return if success

      $stderr.puts "Check #{Formatter.url("https://docs.brew.sh/Typechecking")} for " \
                   "more information on how to resolve these errors."
      Homebrew.failed = true
    end
  end
end
