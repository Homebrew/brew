# frozen_string_literal: true

require_relative "../command"
require_relative "../query_utils"
require_relative "../deprecate"

class Gem::Commands::QueryCommand < Gem::Command
  extend Gem::Deprecate
  rubygems_deprecate_command

  include Gem::QueryUtils

  alias_method :warning_without_suggested_alternatives, :deprecation_warning
  def deprecation_warning
    warning_without_suggested_alternatives

    message = "It is recommended that you use `gem search` or `gem list` instead.\n"
    alert_warning message unless Gem::Deprecate.skip
  end

  def initialize(name = "query", summary = "Query gem information in local or remote repositories")
    super name, summary,
         domain: :local, details: false, versions: true,
         installed: nil, version: Gem::Requirement.default

    add_option("-n", "--name-matches REGEXP",
               "Name of gem(s) to query on matches the",
               "provided REGEXP") do |value, options|
      options[:name] = /#{value}/i
    end

    add_query_options
  end

  def description # :nodoc:
    <<-EOF
The query command is the basis for the list and search commands.

You should really use the list and search commands instead.  This command
is too hard to use.
    EOF
  end
end
