# frozen_string_literal: true

module Bootsnap
  module LoadPathCache
    module ChangeObserver
      module ArrayMixin
        # For each method that adds items to one end or another of the array
        # (<<, push, unshift, concat), override that method to also notify the
        # observer of the change.
        def <<(entry)
          @lpc_observer.push_paths(self, entry.to_s)
          super
        end

        def push(*entries)
          @lpc_observer.push_paths(self, *entries.map(&:to_s))
          super
        end
        alias_method :append, :push

        def unshift(*entries)
          @lpc_observer.unshift_paths(self, *entries.map(&:to_s))
          super
        end
        alias_method :prepend, :unshift

        def concat(entries)
          @lpc_observer.push_paths(self, *entries.map(&:to_s))
          super
        end

        # uniq! keeps the first occurrence of each path, otherwise preserving
        # order, preserving the effective load path
        def uniq!(*args)
          ret = super
          @lpc_observer.reinitialize if block_given? || !args.empty?
          ret
        end

        # For each method that modifies the array more aggressively, override
        # the method to also have the observer completely reconstruct its state
        # after the modification. Many of these could be made to modify the
        # internal state of the LoadPathCache::Cache more efficiently, but the
        # accounting cost would be greater than the hit from these, since we
        # actively discourage calling them.
        %i(
          []= clear collect! compact! delete delete_at delete_if fill flatten!
          insert keep_if map! pop reject! replace reverse! rotate! select!
          shift shuffle! slice! sort! sort_by!
        ).each do |method_name|
          define_method(method_name) do |*args, &block|
            ret = super(*args, &block)
            @lpc_observer.reinitialize
            ret
          end
        end

        def dup
          [] + self
        end

        alias_method :clone, :dup
      end

      def self.register(arr, observer)
        return if arr.frozen? # can't register observer, but no need to.

        arr.instance_variable_set(:@lpc_observer, observer)
        ArrayMixin.instance_methods.each do |method_name|
          arr.singleton_class.send(:define_method, method_name, ArrayMixin.instance_method(method_name))
        end
      end

      def self.unregister(arr)
        return unless arr.instance_variable_defined?(:@lpc_observer) && arr.instance_variable_get(:@lpc_observer)

        ArrayMixin.instance_methods.each do |method_name|
          arr.singleton_class.send(:remove_method, method_name)
        end
        arr.instance_variable_set(:@lpc_observer, nil)
      end
    end
  end
end
