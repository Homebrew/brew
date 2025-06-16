# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cache_store"

#
# {LinkageCacheStore} provides methods to fetch and mutate linkage-specific data used
# by the `brew linkage` command.
#
class LinkageCacheStore < CacheStore
  # @param keg_path [String]
  # @param database [CacheStoreDatabase]
  # @return [nil]
  def initialize(keg_path, database)
    @keg_path = keg_path
    super(database)
  end

  # Returns `true` if the database has any value for the current `keg_path`.
  #
  # @return [Boolean]
  def keg_exists?
    !database.get(@keg_path).nil?
  end

  # Inserts dylib-related information into the cache if it does not exist or
  # updates data into the linkage cache if it does exist.
  #
  # @param hash_values [Hash] hash containing KVPs of { :type => Hash }
  # @return [nil]
  def update!(hash_values)
    hash_values.each_key do |type|
      next if HASH_LINKAGE_TYPES.include?(type)

      raise TypeError, <<~EOS
        Can't update types that are not defined for the linkage store
      EOS
    end

    database.set @keg_path, hash_values
  end

  # @param type [Symbol] the type to fetch from the {LinkageCacheStore}
  # @raise  [TypeError] error if the type is not in `HASH_LINKAGE_TYPES`
  # @return [Hash]
  def fetch(type)
    unless HASH_LINKAGE_TYPES.include?(type)
      raise TypeError, <<~EOS
        Can't fetch types that are not defined for the linkage store
      EOS
    end

    return {} unless keg_exists?

    fetch_hash_values(type)
  end

  # Delete the keg from the {LinkageCacheStore}
  #
  # @return [nil]
  def delete!
    database.delete(@keg_path)
  end

  private

  HASH_LINKAGE_TYPES = [:keg_files_dylibs].freeze
  private_constant :HASH_LINKAGE_TYPES

  # @param type [Symbol]
  # @return [Hash]
  def fetch_hash_values(type)
    keg_cache = database.get(@keg_path)
    return {} unless keg_cache

    keg_cache[type.to_s]
  end
end
