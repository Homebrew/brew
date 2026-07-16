# typed: strict
# frozen_string_literal: true

# Used to substitute common paths with generic placeholders when generating JSON for the API.
module APIHashable
  sig { void }
  def generating_hash!
    return if generating_hash?

    # Apply monkeypatches for API generation
    @old_homebrew_prefix = T.let(HOMEBREW_PREFIX, T.nilable(Pathname))
    @old_homebrew_cellar = T.let(HOMEBREW_CELLAR, T.nilable(Pathname))
    @old_home = T.let(Dir.home, T.nilable(String))
    @old_git_config_global = T.let(ENV.fetch("GIT_CONFIG_GLOBAL", nil), T.nilable(String))
    Object.send(:remove_const, :HOMEBREW_PREFIX)
    Object.const_set(:HOMEBREW_PREFIX, Pathname.new(HOMEBREW_PREFIX_PLACEHOLDER))
    ENV["HOME"] = HOMEBREW_HOME_PLACEHOLDER
    ENV["GIT_CONFIG_GLOBAL"] = File.join(@old_home, ".gitconfig")

    @generating_hash = T.let(true, T.nilable(T::Boolean))
  end

  sig { returns(T::Boolean) }
  def generating_hash?
    @generating_hash ||= false
    @generating_hash == true
  end

  sig { type_parameters(:U).params(value: T.type_parameter(:U)).returns(T.type_parameter(:U)) }
  def deep_remove_placeholders(value)
    return value if generating_hash?

    value = case value
    when Hash
      value.transform_values { |v| deep_remove_placeholders(v) }
    when Array
      value.map { |v| deep_remove_placeholders(v) }
    when String
      value.gsub(HOMEBREW_PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
           .gsub(HOMEBREW_CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
           .gsub(HOMEBREW_HOME_PLACEHOLDER, Dir.home)
    else
      value
    end

    T.cast(value, T.type_parameter(:U))
  end
end
