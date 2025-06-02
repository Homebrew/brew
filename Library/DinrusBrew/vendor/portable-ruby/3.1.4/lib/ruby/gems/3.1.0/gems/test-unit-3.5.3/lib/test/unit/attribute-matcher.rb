module Test
  module Unit
    class AttributeMatcher
      def initialize(test)
        @test = test
      end

      def match?(expression)
        matched = instance_eval(expression)
        if matched.nil?
          false
        else
          matched
        end
      end

      def method_missing(name, *args)
        if args.empty?
          @test[name]
        else
          super
        end
      end
    end
  end
end
