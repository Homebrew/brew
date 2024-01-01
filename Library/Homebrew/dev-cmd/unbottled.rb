# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"
require "api"
require "os/mac/xcode"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def unbottled_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Show the unbottled dependents of formulae.
      EOS
      flag   "--tag=",
             description: "Use the specified bottle tag (e.g. `big_sur`) instead of the current OS."
      switch "--dependents",
             description: "Skip getting analytics data and sort by number of dependents instead."
      switch "--total",
             description: "Print the number of unbottled and total formulae."
      switch "--lost",
             description: "Print the `homebrew/core` commits where bottles were lost in the last week."
      switch "--eval-all",
             description: "Evaluate all available formulae and casks, whether installed or not, to check them. " \
                          "Implied if `HOMEBREW_EVAL_ALL` is set."

      conflicts "--dependents", "--total", "--lost"

      named_args :formula
    end
  end

  sig { void }
  def unbottled
    args = unbottled_args.parse

    Formulary.enable_factory_cache!

    @bottle_tag = if (tag = args.tag)
      Utils::Bottles::Tag.from_symbol(tag.to_sym)
    else
      Utils::Bottles.tag
    end

    if args.lost?
      if args.named.present?
        raise UsageError, "`brew unbottled --lost` cannot be used with formula arguments!"
      elsif !CoreTap.instance.installed?
        raise UsageError, "`brew unbottled --lost` requires `homebrew/core` to be tapped locally!"
      else
        output_lost_bottles
        return
      end
    end

    os = @bottle_tag.system
    arch = if Hardware::CPU::INTEL_ARCHS.include?(@bottle_tag.arch)
      :intel
    elsif Hardware::CPU::ARM_ARCHS.include?(@bottle_tag.arch)
      :arm
    else
      raise "Unknown arch #{@bottle_tag.arch}."
    end

    Homebrew::SimulateSystem.with os: os, arch: arch do
      all = args.eval_all?
      if args.total?
        if !all && !Homebrew::EnvConfig.eval_all?
          raise UsageError, "`brew unbottled --total` needs `--eval-all` passed or `HOMEBREW_EVAL_ALL` set!"
        end

        all = true
      end

      if args.named.blank?
        ohai "Getting formulae..."
      elsif all
        raise UsageError, "Cannot specify formulae when using `--eval-all`/`--total`."
      end

      formulae, all_formulae, formula_installs =
        formulae_all_installs_from_args(args, all)
      deps_hash, uses_hash = deps_uses_from_formulae(all_formulae)

      if args.dependents?
        formula_dependents = {}
        formulae = formulae.sort_by do |f|
          dependents = uses_hash[f.name]&.length || 0
          formula_dependents[f.name] ||= dependents
        end.reverse
      elsif all
        output_total(formulae)
        return
      end

      noun, hash = if args.named.present?
        [nil, {}]
      elsif args.dependents?
        ["dependents", formula_dependents]
      else
        ["installs", formula_installs]
      end

      output_unbottled(formulae, deps_hash, noun, hash, args.named.present?)
    end
  end

  def formulae_all_installs_from_args(args, all)
    if args.named.present?
      formulae = all_formulae = args.named.to_formulae
    elsif args.dependents?
      if !args.eval_all? && !Homebrew::EnvConfig.eval_all?
        raise UsageError, "`brew unbottled --dependents` needs `--eval-all` passed or `HOMEBREW_EVAL_ALL` set!"
      end

      formulae = all_formulae = Formula.all(eval_all: args.eval_all?)

      @sort = " (sorted by number of dependents)"
    elsif all
      formulae = all_formulae = Formula.all(eval_all: args.eval_all?)
    else
      formula_installs = {}

      ohai "Getting analytics data..."
      analytics = Homebrew::API::Analytics.fetch "install", 90

      if analytics.blank?
        raise UsageError,
              "default sort by analytics data requires " \
              "`HOMEBREW_NO_GITHUB_API` and `HOMEBREW_NO_ANALYTICS` to be unset"
      end

      formulae = analytics["items"].map do |i|
        f = i["formula"].split.first
        next if f.include?("/")
        next if formula_installs[f].present?

        formula_installs[f] = i["count"]
        begin
          Formula[f]
        rescue FormulaUnavailableError
          nil
        end
      end.compact
      @sort = " (sorted by installs in the last 90 days; top 10,000 only)"

      all_formulae = Formula.all(eval_all: args.eval_all?)
    end

    # Remove deprecated formulae as we do not care if they are unbottled
    formulae = Array(formulae).reject(&:deprecated?) if formulae.present?
    all_formulae = Array(all_formulae).reject(&:deprecated?) if all_formulae.present?

    [formulae, all_formulae, formula_installs]
  end

  def deps_uses_from_formulae(all_formulae)
    ohai "Populating dependency tree..."

    deps_hash = {}
    uses_hash = {}

    all_formulae.each do |f|
      deps = Dependency.expand(f, cache_key: "unbottled") do |_, dep|
        Dependency.prune if dep.optional?
      end.map(&:to_formula)
      deps_hash[f.name] = deps

      deps.each do |dep|
        uses_hash[dep.name] ||= []
        uses_hash[dep.name] << f
      end
    end

    [deps_hash, uses_hash]
  end

  def output_total(formulae)
    ohai "Unbottled :#{@bottle_tag} formulae"
    unbottled_formulae = 0

    formulae.each do |f|
      next if f.bottle_specification.tag?(@bottle_tag)

      unbottled_formulae += 1
    end

    puts "#{unbottled_formulae}/#{formulae.length} remaining."
  end

  def output_unbottled(formulae, deps_hash, noun, hash, any_named_args)
    ohai ":#{@bottle_tag} bottle status#{@sort}"
    any_found = T.let(false, T::Boolean)

    formulae.each do |f|
      name = f.name.downcase

      if f.disabled?
        puts "#{Tty.bold}#{Tty.green}#{name}#{Tty.reset}: formula disabled" if any_named_args
        next
      end

      requirements = f.recursive_requirements
      if @bottle_tag.linux?
        if requirements.any? { |r| r.is_a?(MacOSRequirement) && !r.version }
          puts "#{Tty.bold}#{Tty.red}#{name}#{Tty.reset}: requires macOS" if any_named_args
          next
        end
      elsif requirements.any?(LinuxRequirement)
        puts "#{Tty.bold}#{Tty.red}#{name}#{Tty.reset}: requires Linux" if any_named_args
        next
      else
        macos_version = @bottle_tag.to_macos_version
        macos_satisfied = requirements.all? do |r|
          case r
          when MacOSRequirement
            next true unless r.version_specified?

            macos_version.compare(r.comparator, r.version)
          when XcodeRequirement
            next true unless r.version

            Version.new(MacOS::Xcode.latest_version(macos: macos_version)) >= r.version
          when ArchRequirement
            r.arch == @bottle_tag.arch
          else
            true
          end
        end
        unless macos_satisfied
          puts "#{Tty.bold}#{Tty.red}#{name}#{Tty.reset}: doesn't support this macOS" if any_named_args
          next
        end
      end

      if f.bottle_specification.tag?(@bottle_tag, no_older_versions: true)
        puts "#{Tty.bold}#{Tty.green}#{name}#{Tty.reset}: already bottled" if any_named_args
        next
      end

      deps = Array(deps_hash[f.name]).reject do |dep|
        dep.bottle_specification.tag?(@bottle_tag, no_older_versions: true)
      end

      if deps.blank?
        count = " (#{hash[f.name]} #{noun})" if noun
        puts "#{Tty.bold}#{Tty.green}#{name}#{Tty.reset}#{count}: ready to bottle"
        next
      end

      any_found ||= true
      count = " (#{hash[f.name]} #{noun})" if noun
      puts "#{Tty.bold}#{Tty.yellow}#{name}#{Tty.reset}#{count}: unbottled deps: #{deps.join(" ")}"
    end
    return if any_found
    return if any_named_args

    puts "No unbottled dependencies found!"
  end

  def output_lost_bottles
    ohai ":#{@bottle_tag} lost bottles"

    bottle_tag_regex_fragment = " +sha256.* #{@bottle_tag}: "

    # $ git log --patch --no-ext-diff -G'^ +sha256.* sonoma:' --since=@{'1 week ago'}
    git_log = %w[git log --patch --no-ext-diff]
    git_log << "-G^#{bottle_tag_regex_fragment}"
    git_log << "--since=@{'1 week ago'}"

    bottle_tag_sha_regex = /^[+-]#{bottle_tag_regex_fragment}/

    processed_formulae = Set.new
    commit = T.let(nil, T.nilable(String))
    formula = T.let(nil, T.nilable(String))
    lost_bottles = 0

    CoreTap.instance.path.cd do
      Utils.safe_popen_read(*git_log) do |io|
        io.each_line do |line|
          case line
          when /^commit [0-9a-f]{40}$/
            # Example match: `commit 7289b409b96a752540befef1a56b8a818baf1db7`
            if commit && formula && lost_bottles.positive? && processed_formulae.exclude?(formula)
              puts "#{commit}: bottle lost for #{formula}"
            end
            processed_formulae << formula
            commit = line.split.last
            formula = nil
          when %r{^diff --git a/Formula/}
            # Example match: `diff --git a/Formula/a/aws-cdk.rb b/Formula/a/aws-cdk.rb`
            formula = line.split("/").last.chomp(".rb\n")
            formula = CoreTap.instance.formula_renames.fetch(formula, formula)
            lost_bottles = 0
          when bottle_tag_sha_regex
            # Example match: `-    sha256 cellar: :any_skip_relocation, sonoma: "f0a4..."`
            next if processed_formulae.include?(formula)

            case line.chr
            when "+" then lost_bottles -= 1
            when "-" then lost_bottles += 1
            end
          when /^[+] +sha256.* all: /
            # Example match: `+    sha256 cellar: :any_skip_relocation, all: "9e35..."`
            lost_bottles -= 1
          end
        end
      end
    end

    return if !commit || !formula || !lost_bottles.positive? || processed_formulae.include?(formula)

    puts "#{commit}: bottle lost for #{formula}"
  end
end
