# frozen_string_literal: true

require_relative "../explicit_require"

Bootsnap::ExplicitRequire.with_gems("msgpack") { require "msgpack" }

module Bootsnap
  module LoadPathCache
    class Store
      VERSION_KEY = "__bootsnap_ruby_version__"
      CURRENT_VERSION = "#{RUBY_REVISION}-#{RUBY_PLATFORM}".freeze # rubocop:disable Style/RedundantFreeze

      NestedTransactionError = Class.new(StandardError)
      SetOutsideTransactionNotAllowed = Class.new(StandardError)

      def initialize(store_path, readonly: false)
        @store_path = store_path
        @txn_mutex = Mutex.new
        @dirty = false
        @readonly = readonly
        load_data
      end

      def get(key)
        @data[key]
      end

      def fetch(key)
        raise(SetOutsideTransactionNotAllowed) unless @txn_mutex.owned?

        v = get(key)
        unless v
          v = yield
          mark_for_mutation!
          @data[key] = v
        end
        v
      end

      def set(key, value)
        raise(SetOutsideTransactionNotAllowed) unless @txn_mutex.owned?

        if value != @data[key]
          mark_for_mutation!
          @data[key] = value
        end
      end

      def transaction
        raise(NestedTransactionError) if @txn_mutex.owned?

        @txn_mutex.synchronize do
          yield
        ensure
          commit_transaction
        end
      end

      private

      def mark_for_mutation!
        @dirty = true
        @data = @data.dup if @data.frozen?
      end

      def commit_transaction
        if @dirty && !@readonly
          dump_data
          @dirty = false
        end
      end

      def load_data
        @data = begin
          data = File.open(@store_path, encoding: Encoding::BINARY) do |io|
            MessagePack.load(io, freeze: true)
          end
          if data.is_a?(Hash) && data[VERSION_KEY] == CURRENT_VERSION
            data
          else
            default_data
          end
        # handle malformed data due to upgrade incompatibility
        rescue Errno::ENOENT, MessagePack::MalformedFormatError, MessagePack::UnknownExtTypeError, EOFError
          default_data
        rescue ArgumentError => error
          if error.message =~ /negative array size/
            default_data
          else
            raise
          end
        end
      end

      def dump_data
        # Change contents atomically so other processes can't get invalid
        # caches if they read at an inopportune time.
        tmp = "#{@store_path}.#{Process.pid}.#{(rand * 100_000).to_i}.tmp"
        mkdir_p(File.dirname(tmp))
        exclusive_write = File::Constants::CREAT | File::Constants::EXCL | File::Constants::WRONLY
        # `encoding:` looks redundant wrt `binwrite`, but necessary on windows
        # because binary is part of mode.
        File.open(tmp, mode: exclusive_write, encoding: Encoding::BINARY) do |io|
          MessagePack.dump(@data, io)
        end
        File.rename(tmp, @store_path)
      rescue Errno::EEXIST
        retry
      rescue SystemCallError
      end

      def default_data
        {VERSION_KEY => CURRENT_VERSION}
      end

      def mkdir_p(path)
        stack = []
        until File.directory?(path)
          stack.push path
          path = File.dirname(path)
        end
        stack.reverse_each do |dir|
          Dir.mkdir(dir)
        rescue SystemCallError
          # Check for broken symlinks. Calling File.realpath will raise Errno::ENOENT if that is the case
          File.realpath(dir) if File.symlink?(dir)
          raise unless File.directory?(dir)
        end
      end
    end
  end
end
