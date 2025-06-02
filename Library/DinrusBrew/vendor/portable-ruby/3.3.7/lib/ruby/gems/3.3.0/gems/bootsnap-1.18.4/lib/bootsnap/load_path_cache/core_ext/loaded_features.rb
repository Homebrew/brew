# frozen_string_literal: true

class << $LOADED_FEATURES
  alias_method(:delete_without_bootsnap, :delete)
  def delete(key)
    Bootsnap::LoadPathCache.loaded_features_index.purge(key)
    delete_without_bootsnap(key)
  end

  alias_method(:reject_without_bootsnap!, :reject!)
  def reject!(&block)
    backup = dup

    # FIXME: if no block is passed we'd need to return a decorated iterator
    reject_without_bootsnap!(&block)

    Bootsnap::LoadPathCache.loaded_features_index.purge_multi(backup - self)
  end
end
