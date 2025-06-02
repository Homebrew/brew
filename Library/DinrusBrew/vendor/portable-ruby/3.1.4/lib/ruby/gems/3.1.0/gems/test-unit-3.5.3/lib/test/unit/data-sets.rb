module Test
  module Unit
    class DataSets
      def initialize
        @variables = []
        @procs = []
        @value_sets = []
      end

      def add(data_set, options=nil)
        options ||= {}
        if data_set.respond_to?(:call)
          @procs << [data_set, options]
        elsif data_set.is_a?(Array)
          @variables << [data_set, options]
        else
          @value_sets << [data_set, options]
        end
      end

      def <<(data_set)
        add(data_set)
      end

      def have_keep?
        each_data_set do |_, options|
          return true if options[:keep]
        end
        false
      end

      def keep
        new_data_sets = self.class.new
        each_data_set do |data_set, options|
          next if options.nil?
          next unless options[:keep]
          new_data_sets.add(data_set, options)
        end
        new_data_sets
      end

      def each
        variables = @variables
        value_sets = @value_sets
        @procs.each do |proc, options|
          data_set = proc.call
          case data_set
          when Array
            variables += [[data_set, options]]
          else
            value_sets += [[data_set, options]]
          end
        end

        value_sets.each do |values, _options|
          values.each do |label, data|
            yield(label, data)
          end
        end

        each_pattern(variables) do |label, data|
          yield(label, data)
        end
      end

      def ==(other)
        @variables == other.instance_variable_get(:@variables) and
          @procs == other.instance_variable_get(:@procs) and
          @value_sets == other.instance_variable_get(:@value_sets)
      end

      def eql?(other)
        self == other
      end

      def hash
        [@variables, @procs, @value_sets].hash
      end

      private
      def each_data_set(&block)
        @procs.each(&block)
        @variables.each(&block)
        @value_sets.each(&block)
      end

      def each_pattern(variables)
        grouped_variables = variables.group_by do |_, options|
          options[:group]
        end
        grouped_variables.each do |group, group_variables|
          each_raw_pattern(group_variables) do |cell|
            label = String.new
            label << "group: #{group.inspect}" unless group.nil?
            data = {}
            cell.each do |variable, pattern, pattern_label|
              label << ", " unless label.empty?
              label << "#{variable}: #{pattern_label}"
              data[variable] = pattern
            end
            yield(label, data)
          end
        end
      end

      def each_raw_pattern(variables, &block)
        return if variables.empty?

        sorted_variables = variables.sort_by do |(variable, _), _|
          variable
        end
        all_patterns = sorted_variables.collect do |(variable, patterns), _|
          if patterns.is_a?(Hash)
            patterns.collect do |pattern_label, pattern|
              [variable, pattern, pattern_label]
            end
          else
            patterns.collect do |pattern|
              [variable, pattern, pattern.inspect]
            end
          end
        end
        all_patterns[0].product(*all_patterns[1..-1], &block)
      end
    end
  end
end
