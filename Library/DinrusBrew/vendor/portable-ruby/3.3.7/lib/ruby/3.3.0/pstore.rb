# frozen_string_literal: true
# = PStore -- Transactional File Storage for Ruby Objects
#
# pstore.rb -
#   originally by matz
#   documentation by Kev Jackson and James Edward Gray II
#   improved by Hongli Lai
#
# See PStore for documentation.

require "digest"

# \PStore implements a file based persistence mechanism based on a Hash.
# User code can store hierarchies of Ruby objects (values)
# into the data store by name (keys).
# An object hierarchy may be just a single object.
# User code may later read values back from the data store
# or even update data, as needed.
#
# The transactional behavior ensures that any changes succeed or fail together.
# This can be used to ensure that the data store is not left in a transitory state,
# where some values were updated but others were not.
#
# Behind the scenes, Ruby objects are stored to the data store file with Marshal.
# That carries the usual limitations. Proc objects cannot be marshalled,
# for example.
#
# There are three important concepts here (details at the links):
#
# - {Store}[rdoc-ref:PStore@The+Store]: a store is an instance of \PStore.
# - {Entries}[rdoc-ref:PStore@Entries]: the store is hash-like;
#   each entry is the key for a stored object.
# - {Transactions}[rdoc-ref:PStore@Transactions]: each transaction is a collection
#   of prospective changes to the store;
#   a transaction is defined in the block given with a call
#   to PStore#transaction.
#
# == About the Examples
#
# Examples on this page need a store that has known properties.
# They can get a new (and populated) store by calling thus:
#
#   example_store do |store|
#     # Example code using store goes here.
#   end
#
# All we really need to know about +example_store+
# is that it yields a fresh store with a known population of entries;
# its implementation:
#
#   require 'pstore'
#   require 'tempfile'
#   # Yield a pristine store for use in examples.
#   def example_store
#     # Create the store in a temporary file.
#     Tempfile.create do |file|
#       store = PStore.new(file)
#       # Populate the store.
#       store.transaction do
#         store[:foo] = 0
#         store[:bar] = 1
#         store[:baz] = 2
#       end
#       yield store
#     end
#   end
#
# == The Store
#
# The contents of the store are maintained in a file whose path is specified
# when the store is created (see PStore.new).
# The objects are stored and retrieved using
# module Marshal, which means that certain objects cannot be added to the store;
# see {Marshal::dump}[rdoc-ref:Marshal.dump].
#
# == Entries
#
# A store may have any number of entries.
# Each entry has a key and a value, just as in a hash:
#
# - Key: as in a hash, the key can be (almost) any object;
#   see {Hash Keys}[rdoc-ref:Hash@Hash+Keys].
#   You may find it convenient to keep it simple by using only
#   symbols or strings as keys.
# - Value: the value may be any object that can be marshalled by \Marshal
#   (see {Marshal::dump}[rdoc-ref:Marshal.dump])
#   and in fact may be a collection
#   (e.g., an array, a hash, a set, a range, etc).
#   That collection may in turn contain nested objects,
#   including collections, to any depth;
#   those objects must also be \Marshal-able.
#   See {Hierarchical Values}[rdoc-ref:PStore@Hierarchical+Values].
#
# == Transactions
#
# === The Transaction Block
#
# The block given with a call to method #transaction#
# contains a _transaction_,
# which consists of calls to \PStore methods that
# read from or write to the store
# (that is, all \PStore methods except #transaction itself,
# #path, and Pstore.new):
#
#   example_store do |store|
#     store.transaction do
#       store.keys # => [:foo, :bar, :baz]
#       store[:bat] = 3
#       store.keys # => [:foo, :bar, :baz, :bat]
#     end
#   end
#
# Execution of the transaction is deferred until the block exits,
# and is executed _atomically_ (all-or-nothing):
# either all transaction calls are executed, or none are.
# This maintains the integrity of the store.
#
# Other code in the block (including even calls to #path and PStore.new)
# is executed immediately, not deferred.
#
# The transaction block:
#
# - May not contain a nested call to #transaction.
# - Is the only context where methods that read from or write to
#   the store are allowed.
#
# As seen above, changes in a transaction are made automatically
# when the block exits.
# The block may be exited early by calling method #commit or #abort.
#
# - Method #commit triggers the update to the store and exits the block:
#
#     example_store do |store|
#       store.transaction do
#         store.keys # => [:foo, :bar, :baz]
#         store[:bat] = 3
#         store.commit
#         fail 'Cannot get here'
#       end
#       store.transaction do
#         # Update was completed.
#         store.keys # => [:foo, :bar, :baz, :bat]
#       end
#     end
#
# - Method #abort discards the update to the store and exits the block:
#
#     example_store do |store|
#       store.transaction do
#         store.keys # => [:foo, :bar, :baz]
#         store[:bat] = 3
#         store.abort
#         fail 'Cannot get here'
#       end
#       store.transaction do
#         # Update was not completed.
#         store.keys # => [:foo, :bar, :baz]
#       end
#     end
#
# === Read-Only Transactions
#
# By default, a transaction allows both reading from and writing to
# the store:
#
#   store.transaction do
#     # Read-write transaction.
#     # Any code except a call to #transaction is allowed here.
#   end
#
# If argument +read_only+ is passed as +true+,
# only reading is allowed:
#
#   store.transaction(true) do
#     # Read-only transaction:
#     # Calls to #transaction, #[]=, and #delete are not allowed here.
#   end
#
# == Hierarchical Values
#
# The value for an entry may be a simple object (as seen above).
# It may also be a hierarchy of objects nested to any depth:
#
#   deep_store = PStore.new('deep.store')
#   deep_store.transaction do
#     array_of_hashes = [{}, {}, {}]
#     deep_store[:array_of_hashes] = array_of_hashes
#     deep_store[:array_of_hashes] # => [{}, {}, {}]
#     hash_of_arrays = {foo: [], bar: [], baz: []}
#     deep_store[:hash_of_arrays] = hash_of_arrays
#     deep_store[:hash_of_arrays]  # => {:foo=>[], :bar=>[], :baz=>[]}
#     deep_store[:hash_of_arrays][:foo].push(:bat)
#     deep_store[:hash_of_arrays]  # => {:foo=>[:bat], :bar=>[], :baz=>[]}
#   end
#
# And recall that you can use
# {dig methods}[rdoc-ref:dig_methods.rdoc]
# in a returned hierarchy of objects.
#
# == Working with the Store
#
# === Creating a Store
#
# Use method PStore.new to create a store.
# The new store creates or opens its containing file:
#
#   store = PStore.new('t.store')
#
# === Modifying the Store
#
# Use method #[]= to update or create an entry:
#
#   example_store do |store|
#     store.transaction do
#       store[:foo] = 1 # Update.
#       store[:bam] = 1 # Create.
#     end
#   end
#
# Use method #delete to remove an entry:
#
#   example_store do |store|
#     store.transaction do
#       store.delete(:foo)
#       store[:foo] # => nil
#     end
#   end
#
# === Retrieving Values
#
# Use method #fetch (allows default) or #[] (defaults to +nil+)
# to retrieve an entry:
#
#   example_store do |store|
#     store.transaction do
#       store[:foo]             # => 0
#       store[:nope]            # => nil
#       store.fetch(:baz)       # => 2
#       store.fetch(:nope, nil) # => nil
#       store.fetch(:nope)      # Raises exception.
#     end
#   end
#
# === Querying the Store
#
# Use method #key? to determine whether a given key exists:
#
#   example_store do |store|
#     store.transaction do
#       store.key?(:foo) # => true
#     end
#   end
#
# Use method #keys to retrieve keys:
#
#   example_store do |store|
#     store.transaction do
#       store.keys # => [:foo, :bar, :baz]
#     end
#   end
#
# Use method #path to retrieve the path to the store's underlying file;
# this method may be called from outside a transaction block:
#
#   store = PStore.new('t.store')
#   store.path # => "t.store"
#
# == Transaction Safety
#
# For transaction safety, see:
#
# - Optional argument +thread_safe+ at method PStore.new.
# - Attribute #ultra_safe.
#
# Needless to say, if you're storing valuable data with \PStore, then you should
# backup the \PStore file from time to time.
#
# == An Example Store
#
#  require "pstore"
#
#  # A mock wiki object.
#  class WikiPage
#
#    attr_reader :page_name
#
#    def initialize(page_name, author, contents)
#      @page_name = page_name
#      @revisions = Array.new
#      add_revision(author, contents)
#    end
#
#    def add_revision(author, contents)
#      @revisions << {created: Time.now,
#                     author: author,
#                     contents: contents}
#    end
#
#    def wiki_page_references
#      [@page_name] + @revisions.last[:contents].scan(/\b(?:[A-Z]+[a-z]+){2,}/)
#    end
#
#  end
#
#  # Create a new wiki page.
#  home_page = WikiPage.new("HomePage", "James Edward Gray II",
#                           "A page about the JoysOfDocumentation..." )
#
#  wiki = PStore.new("wiki_pages.pstore")
#  # Update page data and the index together, or not at all.
#  wiki.transaction do
#    # Store page.
#    wiki[home_page.page_name] = home_page
#    # Create page index.
#    wiki[:wiki_index] ||= Array.new
#    # Update wiki index.
#    wiki[:wiki_index].push(*home_page.wiki_page_references)
#  end
#
#  # Read wiki data, setting argument read_only to true.
#  wiki.transaction(true) do
#    wiki.keys.each do |key|
#      puts key
#      puts wiki[key]
#    end
#  end
#
class PStore
  VERSION = "0.1.3"

  RDWR_ACCESS = {mode: IO::RDWR | IO::CREAT | IO::BINARY, encoding: Encoding::ASCII_8BIT}.freeze
  RD_ACCESS = {mode: IO::RDONLY | IO::BINARY, encoding: Encoding::ASCII_8BIT}.freeze
  WR_ACCESS = {mode: IO::WRONLY | IO::CREAT | IO::TRUNC | IO::BINARY, encoding: Encoding::ASCII_8BIT}.freeze

  # The error type thrown by all PStore methods.
  class Error < StandardError
  end

  # Whether \PStore should do its best to prevent file corruptions,
  # even when an unlikely error (such as memory-error or filesystem error) occurs:
  #
  # - +true+: changes are posted by creating a temporary file,
  #   writing the updated data to it, then renaming the file to the given #path.
  #   File integrity is maintained.
  #   Note: has effect only if the filesystem has atomic file rename
  #   (as do POSIX platforms Linux, MacOS, FreeBSD and others).
  #
  # - +false+ (the default): changes are posted by rewinding the open file
  #   and writing the updated data.
  #   File integrity is maintained if the filesystem raises
  #   no unexpected I/O error;
  #   if such an error occurs during a write to the store,
  #   the file may become corrupted.
  #
  attr_accessor :ultra_safe

  # Returns a new \PStore object.
  #
  # Argument +file+ is the path to the file in which objects are to be stored;
  # if the file exists, it should be one that was written by \PStore.
  #
  #   path = 't.store'
  #   store = PStore.new(path)
  #
  # A \PStore object is
  # {reentrant}[https://en.wikipedia.org/wiki/Reentrancy_(computing)].
  # If argument +thread_safe+ is given as +true+,
  # the object is also thread-safe (at the cost of a small performance penalty):
  #
  #   store = PStore.new(path, true)
  #
  def initialize(file, thread_safe = false)
    dir = File::dirname(file)
    unless File::directory? dir
      raise PStore::Error, format("directory %s does not exist", dir)
    end
    if File::exist? file and not File::readable? file
      raise PStore::Error, format("file %s not readable", file)
    end
    @filename = file
    @abort = false
    @ultra_safe = false
    @thread_safe = thread_safe
    @lock = Thread::Mutex.new
  end

  # Raises PStore::Error if the calling code is not in a PStore#transaction.
  def in_transaction
    raise PStore::Error, "not in transaction" unless @lock.locked?
  end
  #
  # Raises PStore::Error if the calling code is not in a PStore#transaction or
  # if the code is in a read-only PStore#transaction.
  #
  def in_transaction_wr
    in_transaction
    raise PStore::Error, "in read-only transaction" if @rdonly
  end
  private :in_transaction, :in_transaction_wr

  # Returns the value for the given +key+ if the key exists.
  # +nil+ otherwise;
  # if not +nil+, the returned value is an object or a hierarchy of objects:
  #
  #   example_store do |store|
  #     store.transaction do
  #       store[:foo]  # => 0
  #       store[:nope] # => nil
  #     end
  #   end
  #
  # Returns +nil+ if there is no such key.
  #
  # See also {Hierarchical Values}[rdoc-ref:PStore@Hierarchical+Values].
  #
  # Raises an exception if called outside a transaction block.
  def [](key)
    in_transaction
    @table[key]
  end

  # Like #[], except that it accepts a default value for the store.
  # If the +key+ does not exist:
  #
  # - Raises an exception if +default+ is +PStore::Error+.
  # - Returns the value of +default+ otherwise:
  #
  #     example_store do |store|
  #       store.transaction do
  #         store.fetch(:nope, nil) # => nil
  #         store.fetch(:nope)      # Raises an exception.
  #       end
  #     end
  #
  # Raises an exception if called outside a transaction block.
  def fetch(key, default=PStore::Error)
    in_transaction
    unless @table.key? key
      if default == PStore::Error
        raise PStore::Error, format("undefined key `%s'", key)
      else
        return default
      end
    end
    @table[key]
  end

  # Creates or replaces the value for the given +key+:
  #
  #   example_store do |store|
  #     temp.transaction do
  #       temp[:bat] = 3
  #     end
  #   end
  #
  # See also {Hierarchical Values}[rdoc-ref:PStore@Hierarchical+Values].
  #
  # Raises an exception if called outside a transaction block.
  def []=(key, value)
    in_transaction_wr
    @table[key] = value
  end

  # Removes and returns the value at +key+ if it exists:
  #
  #   example_store do |store|
  #     store.transaction do
  #       store[:bat] = 3
  #       store.delete(:bat)
  #     end
  #   end
  #
  # Returns +nil+ if there is no such key.
  #
  # Raises an exception if called outside a transaction block.
  def delete(key)
    in_transaction_wr
    @table.delete key
  end

  # Returns an array of the existing keys:
  #
  #   example_store do |store|
  #     store.transaction do
  #       store.keys # => [:foo, :bar, :baz]
  #     end
  #   end
  #
  # Raises an exception if called outside a transaction block.
  def keys
    in_transaction
    @table.keys
  end
  alias roots keys

  # Returns +true+ if +key+ exists, +false+ otherwise:
  #
  #   example_store do |store|
  #     store.transaction do
  #       store.key?(:foo) # => true
  #     end
  #   end
  #
  # Raises an exception if called outside a transaction block.
  def key?(key)
    in_transaction
    @table.key? key
  end
  alias root? key?

  # Returns the string file path used to create the store:
  #
  #   store.path # => "flat.store"
  #
  def path
    @filename
  end

  # Exits the current transaction block, committing any changes
  # specified in the
  # {transaction block}[rdoc-ref:PStore@The+Transaction+Block].
  #
  # Raises an exception if called outside a transaction block.
  def commit
    in_transaction
    @abort = false
    throw :pstore_abort_transaction
  end

  # Exits the current transaction block, discarding any changes
  # specified in the
  # {transaction block}[rdoc-ref:PStore@The+Transaction+Block].
  #
  # Raises an exception if called outside a transaction block.
  def abort
    in_transaction
    @abort = true
    throw :pstore_abort_transaction
  end

  # Opens a transaction block for the store.
  # See {Transactions}[rdoc-ref:PStore@Transactions].
  #
  # With argument +read_only+ as +false+, the block may both read from
  # and write to the store.
  #
  # With argument +read_only+ as +true+, the block may not include calls
  # to #transaction, #[]=, or #delete.
  #
  # Raises an exception if called within a transaction block.
  def transaction(read_only = false)  # :yields:  pstore
    value = nil
    if !@thread_safe
      raise PStore::Error, "nested transaction" unless @lock.try_lock
    else
      begin
        @lock.lock
      rescue ThreadError
        raise PStore::Error, "nested transaction"
      end
    end
    begin
      @rdonly = read_only
      @abort = false
      file = open_and_lock_file(@filename, read_only)
      if file
        begin
          @table, checksum, original_data_size = load_data(file, read_only)

          catch(:pstore_abort_transaction) do
            value = yield(self)
          end

          if !@abort && !read_only
            save_data(checksum, original_data_size, file)
          end
        ensure
          file.close
        end
      else
        # This can only occur if read_only == true.
        @table = {}
        catch(:pstore_abort_transaction) do
          value = yield(self)
        end
      end
    ensure
      @lock.unlock
    end
    value
  end

  private
  # Constant for relieving Ruby's garbage collector.
  CHECKSUM_ALGO = %w[SHA512 SHA384 SHA256 SHA1 RMD160 MD5].each do |algo|
    begin
      break Digest(algo)
    rescue LoadError
    end
  end
  EMPTY_STRING = ""
  EMPTY_MARSHAL_DATA = Marshal.dump({})
  EMPTY_MARSHAL_CHECKSUM = CHECKSUM_ALGO.digest(EMPTY_MARSHAL_DATA)

  #
  # Open the specified filename (either in read-only mode or in
  # read-write mode) and lock it for reading or writing.
  #
  # The opened File object will be returned. If _read_only_ is true,
  # and the file does not exist, then nil will be returned.
  #
  # All exceptions are propagated.
  #
  def open_and_lock_file(filename, read_only)
    if read_only
      begin
        file = File.new(filename, **RD_ACCESS)
        begin
          file.flock(File::LOCK_SH)
          return file
        rescue
          file.close
          raise
        end
      rescue Errno::ENOENT
        return nil
      end
    else
      file = File.new(filename, **RDWR_ACCESS)
      file.flock(File::LOCK_EX)
      return file
    end
  end

  # Load the given PStore file.
  # If +read_only+ is true, the unmarshalled Hash will be returned.
  # If +read_only+ is false, a 3-tuple will be returned: the unmarshalled
  # Hash, a checksum of the data, and the size of the data.
  def load_data(file, read_only)
    if read_only
      begin
        table = load(file)
        raise Error, "PStore file seems to be corrupted." unless table.is_a?(Hash)
      rescue EOFError
        # This seems to be a newly-created file.
        table = {}
      end
      table
    else
      data = file.read
      if data.empty?
        # This seems to be a newly-created file.
        table = {}
        checksum = empty_marshal_checksum
        size = empty_marshal_data.bytesize
      else
        table = load(data)
        checksum = CHECKSUM_ALGO.digest(data)
        size = data.bytesize
        raise Error, "PStore file seems to be corrupted." unless table.is_a?(Hash)
      end
      data.replace(EMPTY_STRING)
      [table, checksum, size]
    end
  end

  def on_windows?
    is_windows = RUBY_PLATFORM =~ /mswin|mingw|bccwin|wince/
    self.class.__send__(:define_method, :on_windows?) do
      is_windows
    end
    is_windows
  end

  def save_data(original_checksum, original_file_size, file)
    new_data = dump(@table)

    if new_data.bytesize != original_file_size || CHECKSUM_ALGO.digest(new_data) != original_checksum
      if @ultra_safe && !on_windows?
        # Windows doesn't support atomic file renames.
        save_data_with_atomic_file_rename_strategy(new_data, file)
      else
        save_data_with_fast_strategy(new_data, file)
      end
    end

    new_data.replace(EMPTY_STRING)
  end

  def save_data_with_atomic_file_rename_strategy(data, file)
    temp_filename = "#{@filename}.tmp.#{Process.pid}.#{rand 1000000}"
    temp_file = File.new(temp_filename, **WR_ACCESS)
    begin
      temp_file.flock(File::LOCK_EX)
      temp_file.write(data)
      temp_file.flush
      File.rename(temp_filename, @filename)
    rescue
      File.unlink(temp_file) rescue nil
      raise
    ensure
      temp_file.close
    end
  end

  def save_data_with_fast_strategy(data, file)
    file.rewind
    file.write(data)
    file.truncate(data.bytesize)
  end


  # This method is just a wrapped around Marshal.dump
  # to allow subclass overriding used in YAML::Store.
  def dump(table)  # :nodoc:
    Marshal::dump(table)
  end

  # This method is just a wrapped around Marshal.load.
  # to allow subclass overriding used in YAML::Store.
  def load(content)  # :nodoc:
    Marshal::load(content)
  end

  def empty_marshal_data
    EMPTY_MARSHAL_DATA
  end
  def empty_marshal_checksum
    EMPTY_MARSHAL_CHECKSUM
  end
end
