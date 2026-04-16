# typed: strict
# frozen_string_literal: true

require "dependable"
require "dependency"
require "dependencies"
require "build_environment"
require "utils/output"

# A base class for non-formula requirements needed by formulae.
# A fatal requirement is one that will fail the build if it is not present.
# By default, requirements are non-fatal.
class Requirement
  include Dependable
  include Utils::Output::Mixin
  extend Cachable
  extend T::Helpers

  # This base class enforces no constraints on its own.
  # Individual subclasses use the `satisfy` DSL to define those constraints.
  abstract!

  sig { abstract.returns(T.nilable(Tap)) }
  def tap; end

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.nilable(String)) }
  attr_reader :cask

  sig { returns(T.nilable(String)) }
  attr_reader :download

  sig { override.returns(T::Array[T.untyped]) }
  attr_reader :tags

  sig { params(tags: T::Array[T.untyped]).void }
  def initialize(tags = [])
    @cask = T.let(self.class.cask, T.nilable(String))
    @download = T.let(self.class.download, T.nilable(String))
    tags.each do |tag|
      next unless tag.is_a? Hash

      @cask ||= tag[:cask]
      @download ||= tag[:download]
    end
    @tags = T.let(tags, T::Array[T.untyped])
    @tags << :build if self.class.build
    inferred_name = infer_name
    @name = T.let(inferred_name, String)
  end

  sig { override.returns(T::Array[String]) }
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

    @satisfied_result = T.let(
      satisfy.yielder(env:, cc:, build_bottle:, bottle_arch:) do |p|
        instance_eval(&T.must(p))
      end,
      Object,
    )
    return false unless @satisfied_result

    true
  end

  # Overriding {#fatal?} is unsupported.
  # Pass a boolean to the fatal DSL method instead.
  sig { returns(T::Boolean) }
  def fatal?
    self.class.fatal || false
  end

  sig { returns(T.nilable(Pathname)) }
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
    instance_eval(&T.must(env_proc)) if env_proc

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

  sig { returns(T.nilable(BuildEnvironment)) }
  def env
    self.class.env
  end

  sig { returns(T.nilable(T.proc.void)) }
  def env_proc
    self.class.env_proc
  end

  sig { override.params(other: BasicObject).returns(T::Boolean) }
  def ==(other)
    case other
    when Requirement
      other.class == self.class && name == other.name && tags == other.tags
    else false
    end
  end
  alias eql? ==

  sig { override.returns(Integer) }
  def hash
    [self.class, name, tags].hash
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{tags.inspect}>"
  end

  sig { returns(String) }
  def display_s
    name.capitalize
  end

  sig { params(block: T.proc.params(arg0: Mktemp).void).void }
  def mktemp(&block)
    Mktemp.new(name).run(&block)
  end

  private

  sig { returns(String) }
  def infer_name
    klass = self.class.name
    klass = klass&.sub(/(Dependency|Requirement)$/, "")
                 &.sub(/^(\w+::)*/, "")
    return klass.downcase if klass.present?

    return @cask if @cask.present?

    ""
  end

  sig { params(cmd: String).returns(T.nilable(Pathname)) }
  def which(cmd)
    super(cmd, PATH.new(ORIGINAL_PATHS))
  end

  class << self
    include BuildEnvironment::DSL

    sig { override.params(child: T::Class[T.anything]).void }
    def inherited(child)
      super
      child.instance_eval do
        @cask = T.let(nil, T.nilable(String))
        @download = T.let(nil, T.nilable(String))
        @fatal = T.let(nil, T.nilable(T::Boolean))
        @satisfied = T.let(nil, T.nilable(Satisfier))
        @build = T.let(nil, T.nilable(T::Boolean))
        @env_proc = T.let(nil, T.nilable(T.proc.void))
      end
    end

    sig { returns(T.nilable(T.proc.void)) }
    attr_reader :env_proc

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :build

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

    sig {
      params(options: T.nilable(T.any(T::Boolean, T::Hash[Symbol, T.anything], Satisfier)),
             block:   T.nilable(T.proc.returns(T.anything))).returns(T.nilable(Satisfier))
    }
    def satisfy(options = nil, &block)
      return @satisfied if options.nil? && !block

      options = {} if options.nil?
      @satisfied = Satisfier.new(options, &block)
    end

    sig {
      override.params(settings: Symbol, block: T.nilable(T.proc.void)).returns(T.nilable(BuildEnvironment))
    }
    def env(*settings, &block)
      if block
        @env_proc = T.let(block, T.nilable(T.proc.void))
        nil
      else
        super
      end
    end
  end

  # Helper class for evaluating whether a requirement is satisfied.
  class Satisfier
    sig { params(options: T.nilable(T.any(T::Boolean, T::Hash[Symbol, T.anything], Satisfier)), block: T.nilable(T.proc.returns(T.anything))).void }
    def initialize(options, &block)
      case options
      when Hash
        @options = T.let({ build_env: true }, T.nilable(T::Hash[Symbol, T.anything]))
        T.must(@options).merge!(options)
      else
        @satisfied = T.let(options, T.anything)
      end
      @proc = T.let(block, T.nilable(T.proc.returns(T.anything)))
    end

    sig {
      params(
        env:          T.nilable(String),
        cc:           T.nilable(String),
        build_bottle: T::Boolean,
        bottle_arch:  T.nilable(String),
        block:        T.proc.params(arg0: T.nilable(T.proc.returns(T.anything))).returns(T.anything),
      ).returns(T.untyped)
    }
    def yielder(env: nil, cc: nil, build_bottle: false, bottle_arch: nil, &block)
      if instance_variable_defined?(:@satisfied)
        @satisfied = T.let(@satisfied, T.anything)
        @satisfied
      elsif (@options = T.let(@options, T.nilable(T::Hash[Symbol, T.anything]))) &&
            @options[:build_env]
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
    sig {
      params(
        dependent: T.any(Formula, CaskDependent, SoftwareSpec),
        cache_key: T.nilable(String),
        block:     T.nilable(T.proc.params(arg0: T.any(Formula, CaskDependent, SoftwareSpec),
                                           arg1: Requirement).returns(T.nilable(Symbol))),
      ).returns(Requirements)
    }
    def expand(dependent, cache_key: nil, &block)
      if cache_key.present?
        cache[cache_key] ||= {}
        return cache[cache_key][cache_id dependent].dup if cache[cache_key][cache_id dependent]
      end

      reqs = Requirements.new

      formulae = T.let(dependent.recursive_dependencies.map(&:to_formula),
                       T::Array[T.any(Formula, CaskDependent, SoftwareSpec)])
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

    sig {
      params(
        dependent: T.any(Formula, CaskDependent, SoftwareSpec),
        req:       Requirement,
        block:     T.nilable(T.proc.params(arg0: T.any(Formula, CaskDependent, SoftwareSpec),
                                           arg1: Requirement).returns(T.nilable(Symbol))),
      ).returns(T::Boolean)
    }
    def prune?(dependent, req, &block)
      if block
        yield(dependent, req) == Dependable::PRUNE
      elsif req.optional? || req.recommended?
        !T.cast(dependent, Formula).build.with?(req)
      else
        false
      end
    end

    private

    sig { params(dependent: T.untyped).returns(String) }
    def cache_id(dependent)
      "#{dependent.full_name}_#{dependent.class}"
    end
  end
end
