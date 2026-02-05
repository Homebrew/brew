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
  run_test = proc do |_|
    # TODO: Replace proc usage with direct `formula.run_test` when removing this.
    # Also update formula.rb 'TODO: replace `returns(BasicObject)` with `void`'
    if formula.run_test(keep_tmp: args.keep_tmp?) == false
      require "utils/output"
      Utils::Output.odeprecated "`return false` in test", "`raise \"<reason for failure>\"`"
      raise "test returned false"
    end
  end
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
  pid = Process.pid.to_s
  pkill = "/usr/bin/pkill"
  pgrep = "/usr/bin/pgrep"
  if File.executable?(pkill) && File.executable?(pgrep) && system(pgrep, "-P", pid, out: File::NULL)
    $stderr.puts "Killing child processes..."
    system pkill, "-P", pid
    sleep 1
    system pkill, "-9", "-P", pid
  end
  exit! 1 if e
end
