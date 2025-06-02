# frozen_string_literal: true

##
# Raised when there is an error while building extensions.

require_relative "../exceptions"

class Gem::Ext::BuildError < Gem::InstallError
end
