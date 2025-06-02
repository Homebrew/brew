class Bundler::ConnectionPool
  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown, :wrapped_pool]

    def initialize(options = {}, &block)
      @pool = options.fetch(:pool) { ::Bundler::ConnectionPool.new(options, &block) }
    end

    def wrapped_pool
      @pool
    end

    def with(&block)
      @pool.with(&block)
    end

    def pool_shutdown(&block)
      @pool.shutdown(&block)
    end

    def pool_size
      @pool.size
    end

    def pool_available
      @pool.available
    end

    def respond_to?(id, *args)
      METHODS.include?(id) || with { |c| c.respond_to?(id, *args) }
    end

    # rubocop:disable Style/MissingRespondToMissing
    if ::RUBY_VERSION >= "3.0.0"
      def method_missing(name, *args, **kwargs, &block)
        with do |connection|
          connection.send(name, *args, **kwargs, &block)
        end
      end
    elsif ::RUBY_VERSION >= "2.7.0"
      ruby2_keywords def method_missing(name, *args, &block)
        with do |connection|
          connection.send(name, *args, &block)
        end
      end
    else
      def method_missing(name, *args, &block)
        with do |connection|
          connection.send(name, *args, &block)
        end
      end
    end
    # rubocop:enable Style/MethodMissingSuper
    # rubocop:enable Style/MissingRespondToMissing
  end
end
