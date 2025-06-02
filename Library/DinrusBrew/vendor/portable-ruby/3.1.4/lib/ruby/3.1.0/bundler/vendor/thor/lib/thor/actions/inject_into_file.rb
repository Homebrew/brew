require_relative "empty_directory"

class Bundler::Thor
  module Actions
    # Injects the given content into a file. Different from gsub_file, this
    # method is reversible.
    #
    # ==== Parameters
    # destination<String>:: Relative path to the destination root
    # data<String>:: Data to add to the file. Can be given as a block.
    # config<Hash>:: give :verbose => false to not log the status and the flag
    #                for injection (:after or :before) or :force => true for
    #                insert two or more times the same content.
    #
    # ==== Examples
    #
    #   insert_into_file "config/environment.rb", "config.gem :thor", :after => "Rails::Initializer.run do |config|\n"
    #
    #   insert_into_file "config/environment.rb", :after => "Rails::Initializer.run do |config|\n" do
    #     gems = ask "Which gems would you like to add?"
    #     gems.split(" ").map{ |gem| "  config.gem :#{gem}" }.join("\n")
    #   end
    #
    WARNINGS = { unchanged_no_flag: 'File unchanged! The supplied flag value not found!' }

    def insert_into_file(destination, *args, &block)
      data = block_given? ? block : args.shift

      config = args.shift || {}
      config[:after] = /\z/ unless config.key?(:before) || config.key?(:after)

      action InjectIntoFile.new(self, destination, data, config)
    end
    alias_method :inject_into_file, :insert_into_file

    class InjectIntoFile < EmptyDirectory #:nodoc:
      attr_reader :replacement, :flag, :behavior

      def initialize(base, destination, data, config)
        super(base, destination, {:verbose => true}.merge(config))

        @behavior, @flag = if @config.key?(:after)
          [:after, @config.delete(:after)]
        else
          [:before, @config.delete(:before)]
        end

        @replacement = data.is_a?(Proc) ? data.call : data
        @flag = Regexp.escape(@flag) unless @flag.is_a?(Regexp)
      end

      def invoke!
        content = if @behavior == :after
          '\0' + replacement
        else
          replacement + '\0'
        end

        if exists?
          if replace!(/#{flag}/, content, config[:force])
            say_status(:invoke)
          else
            say_status(:unchanged, warning: WARNINGS[:unchanged_no_flag], color: :red)
          end
        else
          unless pretend?
            raise Bundler::Thor::Error, "The file #{ destination } does not appear to exist"
          end
        end
      end

      def revoke!
        say_status :revoke

        regexp = if @behavior == :after
          content = '\1\2'
          /(#{flag})(.*)(#{Regexp.escape(replacement)})/m
        else
          content = '\2\3'
          /(#{Regexp.escape(replacement)})(.*)(#{flag})/m
        end

        replace!(regexp, content, true)
      end

    protected

      def say_status(behavior, warning: nil, color: nil)
        status = if behavior == :invoke
          if flag == /\A/
            :prepend
          elsif flag == /\z/
            :append
          else
            :insert
          end
        elsif warning
          warning
        else
          :subtract
        end

        super(status, (color || config[:verbose]))
      end

      # Adds the content to the file.
      #
      def replace!(regexp, string, force)
        content = File.read(destination)
        if force || !content.include?(replacement)
          success = content.gsub!(regexp, string)

          File.open(destination, "wb") { |file| file.write(content) } unless pretend?
          success
        end
      end
    end
  end
end
