# typed: strict
# frozen_string_literal: true

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

old_trap = trap("INT") { exit! 130 }

require_relative "global"
require "extend/ENV"
require "timeout"
require "formula_assertions"
require "formula_free_port"
require "fcntl"
require "utils/socket"
require "cli/parser"
require "dev-cmd/test"
require "json/add/exception"
require "extend/pathname/write_mkpath_extension"

DEFAULT_TEST_TIMEOUT_SECONDS = T.let(5 * 60, Integer)

begin
  # Undocumented opt-out for internal use.
  # We need to allow formulae from paths here due to how we pass them through.
  ENV["HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS"] = "1"

  args = Homebrew::DevCmd::Test.new.args
  Context.current = args.context

  error_pipe = Utils::UNIXSocketExt.open(ENV.fetch("HOMEBREW_ERROR_PIPE"), &:recv_io)
  error_pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

  trap("INT", old_trap)

  if Homebrew::EnvConfig.developer? || ENV["CI"].present?
    raise "Cannot find child processes without `pgrep`, please install!" unless which("pgrep")
    raise "Cannot kill child processes without `pkill`, please install!" unless which("pkill")
  end

  formula = args.named.to_resolved_formulae.fetch(0)
  formula.extend(Homebrew::Assertions)
  formula.extend(Homebrew::FreePort)
  if args.debug? && !Homebrew::EnvConfig.disable_debrew?
    require "debrew"
    formula.extend(Debrew::Formula)
  end

  ENV.extend(Stdenv)
  ENV.setup_build_environment(formula:, testing_formula: true)
  Pathname.activate_extensions!

  # tests can also return false to indicate failure
  run_test = proc { |_| raise "test returned false" if formula.run_test(keep_tmp: args.keep_tmp?) == false }
  if args.debug? # --debug is interactive
    run_test.call(nil)
  else
    # HOMEBREW_TEST_TIMEOUT_SECS is private API and subject to change.
    timeout = ENV["HOMEBREW_TEST_TIMEOUT_SECS"]&.to_i || DEFAULT_TEST_TIMEOUT_SECONDS
    Timeout.timeout(timeout, &run_test)
  end
# Any exceptions during the test run are reported.
rescue Exception => e # rubocop:disable Lint/RescueException
  error_pipe&.puts e.to_json
  error_pipe&.close
ensure
  test_failed = e

  begin
    pgid = Process.getpgrp

    $stderr.puts 'Terminating child processes...'
    trap_saved = Signal.trap('TERM', 'IGNORE')
    Process.kill('TERM', -pgid) rescue nil
    Signal.trap('TERM', trap_saved)

    sleep 1

    pgrep = '/usr/bin/pgrep'
    if File.executable?(pgrep)
      $stderr.puts 'Killing child processes...'
      pids = IO.popen([pgrep, '-g', pgid.to_s]) { |io| io.read.split.map(&:to_i) } rescue []
      pids.each do |pid|
        next if pid == Process.pid
        Process.kill('KILL', pid) rescue nil
      end
    end
  rescue Exception => cleanup_ex
    $stderr.puts "Cleanup failed: #{cleanup_ex.message}"
  end

  exit! 1 if test_failed
end
