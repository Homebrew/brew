# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `zap` stanza.
    class Zap < AbstractUninstall
      # Removing files also waits, as `uninstall` steps may still need them, e.g. to
      # identify a keychain certificate to delete.
      sig { override.returns(T::Array[Symbol]) }
      def deferred_directives = [:pkgutil, :delete, :trash, :rmdir]
    end
  end
end
