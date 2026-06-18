# typed: strict
# frozen_string_literal: true

# An abstract {Tap} class for the homebrew-core and homebrew-cask.
class AbstractCoreTap < Tap
  extend T::Helpers

  abstract!

  class << self
    Cache = type_member { { fixed: T::Hash[T.any(String, Symbol), T.untyped] } }
    Elem = type_member(:out) { { fixed: Tap } }
  end

  private_class_method :fetch

  # Get the singleton instance for this {Tap}.
  #
  # @api internal
  sig { returns(T.attached_class) }
  def self.instance
    @instance ||= T.let(T.unsafe(self).new, T.nilable(T.attached_class))
  end

  sig { override.void }
  def ensure_installed!
    return unless Homebrew::EnvConfig.no_install_from_api?
    return if Homebrew::EnvConfig.automatically_set_no_install_from_api?

    super
  end

  # In API mode the formulae and casks come from the API rather than this tap's
  # Git remote, so the remote is irrelevant to what is loaded.
  sig { override.params(remote: T.nilable(String)).returns(T::Boolean) }
  def implicitly_trusted?(remote: self.remote)
    return true unless Homebrew::EnvConfig.no_install_from_api?

    super
  end

  sig { override.params(file: Pathname).returns(String) }
  def formula_file_to_name(file)
    file.basename(".rb").to_s
  end

  sig { override.returns(T::Boolean) }
  def should_report_analytics?
    return super if Homebrew::EnvConfig.no_install_from_api?

    true
  end
end
