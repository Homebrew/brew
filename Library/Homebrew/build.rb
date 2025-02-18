# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# This script is loaded by formula_installer as a separate instance.
# Thrown exceptions are propagated back to the parent process over a pipe

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

old_trap = trap("INT") { exit! 130 }

require_relative "global"
require "build_options"
require "keg"
require "extend/ENV"
require "fcntl"
require "utils/socket"
require "cmd/install"
require "json/add/exception"

# A formula build.
class Build
  attr_reader :formula, :deps, :reqs, :args

  def initialize(formula, options, args:)
    @formula = formula
    @formula.build = BuildOptions.new(options, formula.options)
    @args = args

    if args.ignore_dependencies?
      @deps = []
      @reqs = []
    else
      @deps = expand_deps
      @reqs = expand_reqs
    end
  end

  def effective_build_options_for(dependent)
    args  = dependent.build.used_options
    args |= Tab.for_formula(dependent).used_options
    BuildOptions.new(args, dependent.options)
  end

  def expand_reqs
    formula.recursive_requirements do |dependent, req|
      build = effective_build_options_for(dependent)
      if req.prune_from_option?(build) || req.prune_if_build_and_not_dependent?(dependent, formula) || req.test?
        Requirement.prune
      end
    end
  end

  def expand_deps
    formula.recursive_dependencies do |dependent, dep|
      build = effective_build_options_for(dependent)
      if dep.prune_from_option?(build) ||
         dep.prune_if_build_and_not_dependent?(dependent, formula) ||
         (dep.test? && !dep.build?) || dep.implicit?
        Dependency.prune
      elsif dep.build?
        Dependency.keep_but_prune_recursive_deps
      end
    end
  end

  def install
    formula_deps = deps.map(&:to_formula)
    keg_only_deps = formula_deps.select(&:keg_only?)
    run_time_deps = deps.reject(&:build?).map(&:to_formula)

    formula_deps.each do |dep|
      fixopt(dep) unless dep.opt_prefix.directory?
    end

    ENV.activate_extensions!(env: args.env)

    if superenv?(args.env)
      superenv = T.cast(ENV, Superenv)
      superenv.keg_only_deps = keg_only_deps
      superenv.deps = formula_deps
      superenv.run_time_deps = run_time_deps
      ENV.setup_build_environment(
        formula:,
        cc:            args.cc,
        build_bottle:  args.build_bottle?,
        bottle_arch:   args.bottle_arch,
        debug_symbols: args.debug_symbols?,
      )
      reqs.each do |req|
        req.modify_build_environment(
          env: args.env, cc: args.cc, build_bottle: args.build_bottle?, bottle_arch: args.bottle_arch,
        )
      end
    else
      ENV.setup_build_environment(
        formula:,
        cc:            args.cc,
        build_bottle:  args.build_bottle?,
        bottle_arch:   args.bottle_arch,
        debug_symbols: args.debug_symbols?,
      )
      reqs.each do |req|
        req.modify_build_environment(
          env: args.env, cc: args.cc, build_bottle: args.build_bottle?, bottle_arch: args.bottle_arch,
        )
      end

      keg_only_deps.each do |dep|
        ENV.prepend_path "PATH", dep.opt_bin.to_s
        ENV.prepend_path "PKG_CONFIG_PATH", "#{dep.opt_lib}/pkgconfig"
        ENV.prepend_path "PKG_CONFIG_PATH", "#{dep.opt_share}/pkgconfig"
        ENV.prepend_path "ACLOCAL_PATH", "#{dep.opt_share}/aclocal"
        ENV.prepend_path "CMAKE_PREFIX_PATH", dep.opt_prefix.to_s
        ENV.prepend "LDFLAGS", "-L#{dep.opt_lib}" if dep.opt_lib.directory?
        ENV.prepend "CPPFLAGS", "-I#{dep.opt_include}" if dep.opt_include.directory?
      end
    end

    new_env = {
      "TMPDIR" => HOMEBREW_TEMP,
      "TEMP"   => HOMEBREW_TEMP,
      "TMP"    => HOMEBREW_TEMP,
    }

    with_env(new_env) do
      if args.debug? && !Homebrew::EnvConfig.disable_debrew?
        require "debrew"
        formula.extend(Debrew::Formula)
      end

      formula.update_head_version

      formula.brew(
        fetch:         false,
        keep_tmp:      args.keep_tmp?,
        debug_symbols: args.debug_symbols?,
        interactive:   args.interactive?,
      ) do
        with_env(
          # For head builds, HOMEBREW_FORMULA_PREFIX should include the commit,
          # which is not known until after the formula has been staged.
          HOMEBREW_FORMULA_PREFIX:    formula.prefix,
          # https://reproducible-builds.org/docs/build-path/
          HOMEBREW_FORMULA_BUILDPATH: formula.buildpath,
          # https://reproducible-builds.org/docs/source-date-epoch/
          SOURCE_DATE_EPOCH:          formula.source_modified_time.to_i.to_s,
          # Avoid make getting confused about timestamps.
          # https://github.com/Homebrew/homebrew-core/pull/87470
          TZ:                         "UTC0",
        ) do
          if args.git?
            formula.selective_patch(is_data: false)
            system "git", "init"
            system "git", "add", "-A"
            formula.selective_patch(is_data: true)
          else
            formula.patch
          end

          if args.interactive?
            ohai "Entering interactive mode..."
            puts <<~EOS
              Type `exit` to return and finalize the installation.
              Install to this prefix: #{formula.prefix}
            EOS

            if args.git?
              puts <<~EOS
                This directory is now a Git repository. Make your changes and then use:
                  git diff | pbcopy
                to copy the diff to the clipboard.
              EOS
            end

            interactive_shell(formula)
          else
            formula.prefix.mkpath
            formula.logs.mkpath

            (formula.logs/"00.options.out").write \
              "#{formula.full_name} #{formula.build.used_options.sort.join(" ")}".strip
            formula.install

            stdlibs = detect_stdlibs
            tab = Tab.create(formula, ENV.compiler, stdlibs.first)
            tab.write

            # Find and link metafiles
            formula.prefix.install_metafiles formula.buildpath
            formula.prefix.install_metafiles formula.libexec if formula.libexec.exist?

            normalize_pod2man_outputs!(formula)
          end
        end
      end
    end
  end

  def detect_stdlibs
    keg = Keg.new(formula.prefix)

    # The stdlib recorded in the install receipt is used during dependency
    # compatibility checks, so we only care about the stdlib that libraries
    # link against.
    keg.detect_cxx_stdlibs(skip_executables: true)
  end

  def fixopt(formula)
    path = if formula.linked_keg.directory? && formula.linked_keg.symlink?
      formula.linked_keg.resolved_path
    elsif formula.prefix.directory?
      formula.prefix
    elsif (kids = formula.rack.children).size == 1 && kids.first.directory?
      kids.first
    else
      raise
    end
    Keg.new(path).optlink(verbose: args.verbose?)
  rescue
    raise "#{formula.opt_prefix} not present or broken\nPlease reinstall #{formula.full_name}. Sorry :("
  end

  def normalize_pod2man_outputs!(formula)
    keg = Keg.new(formula.prefix)
    keg.normalize_pod2man_outputs!
  end
