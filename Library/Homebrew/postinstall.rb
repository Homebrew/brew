# typed: strict
# frozen_string_literal: true

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

old_trap = trap("INT") { exit! 130 }

require_relative "global"

require "cli/parser"
require "cmd/postinstall"
require "utils/fork"
require "extend/pathname/write_mkpath_extension"

begin
  # Undocumented opt-out for internal use.
  # We need to allow formulae from paths here due to how we pass them through.
  ENV["HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS"] = "1"

  args = Homebrew::Cmd::Postinstall.new.args
  error_pipe = Utils.forked_child_error_pipe

  trap("INT", old_trap)

  formula = args.named.to_resolved_formulae.fetch(0)
  if args.debug? && !Homebrew::EnvConfig.disable_debrew?
    require "debrew"
    formula.extend(Debrew::Formula)
  end

  Pathname.activate_extensions!
  formula.run_post_install

# Handle all possible exceptions.
rescue Exception => e # rubocop:disable Lint/RescueException
  Utils.report_forked_child_error(error_pipe, e)
  exit! 1
end
