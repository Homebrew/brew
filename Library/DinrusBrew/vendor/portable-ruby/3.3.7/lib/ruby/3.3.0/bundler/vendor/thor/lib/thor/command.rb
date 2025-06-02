class Bundler::Thor
  class Command < Struct.new(:name, :description, :long_description, :wrap_long_description, :usage, :options, :options_relation, :ancestor_name)
    FILE_REGEXP = /^#{Regexp.escape(File.dirname(__FILE__))}/

    def initialize(name, description, long_description, wrap_long_description, usage, options = nil, options_relation = nil)
      super(name.to_s, description, long_description, wrap_long_description, usage, options || {}, options_relation || {})
    end

    def initialize_copy(other) #:nodoc:
      super(other)
      self.options = other.options.dup if other.options
      self.options_relation = other.options_relation.dup if other.options_relation
    end

    def hidden?
      false
    end

    # By default, a command invokes a method in the thor class. You can change this
    # implementation to create custom commands.
    def run(instance, args = [])
      arity = nil

      if private_method?(instance)
        instance.class.handle_no_command_error(name)
      elsif public_method?(instance)
        arity = instance.method(name).arity
        instance.__send__(name, *args)
      elsif local_method?(instance, :method_missing)
        instance.__send__(:method_missing, name.to_sym, *args)
      else
        instance.class.handle_no_command_error(name)
      end
    rescue ArgumentError => e
      handle_argument_error?(instance, e, caller) ? instance.class.handle_argument_error(self, e, args, arity) : (raise e)
    rescue NoMethodError => e
      handle_no_method_error?(instance, e, caller) ? instance.class.handle_no_command_error(name) : (raise e)
    end

    # Returns the formatted usage by injecting given required arguments
    # and required options into the given usage.
    def formatted_usage(klass, namespace = true, subcommand = false)
      if ancestor_name
        formatted = "#{ancestor_name} ".dup # add space
      elsif namespace
        namespace = klass.namespace
        formatted = "#{namespace.gsub(/^(default)/, '')}:".dup
      end
      formatted ||= "#{klass.namespace.split(':').last} ".dup if subcommand

      formatted ||= "".dup

      Array(usage).map do |specific_usage|
        formatted_specific_usage = formatted

        formatted_specific_usage += required_arguments_for(klass, specific_usage)

        # Add required options
        formatted_specific_usage += " #{required_options}"

        # Strip and go!
        formatted_specific_usage.strip
      end.join("\n")
    end

    def method_exclusive_option_names #:nodoc:
      self.options_relation[:exclusive_option_names] || []
    end

    def method_at_least_one_option_names #:nodoc:
      self.options_relation[:at_least_one_option_names] || []
    end

  protected

    # Add usage with required arguments
    def required_arguments_for(klass, usage)
      if klass && !klass.arguments.empty?
        usage.to_s.gsub(/^#{name}/) do |match|
          match << " " << klass.arguments.map(&:usage).compact.join(" ")
        end
      else
        usage.to_s
      end
    end

    def not_debugging?(instance)
      !(instance.class.respond_to?(:debugging) && instance.class.debugging)
    end

    def required_options
      @required_options ||= options.map { |_, o| o.usage if o.required? }.compact.sort.join(" ")
    end

    # Given a target, checks if this class name is a public method.
    def public_method?(instance) #:nodoc:
      !(instance.public_methods & [name.to_s, name.to_sym]).empty?
    end

    def private_method?(instance)
      !(instance.private_methods & [name.to_s, name.to_sym]).empty?
    end

    def local_method?(instance, name)
      methods = instance.public_methods(false) + instance.private_methods(false) + instance.protected_methods(false)
      !(methods & [name.to_s, name.to_sym]).empty?
    end

    def sans_backtrace(backtrace, caller) #:nodoc:
      saned = backtrace.reject { |frame| frame =~ FILE_REGEXP || (frame =~ /\.java:/ && RUBY_PLATFORM =~ /java/) || (frame =~ %r{^kernel/} && RUBY_ENGINE =~ /rbx/) }
      saned - caller
    end

    def handle_argument_error?(instance, error, caller)
      not_debugging?(instance) && (error.message =~ /wrong number of arguments/ || error.message =~ /given \d*, expected \d*/) && begin
        saned = sans_backtrace(error.backtrace, caller)
        saned.empty? || saned.size == 1
      end
    end

    def handle_no_method_error?(instance, error, caller)
      not_debugging?(instance) &&
        error.message =~ /^undefined method `#{name}' for #{Regexp.escape(instance.to_s)}$/
    end
  end
  Task = Command

  # A command that is hidden in help messages but still invocable.
  class HiddenCommand < Command
    def hidden?
      true
    end
  end
  HiddenTask = HiddenCommand

  # A dynamic command that handles method missing scenarios.
  class DynamicCommand < Command
    def initialize(name, options = nil)
      super(name.to_s, "A dynamically-generated command", name.to_s, nil, name.to_s, options)
    end

    def run(instance, args = [])
      if (instance.methods & [name.to_s, name.to_sym]).empty?
        super
      else
        instance.class.handle_no_command_error(name)
      end
    end
  end
  DynamicTask = DynamicCommand
end
