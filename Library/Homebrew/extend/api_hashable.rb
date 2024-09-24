# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Used to substitute common paths with generic placeholders when generating JSON for the API.
module APIHashable
  extend T::Helpers

  requires_ancestor { Module }

  module CaskURLFallbackExtension
    extend T::Helpers

    requires_ancestor { Kernel }
    requires_ancestor { Cask::Cask }

    def url(...)
      url = super

      # URLs with blocks are lazy-evaluated, so we let's force an evaluation to ensure the URL can be determined
      begin
        url.to_s
      rescue
        raise unless self.class.generating_hash?
        raise unless (json_cask = Homebrew::API::Cask.all_casks[token])

        prev_url = json_cask["url"]
        prev_specs = json_cask["url_specs"] || {}
        url = Cask::URL.new(prev_url, **prev_specs)

        opoo "Unable to determine URL for #{token}. Falling back to previous value: #{url}"
      end

      url
    end
  end

  def self.extended(base)
    return if base != Cask::Cask

    base.prepend CaskURLFallbackExtension
  end

  def generating_hash!
    return if generating_hash?

    # Apply monkeypatches for API generation
    @old_homebrew_prefix = HOMEBREW_PREFIX
    @old_homebrew_cellar = HOMEBREW_CELLAR
    @old_home = Dir.home
    Object.send(:remove_const, :HOMEBREW_PREFIX)
    Object.const_set(:HOMEBREW_PREFIX, Pathname.new(HOMEBREW_PREFIX_PLACEHOLDER))
    ENV["HOME"] = HOMEBREW_HOME_PLACEHOLDER

    @generating_hash = true
  end

  def generated_hash!
    return unless generating_hash?

    # Revert monkeypatches for API generation
    Object.send(:remove_const, :HOMEBREW_PREFIX)
    Object.const_set(:HOMEBREW_PREFIX, @old_homebrew_prefix)
    ENV["HOME"] = @old_home

    @generating_hash = false
  end

  def generating_hash?
    @generating_hash ||= false
    @generating_hash == true
  end
end
