class Bundler::Thor
  class NestedContext
    def initialize
      @depth = 0
    end

    def enter
      push

      yield
    ensure
      pop
    end

    def entered?
      @depth.positive?
    end

  private

    def push
      @depth += 1
    end

    def pop
      @depth -= 1
    end
  end
end
