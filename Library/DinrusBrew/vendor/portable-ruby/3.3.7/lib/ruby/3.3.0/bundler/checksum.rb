# frozen_string_literal: true

module Bundler
  class Checksum
    ALGO_SEPARATOR = "="
    DEFAULT_ALGORITHM = "sha256"
    private_constant :DEFAULT_ALGORITHM
    DEFAULT_BLOCK_SIZE = 16_384
    private_constant :DEFAULT_BLOCK_SIZE

    class << self
      def from_gem_package(gem_package, algo = DEFAULT_ALGORITHM)
        return if Bundler.settings[:disable_checksum_validation]
        return unless source = gem_package.instance_variable_get(:@gem)
        return unless source.respond_to?(:with_read_io)

        source.with_read_io do |io|
          from_gem(io, source.path)
        ensure
          io.rewind
        end
      end

      def from_gem(io, pathname, algo = DEFAULT_ALGORITHM)
        digest = Bundler::SharedHelpers.digest(algo.upcase).new
        buf = String.new(capacity: DEFAULT_BLOCK_SIZE)
        digest << io.readpartial(DEFAULT_BLOCK_SIZE, buf) until io.eof?
        Checksum.new(algo, digest.hexdigest!, Source.new(:gem, pathname))
      end

      def from_api(digest, source_uri, algo = DEFAULT_ALGORITHM)
        return if Bundler.settings[:disable_checksum_validation]

        Checksum.new(algo, to_hexdigest(digest, algo), Source.new(:api, source_uri))
      end

      def from_lock(lock_checksum, lockfile_location)
        algo, digest = lock_checksum.strip.split(ALGO_SEPARATOR, 2)
        Checksum.new(algo, to_hexdigest(digest, algo), Source.new(:lock, lockfile_location))
      end

      def to_hexdigest(digest, algo = DEFAULT_ALGORITHM)
        return digest unless algo == DEFAULT_ALGORITHM
        return digest if digest.match?(/\A[0-9a-f]{64}\z/i)

        if digest.match?(%r{\A[-0-9a-z_+/]{43}={0,2}\z}i)
          digest = digest.tr("-_", "+/") # fix urlsafe base64
          digest.unpack1("m0").unpack1("H*")
        else
          raise ArgumentError, "#{digest.inspect} is not a valid SHA256 hex or base64 digest"
        end
      end
    end

    attr_reader :algo, :digest, :sources

    def initialize(algo, digest, source)
      @algo = algo
      @digest = digest
      @sources = [source]
    end

    def ==(other)
      match?(other) && other.sources == sources
    end

    alias_method :eql?, :==

    def same_source?(other)
      sources.include?(other.sources.first)
    end

    def match?(other)
      other.is_a?(self.class) && other.digest == digest && other.algo == algo
    end

    def hash
      digest.hash
    end

    def to_s
      "#{to_lock} (from #{sources.first}#{", ..." if sources.size > 1})"
    end

    def to_lock
      "#{algo}#{ALGO_SEPARATOR}#{digest}"
    end

    def merge!(other)
      return nil unless match?(other)

      @sources.concat(other.sources).uniq!
      self
    end

    def formatted_sources
      sources.join("\n    and ").concat("\n")
    end

    def removable?
      sources.all?(&:removable?)
    end

    def removal_instructions
      msg = +""
      i = 1
      sources.each do |source|
        msg << "  #{i}. #{source.removal}\n"
        i += 1
      end
      msg << "  #{i}. run `bundle install`\n"
    end

    def inspect
      abbr = "#{algo}#{ALGO_SEPARATOR}#{digest[0, 8]}"
      from = "from #{sources.join(" and ")}"
      "#<#{self.class}:#{object_id} #{abbr} #{from}>"
    end

    class Source
      attr_reader :type, :location

      def initialize(type, location)
        @type = type
        @location = location
      end

      def removable?
        type == :lock || type == :gem
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.location == location
      end

      # phrased so that the usual string format is grammatically correct
      #   rake (10.3.2) sha256=abc123 from #{to_s}
      def to_s
        case type
        when :lock
          "the lockfile CHECKSUMS at #{location}"
        when :gem
          "the gem at #{location}"
        when :api
          "the API at #{location}"
        else
          "#{location} (#{type})"
        end
      end

      # A full sentence describing how to remove the checksum
      def removal
        case type
        when :lock
          "remove the matching checksum in #{location}"
        when :gem
          "remove the gem at #{location}"
        when :api
          "checksums from #{location} cannot be locally modified, you may need to update your sources"
        else
          "remove #{location} (#{type})"
        end
      end
    end

    class Store
      attr_reader :store
      protected :store

      def initialize
        @store = {}
        @store_mutex = Mutex.new
      end

      def inspect
        "#<#{self.class}:#{object_id} size=#{store.size}>"
      end

      # Replace when the new checksum is from the same source.
      # The primary purpose is registering checksums from gems where there are
      # duplicates of the same gem (according to full_name) in the index.
      #
      # In particular, this is when 2 gems have two similar platforms, e.g.
      # "darwin20" and "darwin-20", both of which resolve to darwin-20.
      # In the Index, the later gem replaces the former, so we do that here.
      #
      # However, if the new checksum is from a different source, we register like normal.
      # This ensures a mismatch error where there are multiple top level sources
      # that contain the same gem with different checksums.
      def replace(spec, checksum)
        return unless checksum

        lock_name = spec.name_tuple.lock_name
        @store_mutex.synchronize do
          existing = fetch_checksum(lock_name, checksum.algo)
          if !existing || existing.same_source?(checksum)
            store_checksum(lock_name, checksum)
          else
            merge_checksum(lock_name, checksum, existing)
          end
        end
      end

      def register(spec, checksum)
        return unless checksum

        register_checksum(spec.name_tuple.lock_name, checksum)
      end

      def merge!(other)
        other.store.each do |lock_name, checksums|
          checksums.each do |_algo, checksum|
            register_checksum(lock_name, checksum)
          end
        end
      end

      def to_lock(spec)
        lock_name = spec.name_tuple.lock_name
        checksums = @store[lock_name]
        if checksums
          "#{lock_name} #{checksums.values.map(&:to_lock).sort.join(",")}"
        else
          lock_name
        end
      end

      private

      def register_checksum(lock_name, checksum)
        @store_mutex.synchronize do
          existing = fetch_checksum(lock_name, checksum.algo)
          if existing
            merge_checksum(lock_name, checksum, existing)
          else
            store_checksum(lock_name, checksum)
          end
        end
      end

      def merge_checksum(lock_name, checksum, existing)
        existing.merge!(checksum) || raise(ChecksumMismatchError.new(lock_name, existing, checksum))
      end

      def store_checksum(lock_name, checksum)
        (@store[lock_name] ||= {})[checksum.algo] = checksum
      end

      def fetch_checksum(lock_name, algo)
        @store[lock_name]&.fetch(algo, nil)
      end
    end
  end
end
