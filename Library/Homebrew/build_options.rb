# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Options for a formula build.
class BuildOptions
  def initialize(args, options)
    @args = args
    @options = options
  end

  # True if a {Formula} is being built with a specific option.
  #
  # ### Examples
  #
  # ```ruby
  # args << "--i-want-spam" if build.with? "spam"
  # ```
  #
  # ```ruby
  # args << "--qt-gui" if build.with? "qt" # "--with-qt" ==> build.with? "qt"
  # ```
  #
  # If a formula presents a user with a choice, but the choice must be fulfilled:
  #
  # ```ruby
  # if build.with? "example2"
  #   args << "--with-example2"
  # else
  #   args << "--with-example1"
  # end
  # ```
  def with?(val)
    option_names = val.respond_to?(:option_names) ? val.option_names : [val]

    option_names.any? do |name|
      if option_defined? "with-#{name}"
        include? "with-#{name}"
      elsif option_defined? "without-#{name}"
        !include? "without-#{name}"
      else
        false
      end
    end
  end

  # True if a {Formula} is being built without a specific option.
  #
  # ### Example
  #
  # ```ruby
  # args << "--no-spam-plz" if build.without? "spam"
  # ```
  def without?(val)
    !with?(val)
  end

  # True if a {Formula} is being built as a bottle (i.e. binary package).
  def bottle?
    include? "build-bottle"
  end

  # True if a {Formula} is being built with {Formula.head} instead of {Formula.stable}.
  #
  # ### Examples
  #
  # ```ruby
  # args << "--some-new-stuff" if build.head?
  # ```
  #
  # If there are multiple conditional arguments use a block instead of lines.
  #
  # ```ruby
  # if build.head?
  #   args << "--i-want-pizza"
  #   args << "--and-a-cold-beer" if build.with? "cold-beer"
  # end
  # ```
  def head?
    include? "HEAD"
  end

  # True if a {Formula} is being built with {Formula.stable} instead of {Formula.head}.
  # This is the default.
  #
  # ### Example
  #
  # ```ruby
  # args << "--some-beta" if build.head?
  # ```
  def stable?
    !head?
  end

  # True if the build has any arguments or options specified.
  def any_args_or_options?
    !@args.empty? || !@options.empty?
  end

  def used_options
    @options & @args
  end

  def unused_options
    @options - @args
  end

  private

  def include?(name)
    @args.include?("--#{name}")
  end

  def option_defined?(name)
    @options.include? name
  end
end
