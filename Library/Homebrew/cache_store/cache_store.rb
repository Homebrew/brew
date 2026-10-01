# typed: strict
# frozen_string_literal: true

#
# {CacheStore} provides methods to mutate and fetch data from a persistent
# storage mechanism.
#
class CacheStore
  extend T::Generic
  extend T::Helpers

  abstract!

  Key = type_member
  Value = type_member

  sig { params(database: CacheStoreDatabase[Key, Value]).void }
  def initialize(database)
    @database = database
  end

  protected

  sig { returns(CacheStoreDatabase[Key, Value]) }
  attr_reader :database
end
