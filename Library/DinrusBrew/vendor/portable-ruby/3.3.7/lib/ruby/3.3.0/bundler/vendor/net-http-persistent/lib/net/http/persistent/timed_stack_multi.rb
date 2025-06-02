class Gem::Net::HTTP::Persistent::TimedStackMulti < Bundler::ConnectionPool::TimedStack # :nodoc:

  ##
  # Returns a new hash that has arrays for keys
  #
  # Using a class method to limit the bindings referenced by the hash's
  # default_proc

  def self.hash_of_arrays # :nodoc:
    Hash.new { |h,k| h[k] = [] }
  end

  def initialize(size = 0, &block)
    super

    @enqueued = 0
    @ques = self.class.hash_of_arrays
    @lru = {}
    @key = :"connection_args-#{object_id}"
  end

  def empty?
    (@created - @enqueued) >= @max
  end

  def length
    @max - @created + @enqueued
  end

  private

  def connection_stored? options = {} # :nodoc:
    !@ques[options[:connection_args]].empty?
  end

  def fetch_connection options = {} # :nodoc:
    connection_args = options[:connection_args]

    @enqueued -= 1
    lru_update connection_args
    @ques[connection_args].pop
  end

  def lru_update connection_args # :nodoc:
    @lru.delete connection_args
    @lru[connection_args] = true
  end

  def shutdown_connections # :nodoc:
    @ques.each_key do |key|
      super connection_args: key
    end
  end

  def store_connection obj, options = {} # :nodoc:
    @ques[options[:connection_args]].push obj
    @enqueued += 1
  end

  def try_create options = {} # :nodoc:
    connection_args = options[:connection_args]

    if @created >= @max && @enqueued >= 1
      oldest, = @lru.first
      @lru.delete oldest
      @ques[oldest].pop

      @created -= 1
    end

    if @created < @max
      @created += 1
      lru_update connection_args
      return @create_block.call(connection_args)
    end
  end

end

