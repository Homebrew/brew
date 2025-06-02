# frozen_string_literal: true

require_relative "../command"

class Gem::Commands::SignoutCommand < Gem::Command
  def initialize
    super "signout", "Sign out from all the current sessions."
  end

  def description # :nodoc:
    "The `signout` command is used to sign out from all current sessions,"\
    " allowing you to sign in using a different set of credentials."
  end

  def usage # :nodoc:
    program_name
  end

  def execute
    credentials_path = Gem.configuration.credentials_path

    if !File.exist?(credentials_path)
      alert_error "You are not currently signed in."
    elsif !File.writable?(credentials_path)
      alert_error "File '#{Gem.configuration.credentials_path}' is read-only."\
                  " Please make sure it is writable."
    else
      Gem.configuration.unset_api_key!
      say "You have successfully signed out from all sessions."
    end
  end
end
