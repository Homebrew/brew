# frozen_string_literal: true

require "mutex_m"
require "pathname"

module RequireHooks
  module KernelPatch
    class << self
      def load(path)
        ctx = RequireHooks.context_for(path)

        ctx.run_around_load_callbacks(path) do
          next load_without_require_hooks(path) unless ctx.source_transform? || ctx.hijack?

          new_contents = ctx.perform_source_transform(path)
          hijacked = ctx.try_hijack_load(path, new_contents)

          return try_evaluate(path, hijacked) if hijacked

          if new_contents
            evaluate(new_contents, path)
            true
          else
            load_without_require_hooks(path)
          end
        end
      end

      private

      def try_evaluate(path, bytecode)
        if defined?(::RubyVM::InstructionSequence) && bytecode.is_a?(::RubyVM::InstructionSequence)
          bytecode.eval
        else
          raise TypeError, "Unknown bytecode format for #{path}: #{bytecode.inspect}"
        end

        true
      end

      if defined?(JRUBY_VERSION) || defined?(TruffleRuby)
        def evaluate(code, filepath)
          new_toplevel.eval(code, filepath)
        end

        def new_toplevel
          # Create new "toplevel" binding to avoid lexical scope re-use
          # (aka "leaking refinements")
          eval "proc{binding}.call", TOPLEVEL_BINDING, __FILE__, __LINE__
        end
      else
        def evaluate(code, filepath)
          # This is workaround to solve the "leaking refinements" problem in MRI
          RubyVM::InstructionSequence.compile(code, filepath).tap do |iseq|
            iseq.eval
          end
        end
      end
    end

    module Features
      class Locker
        class PathLock
          def initialize
            @mu = Mutex.new
            @resolved = false
          end

          def owned?
            @mu.owned?
          end

          def locked?
            @mu.locked?
          end

          def lock!
            @mu.lock
          end

          def unlock!
            @mu.unlock
          end

          def resolve!
            @resolved = true
          end

          def resolved?
            @resolved
          end
        end

        attr_reader :features, :mu

        def initialize
          @mu = Mutex.new
          @features = {}
        end

        def lock_feature(fname)
          lock = mu.synchronize do
            features[fname] ||= PathLock.new
          end

          # Can this even happen?
          return yield(true) if lock.resolved?

          # Recursive require
          if lock.owned? && lock.locked?
            warn "loading in progress, circular require considered harmful: #{fname}" if RequireHooks.print_warnings
            return yield(true)
          end

          lock.lock!
          begin
            yield(lock.resolved?).tap do
              lock.resolve!
            end
          ensure
            lock.unlock!

            mu.synchronize do
              features.delete(fname)
            end
          end
        end

        def locked_feature?(fname)
          mu.synchronize { features.key?(fname) }
        end
      end

      LOCK = Locker.new

      class << self
        def feature_path(path, implitic_ext: true)
          path = resolve_feature_path(path, implitic_ext: implitic_ext)
          return if path.nil?
          return if File.extname(path) != ".rb" && implitic_ext
          path
        end

        # Based on https://github.com/ruby/ruby/blob/b588fd552390c55809719100d803c36bc7430f2f/load.c#L403-L415
        def feature_loaded?(feature)
          return true if $LOADED_FEATURES.include?(feature) && !LOCK.locked_feature?(feature)

          feature = Pathname.new(feature).cleanpath.to_s
          efeature = File.expand_path(feature)

          # Check absoulute and relative paths
          return true if $LOADED_FEATURES.include?(efeature) && !LOCK.locked_feature?(efeature)

          candidates = []

          $LOADED_FEATURES.each do |lf|
            candidates << lf if lf.end_with?("/#{feature}")
          end

          return false if candidates.empty?

          $LOAD_PATH.each do |lp|
            lp_feature = File.join(lp, feature)
            return true if candidates.include?(lp_feature) && !LOCK.locked_feature?(lp_feature)
          end

          false
        end

        private

        def lookup_feature_path(path, implitic_ext: true)
          path = "#{path}.rb" if File.extname(path).empty? && implitic_ext

          # Resolve relative paths only against current directory
          if path.match?(/^\.\.?\//)
            path = File.expand_path(path)
            return path if File.file?(path)
            return nil
          end

          if Pathname.new(path).absolute?
            path = File.expand_path(path)
            return File.file?(path) ? path : nil
          end

          # not a relative, not an absolute path — bare path; try looking relative to current dir,
          # if it's in the $LOAD_PATH
          if $LOAD_PATH.include?(Dir.pwd) && File.file?(path)
            return File.expand_path(path)
          end

          $LOAD_PATH.find do |lp|
            lpath = File.join(lp, path)
            return File.expand_path(lpath) if File.file?(lpath)
          end
        end

        if $LOAD_PATH.respond_to?(:resolve_feature_path)
          def resolve_feature_path(feature, implitic_ext: true)
            if implitic_ext
              path = $LOAD_PATH.resolve_feature_path(feature)
              path.last if path # rubocop:disable Style/SafeNavigation
            else
              lookup_feature_path(feature, implitic_ext: implitic_ext)
            end
          rescue LoadError
          end
        else
          def resolve_feature_path(feature, implitic_ext: true)
            lookup_feature_path(feature, implitic_ext: implitic_ext)
          end
        end
      end
    end
  end
end

# Patch Kernel to hijack require/require_relative/load
module Kernel
  module_function

  alias_method :require_without_require_hooks, :require
  # See https://github.com/ruby/ruby/blob/d814722fb8299c4baace3e76447a55a3d5478e3a/load.c#L1181
  def require(path)
    path = path.to_path if path.respond_to?(:to_path)
    raise TypeError unless path.respond_to?(:to_str)

    path = path.to_str

    raise TypeError unless path.is_a?(::String)

    realpath = nil
    feature = path

    # if extname == ".rb" => lookup feature -> resolve feature -> load
    # if extname != ".rb" => append ".rb" - lookup feature -> resolve feature -> lookup orig (no ext) -> resolve orig (no ext) -> load
    if File.extname(path) != ".rb"
      realpath = RequireHooks::KernelPatch::Features.feature_path(path + ".rb")

      if realpath
        feature = path + ".rb"
      end
    end

    realpath ||= RequireHooks::KernelPatch::Features.feature_path(path)

    return require_without_require_hooks(path) unless realpath

    ctx = RequireHooks.context_for(realpath)

    return require_without_require_hooks(path) if ctx.empty?

    return false if RequireHooks::KernelPatch::Features.feature_loaded?(feature)

    RequireHooks::KernelPatch::Features::LOCK.lock_feature(feature) do |loaded|
      return false if loaded

      $LOADED_FEATURES << realpath
      RequireHooks::KernelPatch.load(realpath)
      true
    end
  rescue LoadError => e
    $LOADED_FEATURES.delete(realpath) if realpath
    warn "RequireHooks failed to require '#{path}': #{e.message}" if RequireHooks.print_warnings
    require_without_require_hooks(path)
  rescue Errno::ENOENT, Errno::EACCES
    raise LoadError, "cannot load such file -- #{path}"
  rescue
    $LOADED_FEATURES.delete(realpath) if realpath
    raise
  end

  alias_method :require_relative_without_require_hooks, :require_relative
  def require_relative(path)
    path = path.to_path if path.respond_to?(:to_path)
    raise TypeError unless path.respond_to?(:to_str)
    path = path.to_str

    raise TypeError unless path.is_a?(::String)

    return require(path) if Pathname.new(path).absolute?

    loc = caller_locations(1..1).first
    from = loc.absolute_path || loc.path || File.join(Dir.pwd, "main")
    realpath = File.absolute_path(
      File.join(
        File.dirname(File.absolute_path(from)),
        path
      )
    )

    require(realpath)
  end

  alias_method :load_without_require_hooks, :load
  def load(path, wrap = false)
    if wrap
      warn "RequireHooks does not support `load(smth, wrap: ...)`. Falling back to original `Kernel#load`" if RequireHooks.print_warnings
      return load_without_require_hooks(path, wrap)
    end

    path = path.to_path if path.respond_to?(:to_path)
    raise TypeError unless path.respond_to?(:to_str)

    path = path.to_str

    raise TypeError unless path.is_a?(::String)

    realpath =
      if path =~ /^\.\.?\//
        path
      else
        RequireHooks::KernelPatch::Features.feature_path(path, implitic_ext: false)
      end

    return load_without_require_hooks(path, wrap) unless realpath

    RequireHooks::KernelPatch.load(realpath)
  rescue Errno::ENOENT, Errno::EACCES
    raise LoadError, "cannot load such file -- #{path}"
  rescue LoadError => e
    warn "RuquireHooks failed to load '#{path}': #{e.message}" if RequireHooks.print_warnings
    load_without_require_hooks(path)
  end
end
