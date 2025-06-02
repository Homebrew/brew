# frozen_string_literal: true

module Kernel
  alias_method :require_without_bootsnap, :require

  alias_method :require, :require # Avoid method redefinition warnings

  def require(path) # rubocop:disable Lint/DuplicateMethods
    return require_without_bootsnap(path) unless Bootsnap::LoadPathCache.enabled?

    string_path = Bootsnap.rb_get_path(path)
    return false if Bootsnap::LoadPathCache.loaded_features_index.key?(string_path)

    resolved = Bootsnap::LoadPathCache.load_path_cache.find(string_path)
    if Bootsnap::LoadPathCache::FALLBACK_SCAN.equal?(resolved)
      if (cursor = Bootsnap::LoadPathCache.loaded_features_index.cursor(string_path))
        ret = require_without_bootsnap(path)
        resolved = Bootsnap::LoadPathCache.loaded_features_index.identify(string_path, cursor)
        Bootsnap::LoadPathCache.loaded_features_index.register(string_path, resolved)
        return ret
      else
        return require_without_bootsnap(path)
      end
    elsif false == resolved
      return false
    elsif resolved.nil?
      return require_without_bootsnap(path)
    else
      # Note that require registers to $LOADED_FEATURES while load does not.
      ret = require_without_bootsnap(resolved)
      Bootsnap::LoadPathCache.loaded_features_index.register(string_path, resolved)
      return ret
    end
  end

  private :require
end
