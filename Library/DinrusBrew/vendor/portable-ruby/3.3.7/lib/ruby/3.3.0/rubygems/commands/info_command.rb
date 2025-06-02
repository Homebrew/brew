# frozen_string_literal: true

require_relative "../command"
require_relative "../query_utils"

class Gem::Commands::InfoCommand < Gem::Command
  include Gem::QueryUtils

  def initialize
    super "info", "Show information for the given gem",
         name: //, domain: :local, details: false, versions: true,
         installed: nil, version: Gem::Requirement.default

    add_query_options

    remove_option("-d")

    defaults[:details] = true
    defaults[:exact] = true
  end

  def description # :nodoc:
    "Info prints information about the gem such as name,"\
    " description, website, license and installed paths"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME"
  end

  def arguments # :nodoc:
    "GEMNAME        name of the gem to print information about"
  end

  def defaults_str
    "--local"
  end
end
