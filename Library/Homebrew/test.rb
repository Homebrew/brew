# typed: true
# frozen_string_literal: true

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

old_trap = trap("INT") { exit! 130 }

require_relative "global"
require "extend/ENV"
require "timeout"
require "formula_assertions"
require "formula_free_port"
require "fcntl"
require "socket"
require "cli/parser"
require "dev-cmd/test"

TEST_TIMEOUT_SECONDS = 5 * 60

begin
  args = Homebrew.test_args.parse
  Context.current = args.context

  error_pipe = UNIXSocket.open(ENV.fetch("HOMEBREW_ERROR_PIPE"), &:recv_io)
  error_pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

  trap("INT", old_trap)

  if Homebrew::EnvConfig.developer? || ENV["CI"].present?
    raise "Cannot find child processes without `pgrep`, please install!" unless which("pgrep")
    raise "Cannot kill child processes without `pkill`, please install!" unless which("pkill")
  end

  formula = T.must(args.named.to_resolved_formulae.first)
  formula.extend(Homebrew::Assertions)
  formula.extend(Homebrew::FreePort)
  if args.debug?
    require "debrew"
    formula.extend(Debrew::Formula)
  end

  ENV.extend(Stdenv)
  ENV.setup_build_environment(formula: formula, testing_formula: true)

  # tests can also return false to indicate failure
  run_test = proc { |_ = nil| raise "test returned false" if formula.run_test(keep_tmp: args.keep_tmp?) == false }
  if args.debug? # --debug is interactive
    run_test.call
  else
    Timeout.timeout(TEST_TIMEOUT_SECONDS, &run_test)
  end
rescue Exception => e # rubocop:disable Lint/RescueException
  error_pipe.puts e.to_json
  error_pipe.close
ensure
  pid = Process.pid.to_s
  if which("pgrep") && which("pkill") && system("pgrep", "-P", pid, out: File::NULL)
    $stderr.puts "Killing child processes..."
    system "pkill", "-P", pid
    sleep 1
    system "pkill", "-9", "-P", pid
  end
  exit! 1 if e
end
