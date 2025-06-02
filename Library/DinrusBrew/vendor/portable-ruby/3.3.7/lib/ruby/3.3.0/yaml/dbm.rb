# frozen_string_literal: false
require 'yaml'
require 'dbm'

module YAML

# YAML + DBM = YDBM
#
# YAML::DBM provides the same interface as ::DBM.
#
# However, while DBM only allows strings for both keys and values,
# this library allows one to use most Ruby objects for values
# by first converting them to YAML. Keys must be strings.
#
# Conversion to and from YAML is performed automatically.
#
# See the documentation for ::DBM and ::YAML for more information.
class DBM < ::DBM
    VERSION = "0.1" # :nodoc:

    # :call-seq:
    #   ydbm[key] -> value
    #
    # Return value associated with +key+ from database.
    #
    # Returns +nil+ if there is no such +key+.
    #
    # See #fetch for more information.
    def []( key )
        fetch( key )
    end

    # :call-seq:
    #   ydbm[key] = value
    #
    # Set +key+ to +value+ in database.
    #
    # +value+ will be converted to YAML before storage.
    #
    # See #store for more information.
    def []=( key, val )
        store( key, val )
    end

    # :call-seq:
    #   ydbm.fetch( key, ifnone = nil )
    #   ydbm.fetch( key ) { |key| ... }
    #
    # Return value associated with +key+.
    #
    # If there is no value for +key+ and no block is given, returns +ifnone+.
    #
    # Otherwise, calls block passing in the given +key+.
    #
    # See ::DBM#fetch for more information.
    def fetch( keystr, ifnone = nil )
        begin
            val = super( keystr )
            return YAML.load( val ) if String === val
        rescue IndexError
        end
        if block_given?
            yield keystr
        else
            ifnone
        end
    end

    # Deprecated, used YAML::DBM#key instead.
    # ----
    # Note:
    # YAML::DBM#index makes warning from internal of ::DBM#index.
    # It says 'DBM#index is deprecated; use DBM#key', but DBM#key
    # behaves not same as DBM#index.
    #
    def index( keystr )
        super( keystr.to_yaml )
    end

    # :call-seq:
    #   ydbm.key(value) -> string
    #
    # Returns the key for the specified value.
    def key( keystr )
        invert[keystr]
    end

    # :call-seq:
    #   ydbm.values_at(*keys)
    #
    # Returns an array containing the values associated with the given keys.
    def values_at( *keys )
        keys.collect { |k| fetch( k ) }
    end

    # :call-seq:
    #   ydbm.delete(key)
    #
    # Deletes value from database associated with +key+.
    #
    # Returns value or +nil+.
    def delete( key )
        v = super( key )
        if String === v
            v = YAML.load( v )
        end
        v
    end

    # :call-seq:
    #   ydbm.delete_if { |key, value| ... }
    #
    # Calls the given block once for each +key+, +value+ pair in the database.
    # Deletes all entries for which the block returns true.
    #
    # Returns +self+.
    def delete_if # :yields: [key, value]
        del_keys = keys.dup
        del_keys.delete_if { |k| yield( k, fetch( k ) ) == false }
        del_keys.each { |k| delete( k ) }
        self
    end

    # :call-seq:
    #   ydbm.reject { |key, value| ... }
    #
    # Converts the contents of the database to an in-memory Hash, then calls
    # Hash#reject with the specified code block, returning a new Hash.
    def reject
        hsh = self.to_hash
        hsh.reject { |k,v| yield k, v }
    end

    # :call-seq:
    #   ydbm.each_pair { |key, value| ... }
    #
    # Calls the given block once for each +key+, +value+ pair in the database.
    #
    # Returns +self+.
    def each_pair # :yields: [key, value]
        keys.each { |k| yield k, fetch( k ) }
        self
    end

    # :call-seq:
    #   ydbm.each_value { |value| ... }
    #
    # Calls the given block for each value in database.
    #
    # Returns +self+.
    def each_value # :yields: value
        super { |v| yield YAML.load( v ) }
        self
    end

    # :call-seq:
    #   ydbm.values
    #
    # Returns an array of values from the database.
    def values
        super.collect { |v| YAML.load( v ) }
    end

    # :call-seq:
    #   ydbm.has_value?(value)
    #
    # Returns true if specified +value+ is found in the database.
    def has_value?( val )
        each_value { |v| return true if v == val }
        return false
    end

    # :call-seq:
    #   ydbm.invert -> hash
    #
    # Returns a Hash (not a DBM database) created by using each value in the
    # database as a key, with the corresponding key as its value.
    #
    # Note that all values in the hash will be Strings, but the keys will be
    # actual objects.
    def invert
        h = {}
        keys.each { |k| h[ self.fetch( k ) ] = k }
        h
    end

    # :call-seq:
    #   ydbm.replace(hash) -> ydbm
    #
    # Replaces the contents of the database with the contents of the specified
    # object. Takes any object which implements the each_pair method, including
    # Hash and DBM objects.
    def replace( hsh )
        clear
        update( hsh )
    end

    # :call-seq:
    #   ydbm.shift -> [key, value]
    #
    # Removes a [key, value] pair from the database, and returns it.
    # If the database is empty, returns +nil+.
    #
    # The order in which values are removed/returned is not guaranteed.
    def shift
        a = super
        a[1] = YAML.load( a[1] ) if a
        a
    end

    # :call-seq:
    #   ydbm.select { |key, value| ... }
    #   ydbm.select(*keys)
    #
    # If a block is provided, returns a new array containing [key, value] pairs
    # for which the block returns true.
    #
    # Otherwise, same as #values_at
    def select( *keys )
        if block_given?
            self.keys.collect { |k| v = self[k]; [k, v] if yield k, v }.compact
        else
            values_at( *keys )
        end
    end

    # :call-seq:
    #   ydbm.store(key, value) -> value
    #
    # Stores +value+ in database with +key+ as the index. +value+ is converted
    # to YAML before being stored.
    #
    # Returns +value+
    def store( key, val )
        super( key, val.to_yaml )
        val
    end

    # :call-seq:
    #   ydbm.update(hash) -> ydbm
    #
    # Updates the database with multiple values from the specified object.
    # Takes any object which implements the each_pair method, including
    # Hash and DBM objects.
    #
    # Returns +self+.
    def update( hsh )
        hsh.each_pair do |k,v|
            self.store( k, v )
        end
        self
    end

    # :call-seq:
    #   ydbm.to_a -> array
    #
    # Converts the contents of the database to an array of [key, value] arrays,
    # and returns it.
    def to_a
        a = []
        keys.each { |k| a.push [ k, self.fetch( k ) ] }
        a
    end


    # :call-seq:
    #   ydbm.to_hash -> hash
    #
    # Converts the contents of the database to an in-memory Hash object, and
    # returns it.
    def to_hash
        h = {}
        keys.each { |k| h[ k ] = self.fetch( k ) }
        h
    end

    alias :each :each_pair
end

end
