# typed: strict
# frozen_string_literal: true

require "context"

module Homebrew
  extend Context

  sig { params(path: T.nilable(T.any(String, Pathname))).returns(T::Boolean) }
  def self.require?(path)
    return false if path.nil?

    if defined?(Warnings)
      # Work around require warning when done repeatedly:
      # https://bugs.ruby-lang.org/issues/21091
      Warnings.ignore(/already initialized constant/, /previous definition of/) do
        require path.to_s
      end
    else
      require path.to_s
    end
    true
  rescue LoadError
    false
  end

  # Need to keep this naming as-is for backwards compatibility.
  # rubocop:disable Naming/PredicateMethod
  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.any(Pathname, String),
      options: T.untyped,
      _block:  T.nilable(T.proc.void),
    ).returns(T::Boolean)
  }
  def self._system(cmd, argv0 = nil, *args, **options, &_block)
    pid = fork do
      yield if block_given?
      args.map!(&:to_s)
      begin
        if argv0
          exec(cmd, argv0, *args, **options)
        else
          exec(cmd, *args, **options)
        end
      rescue
        nil
      end
      exit! 1 # never gets here unless exec failed
    end
    Process.wait(pid)
    $CHILD_STATUS.success?
  end
  # TODO: make private_class_method when possible
  # private_class_method :_system
  # rubocop:enable Naming/PredicateMethod

  sig {
    params(
      cmd:     T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)]),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.any(Pathname, String),
      options: T.untyped,
    ).returns(T::Boolean)
  }
  def self.system(cmd, argv0 = nil, *args, **options)
    if verbose?
      out = (options[:out] == :err) ? $stderr : $stdout
      out.puts "#{cmd} #{args * " "}".gsub(RUBY_PATH, "ruby")
                                     .gsub($LOAD_PATH.join(File::PATH_SEPARATOR).to_s, "$LOAD_PATH")
    end
    _system(cmd, argv0, *args, **options)
  end

  # `Module` and `Regexp` are global variables used as types here so they don't need to be imported
  # rubocop:disable Style/GlobalVars
  sig { params(the_module: T::Module[T.anything], pattern: Regexp).void }
  def self.inject_dump_stats!(the_module, pattern)
    @injected_dump_stat_modules ||= T.let({}, T.nilable(T::Hash[T::Module[T.anything], T::Array[String]]))
    @injected_dump_stat_modules[the_module] ||= []
    injected_methods = @injected_dump_stat_modules.fetch(the_module)
    the_module.module_eval do
      instance_methods.grep(pattern).each do |name|
        next if injected_methods.include? name

        method = instance_method(name)
        define_method(name) do |*args, &block|
          require "time"

          time = Time.now

          begin
            method.bind_call(self, *args, &block)
          ensure
            $times[name] ||= 0
            $times[name] += Time.now - time
          end
        end
      end
    end

    return unless $times.nil?

    $times = {}
    at_exit do
      col_width = [$times.keys.map(&:size).max.to_i + 2, 15].max
      $times.sort_by { |_k, v| v }.each do |method, time|
        puts format("%<method>-#{col_width}s %<time>0.4f sec", method: "#{method}:", time:)
      end
    end
  end
  # rubocop:enable Style/GlobalVars
end

