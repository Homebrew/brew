# typed: strict
# frozen_string_literal: true

require "json"

#
# {CacheStoreDatabase} acts as an interface to a persistent storage mechanism
# residing in the `HOMEBREW_CACHE`.
#
class CacheStoreDatabase
  # Yields the cache store database.
  # Closes the database after use if it has been loaded.
  #
  # @param  [Symbol] type
  # @yield  [CacheStoreDatabase] self
  sig {
    type_parameters(:U)
      .params(
        type: Symbol,
        _blk: T.proc.params(arg0: CacheStoreDatabase).returns(T.type_parameter(:U)),
      )
      .returns(T.type_parameter(:U))
  }
  def self.use(type, &_blk)
    @db_type_reference_hash ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
    @db_type_reference_hash[type] ||= {}
    type_ref = @db_type_reference_hash[type]

    type_ref[:count] ||= 0
    type_ref[:count]  += 1

    type_ref[:db] ||= CacheStoreDatabase.new(type)

    return_value = yield(type_ref[:db])
    if type_ref[:count].positive?
      type_ref[:count] -= 1
    else
      type_ref[:count] = 0
    end

    if type_ref[:count].zero?
      type_ref[:db].write_if_dirty!
      type_ref.delete(:db)
    end

    return_value
  end

  # Creates a CacheStoreDatabase.
  #
  # @param  [Symbol] type
  # @return [nil]
  sig { params(type: Symbol).void }
  def initialize(type)
    @type = T.let(type, Symbol)
    @dirty = T.let(false, T.nilable(T::Boolean))
  end

  # Sets a value in the underlying database (and creates it if necessary).
  sig { params(key: T.anything, value: T.anything).void }
  def set(key, value)
    dirty!
    db[key] = value
  end

  # Gets a value from the underlying database (if it already exists).
  sig { params(key: T.anything).returns(T.untyped) }
  def get(key)
    return unless created?

    db[key]
  end

  # Deletes a value from the underlying database (if it already exists).
  sig { params(key: T.anything).void }
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
  #
  # @return [Boolean]
  sig { returns(T::Boolean) }
  def created?
    cache_path.exist?
  end

  # Returns the modification time of the cache file (if it already exists).
  #
  # @return [Time]
  sig { returns(T.nilable(Time)) }
  def mtime
    return unless created?

    cache_path.mtime
  end

  # Performs a `select` on the underlying database.
  #
  # @return [Hash]
  sig { params(block: T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(BasicObject)).returns(T::Hash[T.untyped, T.untyped]) }
  def select(&block)
    db.select(&block)
  end

  # Returns `true` if the cache is empty.
  #
  # @return [Boolean]
  sig { returns(T::Boolean) }
  def empty?
    db.empty?
  end

  # Performs a `each_key` on the underlying database.
  #
  # @return [Hash]
  sig { params(block: T.proc.params(arg0: T.untyped).returns(BasicObject)).returns(T::Hash[T.untyped, T.untyped]) }
  def each_key(&block)
    db.each_key(&block)
  end

  private

  # Lazily loaded database in read/write mode. If this method is called, a
  # database file will be created in the `HOMEBREW_CACHE` with a name
  # corresponding to the `@type` instance variable.
  #
  # @return [Hash] db
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def db
    @db ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
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
  #
  # @return [Pathname]
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
  #
  # @return [Boolean]
  sig { returns(T::Boolean) }
  def dirty?
    !!@dirty
  end
end

#
# {CacheStore} provides methods to mutate and fetch data from a persistent
# storage mechanism.
#
class CacheStore
  # @param  [CacheStoreDatabase] database
  # @return [nil]
  sig { params(database: CacheStoreDatabase).void }
  def initialize(database)
    @database = T.let(database, CacheStoreDatabase)
  end

  # Inserts new values or updates existing cached values to persistent storage.
  #
  # @abstract
  sig { params(args: T.anything).void }
  def update!(*args)
    raise NotImplementedError
  end

  # Fetches cached values in persistent storage according to the type of data
  # stored.
  #
  # @abstract
  sig { params(args: T.anything).returns(T.untyped) }
  def fetch(*args)
    raise NotImplementedError
  end

  # Deletes data from the cache based on a condition defined in a concrete class.
  #
  # @abstract
  sig { params(args: T.anything).void }
  def delete!(*args)
    raise NotImplementedError
  end

  protected

  # @return [CacheStoreDatabase]
  sig { returns(CacheStoreDatabase) }
  attr_reader :database
end