end

begin
  ENV.delete("HOMEBREW_FORBID_PACKAGES_FROM_PATHS")
  args = Homebrew::Cmd::InstallCmd.new.args
  Context.current = args.context

  error_pipe = Utils::UNIXSocketExt.open(ENV.fetch("HOMEBREW_ERROR_PIPE"), &:recv_io)
  error_pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

  trap("INT", old_trap)

  formula = args.named.to_formulae.first
  options = Options.create(args.flags_only)
  build   = Build.new(formula, options, args:)
  build.install
# Any exception means the build did not complete.
# The `case` for what to do per-exception class is further down.
rescue Exception => e # rubocop:disable Lint/RescueException
  error_hash = JSON.parse e.to_json

  # Special case: need to recreate BuildErrors in full
  # for proper analytics reporting and error messages.
  # BuildErrors are specific to build processes and not other
  # children, which is why we create the necessary state here
  # and not in Utils.safe_fork.
  case e
  when BuildError
    error_hash["cmd"] = e.cmd
    error_hash["args"] = e.args
    error_hash["env"] = e.env
  when ErrorDuringExecution
    error_hash["cmd"] = e.cmd
    error_hash["status"] = if e.status.is_a?(Process::Status)
      {
        exitstatus: e.status.exitstatus,
        termsig:    e.status.termsig,
      }
    else
      e.status
    end
    error_hash["output"] = e.output
  end

  error_pipe.puts error_hash.to_json
  error_pipe.close
  exit! 1
end
