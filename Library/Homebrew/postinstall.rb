# typed: strict
# frozen_string_literal: true

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

old_trap = trap("INT") { exit! 130 }

require_relative "global"
require "fcntl"
require "socket"
require "cli/parser"
require "cmd/postinstall"

begin
  args = Homebrew.postinstall_args.parse
  error_pipe = UNIXSocket.open(ENV.fetch("HOMEBREW_ERROR_PIPE"), &:recv_io)
  error_pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

  trap("INT", old_trap)

  formula = args.named.to_resolved_formulae.first
  if args.debug?
    require "debrew"
    formula.extend(Debrew::Formula)
  end
  formula.run_post_install
rescue Exception => e # rubocop:disable Lint/RescueException
  error_pipe.puts e.to_json
  error_pipe.close
  exit! 1
end
