# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "dependable"
require "dependency"
require "dependencies"
require "build_environment"

# A base class for non-formula requirements needed by formulae.
# A fatal requirement is one that will fail the build if it is not present.
# By default, requirements are non-fatal.
class Requirement
  include Dependable
  extend Cachable
  extend T::Helpers

  # This base class enforces no constraints on its own.
  # Individual subclasses use the `satisfy` DSL to define those constraints.
  abstract!

  attr_reader :name, :cask, :download

  def initialize(tags = [])
    @cask = self.class.cask
    @download = self.class.download
    tags.each do |tag|
      next unless tag.is_a? Hash

      @cask ||= tag[:cask]
      @download ||= tag[:download]
    end
    @tags = tags
    @tags << :build if self.class.build
    @name ||= infer_name
  end

  def option_names
    [name]
  end

  # The message to show when the requirement is not met.
  sig { returns(String) }
  def message
    _, _, class_name = self.class.to_s.rpartition "::"
    s = "#{class_name} unsatisfied!\n"
    if cask
      s += <<~EOS
        You can install the necessary cask with:
          brew install --cask #{cask}
      EOS
    end

    if download
      s += <<~EOS
        You can download from:
          #{Formatter.url(download)}
      EOS
    end
    s
  end

  # Overriding {#satisfied?} is unsupported.
  # Pass a block or boolean to the satisfy DSL method instead.
  sig {
    params(
      env:          T.nilable(String),
      cc:           T.nilable(String),
      build_bottle: T::Boolean,
      bottle_arch:  T.nilable(String),
    ).returns(T::Boolean)
  }
  def satisfied?(env: nil, cc: nil, build_bottle: false, bottle_arch: nil)
    satisfy = self.class.satisfy
    return true unless satisfy

    @satisfied_result =
      satisfy.yielder(env:, cc:, build_bottle:, bottle_arch:) do |p|
        instance_eval(&p)
      end
    return false unless @satisfied_result

    true
  end

  # Overriding {#fatal?} is unsupported.
  # Pass a boolean to the fatal DSL method instead.
  sig { returns(T::Boolean) }
  def fatal?
    self.class.fatal || false
  end

  def satisfied_result_parent
    return unless @satisfied_result.is_a?(Pathname)

    parent = @satisfied_result.resolved_path.parent
    if parent.to_s =~ %r{^#{Regexp.escape(HOMEBREW_CELLAR)}/([\w+-.@]+)/[^/]+/(s?bin)/?$}o
      parent = HOMEBREW_PREFIX/"opt/#{Regexp.last_match(1)}/#{Regexp.last_match(2)}"
    end
    parent
  end

  # Pass a block to the env DSL method instead of overriding.
  sig(:final) {
    params(
      env:          T.nilable(String),
      cc:           T.nilable(String),
      build_bottle: T::Boolean,
      bottle_arch:  T.nilable(String),
    ).void
  }
  def modify_build_environment(env: nil, cc: nil, build_bottle: false, bottle_arch: nil)
    satisfied?(env:, cc:, build_bottle:, bottle_arch:)
    instance_eval(&env_proc) if env_proc

    # XXX If the satisfy block returns a Pathname, then make sure that it
    # remains available on the PATH. This makes requirements like
    #   satisfy { which("executable") }
    # work, even under superenv where "executable" wouldn't normally be on the
    # PATH.
    parent = satisfied_result_parent
    return unless parent
    return if ["#{HOMEBREW_PREFIX}/bin", "#{HOMEBREW_PREFIX}/bin"].include?(parent.to_s)
    return if PATH.new(ENV.fetch("PATH")).include?(parent.to_s)

    ENV.prepend_path("PATH", parent)
  end

  def env
    self.class.env
  end

  def env_proc
    self.class.env_proc
  end

  def ==(other)
    instance_of?(other.class) && name == other.name && tags == other.tags
  end
  alias eql? ==

  def hash
    [self.class, name, tags].hash
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{tags.inspect}>"
  end

  def display_s
    name.capitalize
  end

  def mktemp(&block)
    Mktemp.new(name).run(&block)
  end

  private

  def infer_name
    klass = self.class.name
    klass = klass&.sub(/(Dependency|Requirement)$/, "")
                 &.sub(/^(\w+::)*/, "")
    return klass.downcase if klass.present?

    return @cask if @cask.present?

    ""
  end

  def which(cmd)
    super(cmd, PATH.new(ORIGINAL_PATHS))
  end

  def which_all(cmd)
    super(cmd, PATH.new(ORIGINAL_PATHS))
  end

  class << self
    include BuildEnvironment::DSL

    attr_reader :env_proc, :build

    sig { params(val: String).returns(T.nilable(String)) }
    def cask(val = T.unsafe(nil))
      val.nil? ? @cask : @cask = val
    end

    sig { params(val: String).returns(T.nilable(String)) }
    def download(val = T.unsafe(nil))
      val.nil? ? @download : @download = val
    end

    sig { params(val: T::Boolean).returns(T.nilable(T::Boolean)) }
    def fatal(val = T.unsafe(nil))
      val.nil? ? @fatal : @fatal = val
    end

    def satisfy(options = nil, &block)
      return @satisfied if options.nil? && !block

      options = {} if options.nil?
      @satisfied = Satisfier.new(options, &block)
    end

    def env(*settings, &block)
      if block
        @env_proc = block
      else
        super
      end
    end
  end

  # Helper class for evaluating whether a requirement is satisfied.
  class Satisfier
    def initialize(options, &block)
      case options
      when Hash
        @options = { build_env: true }
        @options.merge!(options)
      else
        @satisfied = options
      end
      @proc = block
    end

    def yielder(env: nil, cc: nil, build_bottle: false, bottle_arch: nil)
      if instance_variable_defined?(:@satisfied)
        @satisfied
      elsif @options[:build_env]
        require "extend/ENV"
        ENV.with_build_environment(
          env:, cc:, build_bottle:, bottle_arch:,
        ) do
          yield @proc
        end
      else
        yield @proc
      end
    end
  end
  private_constant :Satisfier

  class << self
    # Expand the requirements of dependent recursively, optionally yielding
    # `[dependent, req]` pairs to allow callers to apply arbitrary filters to
    # the list.
    # The default filter, which is applied when a block is not given, omits
    # optionals and recommends based on what the dependent has asked for.
    def expand(dependent, cache_key: nil, &block)
      if cache_key.present?
        cache[cache_key] ||= {}
        return cache[cache_key][cache_id dependent].dup if cache[cache_key][cache_id dependent]
      end

      reqs = Requirements.new

      formulae = dependent.recursive_dependencies.map(&:to_formula)
      formulae.unshift(dependent)

      formulae.each do |f|
        f.requirements.each do |req|
          next if prune?(f, req, &block)

          reqs << req
        end
      end

      if cache_key.present?
        # Even though we setup the cache above
        # 'dependent.recursive_dependencies.map(&:to_formula)'
        # is invalidating the singleton cache
        cache[cache_key] ||= {}
        cache[cache_key][cache_id dependent] = reqs.dup
      end
      reqs
    end

    def prune?(dependent, req, &block)
      catch(:prune) do
        if block
          yield dependent, req
        elsif req.optional? || req.recommended?
          prune unless dependent.build.with?(req)
        end
      end
    end

    # Used to prune requirements when calling expand with a block.
    sig { void }
    def prune
      throw(:prune, true)
    end

    private

    def cache_id(dependent)
      "#{dependent.full_name}_#{dependent.class}"
    end
  end
end
