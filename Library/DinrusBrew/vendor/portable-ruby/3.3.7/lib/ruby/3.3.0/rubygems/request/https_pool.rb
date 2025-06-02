# frozen_string_literal: true

class Gem::Request::HTTPSPool < Gem::Request::HTTPPool # :nodoc:
  private

  def setup_connection(connection)
    Gem::Request.configure_connection_for_https(connection, @cert_files)
    super
  end
end