module Utils
  # Removes the rightmost segment from the constant expression in the string.
  #
  #   deconstantize('Net::HTTP')   # => "Net"
  #   deconstantize('::Net::HTTP') # => "::Net"
  #   deconstantize('String')      # => ""
  #   deconstantize('::String')    # => ""
  #   deconstantize('')            # => ""
  #
  # See also #demodulize.
  # @see https://github.com/rails/rails/blob/b0dd7c7/activesupport/lib/active_support/inflector/methods.rb#L247-L258
  #   `ActiveSupport::Inflector.deconstantize`
  sig { params(path: String).returns(String) }
  def self.deconstantize(path)
    T.must(path[0, path.rindex("::") || 0]) # implementation based on the one in facets' Module#spacename
  end

  # Removes the module part from the expression in the string.
  #
  #   demodulize('ActiveSupport::Inflector::Inflections') # => "Inflections"
  #   demodulize('Inflections')                           # => "Inflections"
  #   demodulize('::Inflections')                         # => "Inflections"
  #   demodulize('')                                      # => ""
  #
  # See also #deconstantize.
  # @see https://github.com/rails/rails/blob/b0dd7c7/activesupport/lib/active_support/inflector/methods.rb#L230-L245
  #   `ActiveSupport::Inflector.demodulize`
  # @raise [ArgumentError] if the provided path is nil
  sig { params(path: T.nilable(String)).returns(String) }
  def self.demodulize(path)
    raise ArgumentError, "No constant path provided" if path.nil?

    if (i = path.rindex("::"))
      T.must(path[(i + 2)..])
    else
      path
    end
  end

  # A lightweight alternative to `ActiveSupport::Inflector.pluralize`:
  # Combines `stem` with the `singular` or `plural` suffix based on `count`.
  # Adds a prefix of the count value if `include_count` is set to true.
  sig {
    params(stem: String, count: Integer, plural: String, singular: String, include_count: T::Boolean).returns(String)
  }
  def self.pluralize(stem, count, plural: "s", singular: "", include_count: false)
    case stem
    when "formula"
      plural = "e"
    when "dependency", "try"
      stem = stem.delete_suffix("y")
      plural = "ies"
      singular = "y"
    end

    prefix = include_count ? "#{count} " : ""
    suffix = (count == 1) ? singular : plural
    "#{prefix}#{stem}#{suffix}"
  end

  sig { params(author: String).returns({ email: String, name: String }) }
  def self.parse_author!(author)
    match_data = /^(?<name>[^<]+?)[ \t]*<(?<email>[^>]+?)>$/.match(author)
    if match_data
      name = match_data[:name]
      email = match_data[:email]
    end
    raise UsageError, "Unable to parse name and email." if name.blank? && email.blank?

    { name: T.must(name), email: T.must(email) }
  end

  # Makes an underscored, lowercase form from the expression in the string.
  #
  # Changes '::' to '/' to convert namespaces to paths.
  #
  #   underscore('ActiveModel')         # => "active_model"
  #   underscore('ActiveModel::Errors') # => "active_model/errors"
  #
  # @see https://github.com/rails/rails/blob/v6.1.7.2/activesupport/lib/active_support/inflector/methods.rb#L81-L100
  #   `ActiveSupport::Inflector.underscore`
  sig { params(camel_cased_word: T.any(String, Symbol)).returns(String) }
  def self.underscore(camel_cased_word)
    return camel_cased_word.to_s unless /[A-Z-]|::/.match?(camel_cased_word)

    word = camel_cased_word.to_s.gsub("::", "/")
    word.gsub!(/([A-Z])(?=[A-Z][a-z])|([a-z\d])(?=[A-Z])/) do
      T.must(::Regexp.last_match(1) || ::Regexp.last_match(2)) << "_"
    end
    word.tr!("-", "_")
    word.downcase!
    word
  end

  SAFE_FILENAME_REGEX = /[[:cntrl:]#{Regexp.escape("#{File::SEPARATOR}#{File::ALT_SEPARATOR}")}]/o
  private_constant :SAFE_FILENAME_REGEX

  sig { params(basename: String).returns(T::Boolean) }
  def self.safe_filename?(basename)
    !SAFE_FILENAME_REGEX.match?(basename)
  end

  sig { params(basename: String).returns(String) }
  def self.safe_filename(basename)
    basename.gsub(SAFE_FILENAME_REGEX, "")
  end

  # Converts a string starting with `:` to a symbol, otherwise returns the
  # string itself.
  #
  #   convert_to_string_or_symbol(":example") # => :example
  #   convert_to_string_or_symbol("example")  # => "example"
  sig { params(string: String).returns(T.any(String, Symbol)) }
  def self.convert_to_string_or_symbol(string)
    return T.must(string[1..]).to_sym if string.start_with?(":")

    string
  end
end
