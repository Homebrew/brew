# typed: strict
# frozen_string_literal: true

require "json"

#
# {CacheStoreDatabase} acts as an interface to a persistent storage mechanism
# residing in the `HOMEBREW_CACHE`.
#
class CacheStoreDatabase
  extend T::Generic

  Key = type_member
  Value = type_member

  # Tracks the active users and shared database for one cache type.
  class TypeReference < T::Struct
    const :mutex, Thread::Mutex
    prop :active_users, Integer, default: 0
    prop :database, T.nilable(CacheStoreDatabase[T.anything, T.anything]), default: nil
  end
  private_constant :TypeReference

  # Only reference creation is global; each cache type has its own lifecycle lock.
  @type_references_mutex = T.let(Thread::Mutex.new, Thread::Mutex)
  @type_references = T.let({}, T::Hash[Symbol, TypeReference])

  # Yields the cache store database.
  # Closes the database after use if it has been loaded.
  sig {
    type_parameters(:U)
      .params(
        type: Symbol,
        _blk: T.proc.params(arg0: CacheStoreDatabase[T.anything, T.anything]).returns(T.type_parameter(:U)),
      )
      .returns(T.type_parameter(:U))
  }
  def self.use(type, &_blk)
    type_ref = @type_references_mutex.synchronize do
      @type_references[type] ||= TypeReference.new(mutex: Thread::Mutex.new)
    end

    db = type_ref.mutex.synchronize do
      type_ref.active_users += 1
      type_ref.database ||= CacheStoreDatabase.new(type)
    end

    begin
      return_value = yield(db)
      return_value
    ensure
      # `break` from the block used to skip the decrement and leak the refcount.
      type_ref.mutex.synchronize do
        type_ref.active_users -= 1
        if type_ref.active_users.zero?
          # Prevent a replacement database from opening until the final write completes.
          type_ref.database&.write_if_dirty!
          type_ref.database = nil
        end
      end
    end
  end

  # Creates a CacheStoreDatabase.
  sig { params(type: Symbol).void }
  def initialize(type)
    @type = type
    @dirty = T.let(false, T.nilable(T::Boolean))
  end

  # Sets a value in the underlying database (and creates it if necessary).
  sig { params(key: Key, value: Value).void }
  def set(key, value)
    dirty!
    db[key] = value
  end

  # Gets a value from the underlying database (if it already exists).
  sig { params(key: Key).returns(T.nilable(Value)) }
  def get(key)
    return unless created?

    db[key]
  end

  # Deletes a value from the underlying database (if it already exists).
  sig { params(key: Key).void }
  def delete(key)
    return unless created?

    dirty!
    db.delete(key)
  end

  # Deletes all content from the underlying database (if it already exists).
  sig { void }
  def clear!
    return unless created?

    dirty!
    db.clear
  end

  # Closes the underlying database (if it is created and open).
  sig { void }
  def write_if_dirty!
    return unless dirty?

    cache_path.dirname.mkpath
    cache_path.atomic_write(JSON.dump(@db))
  end

  # Returns `true` if the cache file has been created for the given `@type`.
  sig { returns(T::Boolean) }
  def created?
    cache_path.exist?
  end

  # Returns the modification time of the cache file (if it already exists).
  sig { returns(T.nilable(Time)) }
  def mtime
    return unless created?

    cache_path.mtime
  end

  # Performs a `select` on the underlying database.
  sig {
    overridable.params(block: T.proc.params(arg0: Key, arg1: Value).returns(BasicObject)).returns(T::Hash[Key, Value])
  }
  def select(&block)
    db.select(&block)
  end

  # Returns `true` if the cache is empty.
  sig { returns(T::Boolean) }
  def empty?
    db.empty?
  end

  # Performs a `each_key` on the underlying database.
  sig {
    params(block: T.proc.params(arg0: Key).returns(BasicObject)).returns(T::Hash[Key, Value])
  }
  def each_key(&block)
    db.each_key(&block)
  end

  sig { params(db: T.nilable(T::Hash[Key, Value])).void }
  attr_writer :db

  private

  # Lazily loaded database in read/write mode. If this method is called, a
  # database file will be created in the `HOMEBREW_CACHE` with a name
  # corresponding to the `@type` instance variable.
  sig { returns(T::Hash[Key, Value]) }
  def db
    @db ||= T.let({}, T.nilable(T::Hash[Key, Value]))
    return @db if !@db.empty? || !created?

    begin
      result = JSON.parse(cache_path.read)
      @db = result if result.is_a?(Hash)
    rescue JSON::ParserError
      # Ignore parse errors
    end
    @db
  end

  # The path where the database resides in the `HOMEBREW_CACHE` for the given
  # `@type`.
  sig { returns(Pathname) }
  def cache_path
    HOMEBREW_CACHE/"#{@type}.json"
  end

  # Sets that the cache needs to be written to disk.
  sig { void }
  def dirty!
    @dirty = true
  end

  # Returns `true` if the cache needs to be written to disk.
  sig { returns(T::Boolean) }
  def dirty?
    !!@dirty
  end
end
require "cache_store/cache_store"
