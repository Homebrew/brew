# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Used to substitute common paths with generic placeholders when generating JSON for the API.
module APIHashable
  def generating_hash!
    return if generating_hash?

    # Apply monkeypatches for API generation
    @old_homebrew_prefix = DINRUSBREW_PREFIX
    @old_homebrew_cellar = DINRUSBREW_CELLAR
    @old_home = Dir.home
    Object.send(:remove_const, :DINRUSBREW_PREFIX)
    Object.const_set(:DINRUSBREW_PREFIX, Pathname.new(DINRUSBREW_PREFIX_PLACEHOLDER))
    ENV["HOME"] = DINRUSBREW_HOME_PLACEHOLDER

    @generating_hash = true
  end

  def generated_hash!
    return unless generating_hash?

    # Revert monkeypatches for API generation
    Object.send(:remove_const, :DINRUSBREW_PREFIX)
    Object.const_set(:DINRUSBREW_PREFIX, @old_homebrew_prefix)
    ENV["HOME"] = @old_home

    @generating_hash = false
  end

  def generating_hash?
    @generating_hash ||= false
    @generating_hash == true
  end
end
