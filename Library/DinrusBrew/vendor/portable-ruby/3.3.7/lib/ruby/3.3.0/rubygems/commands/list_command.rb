# frozen_string_literal: true

require_relative "../command"
require_relative "../query_utils"

##
# Searches for gems starting with the supplied argument.

class Gem::Commands::ListCommand < Gem::Command
  include Gem::QueryUtils

  def initialize
    super "list", "Display local gems whose name matches REGEXP",
         domain: :local, details: false, versions: true,
         installed: nil, version: Gem::Requirement.default

    add_query_options
  end

  def arguments # :nodoc:
    "REGEXP        regexp to look for in gem name"
  end

  def defaults_str # :nodoc:
    "--local --no-details"
  end

  def description # :nodoc:
    <<-EOF
The list command is used to view the gems you have installed locally.

The --details option displays additional details including the summary, the
homepage, the author, the locations of different versions of the gem.

To search for remote gems use the search command.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [REGEXP ...]"
  end
end
