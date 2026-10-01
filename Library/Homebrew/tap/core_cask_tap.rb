# typed: strict
# frozen_string_literal: true

# A specialized {Tap} class for homebrew-cask.
class CoreCaskTap < AbstractCoreTap
  class << self
    Cache = type_member { { fixed: T::Hash[T.any(String, Symbol), T.untyped] } }
    Elem = type_member(:out) { { fixed: Tap } }
  end

  # Get the singleton instance for this {Tap}.
  #
  # @api internal
  sig { returns(CoreCaskTap) }
  def self.instance
    @instance ||= T.let(new, T.nilable(CoreCaskTap))
  end

  sig { void }
  def initialize
    super "Homebrew", "cask"
  end

  sig { override.returns(T::Boolean) }
  def core_cask_tap?
    true
  end

  sig { params(token: String).returns(String) }
  def new_cask_subdirectory(token)
    if token.start_with?("font-")
      "font/font-#{token.delete_prefix("font-")[0]}"
    else
      token[0].to_s
    end
  end

  sig { override.params(token: String).returns(Pathname) }
  def new_cask_path(token)
    cask_dir/new_cask_subdirectory(token)/"#{token.downcase}.rb"
  end

  sig { override.returns(T::Array[Pathname]) }
  def cask_files
    return super if Homebrew::EnvConfig.no_install_from_api?

    cask_files_by_name.values
  end

  sig { override.returns(T::Array[String]) }
  def cask_tokens
    return super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::API.cask_tokens
  end

  sig { override.returns(T::Hash[String, Pathname]) }
  def cask_files_by_name
    return super if Homebrew::EnvConfig.no_install_from_api?

    @cask_files_by_name ||= T.let(
      begin
        cask_directory_path = cask_dir.to_s
        Homebrew::API.cask_tokens.each_with_object({}) do |name, hash|
          # If there's more than one item with the same path: use the longer one to prioritise more specific results.
          existing_path = hash[name]
          # Pathname equivalent is slow in a tight loop
          new_path = File.join(cask_directory_path, new_cask_subdirectory(name), "#{name.downcase}.rb")
          hash[name] = Pathname(new_path) if existing_path.nil? || existing_path.to_s.length < new_path.length
        end
      end,
      T.nilable(T::Hash[String, Pathname]),
    )
  end

  sig { override.returns(T::Hash[String, String]) }
  def cask_renames
    @cask_renames ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        super
      else
        Homebrew::API.cask_renames
      end,
      T.nilable(T::Hash[String, String]),
    )
  end

  sig { override.returns(T::Hash[String, T.untyped]) }
  def tap_migrations
    @tap_migrations ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        super
      else
        Homebrew::API.cask_tap_migrations
      end,
      T.nilable(T::Hash[String, T.untyped]),
    )
  end
end
