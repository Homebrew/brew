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
  error_pipe = Utils.forked_child_error_pipe

  formula_name = ARGV.delete("--formula-name")
  spec = ARGV.include?("--HEAD") ? :head : nil
  flags = ARGV.grep(/^--/)
  formula = if formula_name
    Formulary.resolve(ARGV.fetch(0), spec:, flags:)
  else
    Formulary.resolve_from_path(ARGV.fetch(0), spec:, flags:)
  end
  args = Homebrew::Cmd::Postinstall.new(formula:).args

  trap("INT", old_trap)

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
