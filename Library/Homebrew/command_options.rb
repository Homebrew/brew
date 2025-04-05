# typed: strict
# frozen_string_literal: true

module Homebrew
  class CommandOptions
    sig { returns(T::Boolean) }
    attr_reader :global

    sig { returns(T::Boolean) }
    attr_reader :verbose

    sig { returns(T::Boolean) }
    attr_reader :no_wait

    sig { returns(T::Boolean) }
    attr_reader :keep

    sig { returns(T::Boolean) }
    attr_reader :zap

    sig { returns(T::Boolean) }
    attr_reader :force

    sig { returns(T.nilable(String)) }
    attr_reader :file

    sig { returns(T.nilable(Float)) }
    attr_reader :max_wait

    sig { params(args: T.untyped).void }
    def initialize(args)
      @global = T.let(args.respond_to?(:global?) ? args.global? : false, T::Boolean)
      @file = T.let(args.respond_to?(:file) ? args.file : nil, T.nilable(String))
      @verbose = T.let(args.respond_to?(:verbose?) ? args.verbose? : false, T::Boolean)
      @no_wait = T.let(args.respond_to?(:no_wait?) ? args.no_wait? : false, T::Boolean)
      @max_wait = T.let(args.respond_to?(:max_wait) ? args.max_wait.to_f : nil, T.nilable(Float))
      @keep = T.let(args.respond_to?(:keep?) ? args.keep? : false, T::Boolean)
      @zap = T.let(args.respond_to?(:zap?) ? args.zap? : false, T::Boolean)
      @force = T.let(args.respond_to?(:force?) ? args.force? : false, T::Boolean)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        global:   @global,
        file:     @file,
        verbose:  @verbose,
        no_wait:  @no_wait,
        max_wait: @max_wait,
        keep:     @keep,
        zap:      @zap,
        force:    @force,
      }
    end
  end
end
