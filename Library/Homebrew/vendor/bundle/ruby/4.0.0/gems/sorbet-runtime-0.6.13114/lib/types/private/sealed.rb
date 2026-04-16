# frozen_string_literal: true
# typed: false

module T::Private::Sealed
  module NoInherit
    def inherited(child)
      super
      caller_loc = T::Private::CallerUtils.find_caller { |loc| loc.base_label != 'inherited' }
      T::Private::Sealed.validate_inheritance(caller_loc, self, child, 'inherited')
      @sorbet_sealed_module_all_subclasses << child
    end

    def sealed_subclasses
      @sorbet_sealed_module_all_subclasses_set ||= # rubocop:disable Naming/MemoizedInstanceVariableName
        begin
          require 'set'
          Set.new(@sorbet_sealed_module_all_subclasses).freeze
        end
    end
  end

  module NoIncludeExtend
    def included(child)
      super
      caller_loc = T::Private::CallerUtils.find_caller { |loc| loc.base_label != 'included' }
      T::Private::Sealed.validate_inheritance(caller_loc, self, child, 'included')
      @sorbet_sealed_module_all_subclasses << child
    end

    def extended(child)
      super
      caller_loc = T::Private::CallerUtils.find_caller { |loc| loc.base_label != 'extended' }
      T::Private::Sealed.validate_inheritance(caller_loc, self, child, 'extended')
      @sorbet_sealed_module_all_subclasses << child
    end

    def sealed_subclasses
      # this will freeze the set so that you can never get into a
      # state where you use the subclasses list and then something
      # else will add to it
      @sorbet_sealed_module_all_subclasses_set ||= # rubocop:disable Naming/MemoizedInstanceVariableName
        begin
          require 'set'
          Set.new(@sorbet_sealed_module_all_subclasses).freeze
        end
    end
  end

  def self.declare(mod, decl_file)
    if !mod.is_a?(Module)
      raise "#{mod} is not a class or module and cannot be declared `sealed!`"
    end
    if sealed_module?(mod)
      raise "#{mod} was already declared `sealed!` and cannot be re-declared `sealed!`"
    end
    if T::Private::Final.final_module?(mod)
      raise "#{mod} was already declared `final!` and cannot be declared `sealed!`"
    end
    mod.extend(mod.is_a?(Class) ? NoInherit : NoIncludeExtend)
    if !decl_file
      raise "Couldn't determine declaration file for sealed class."
    end
    mod.instance_variable_set(:@sorbet_sealed_module_decl_file, decl_file)
    mod.instance_variable_set(:@sorbet_sealed_module_all_subclasses, [])
  end

  def self.sealed_module?(mod)
    mod.instance_variable_defined?(:@sorbet_sealed_module_decl_file)
  end

  def self.validate_inheritance(caller_loc, parent, child, verb)
    this_file = caller_loc&.path
    decl_file = parent.instance_variable_get(:@sorbet_sealed_module_decl_file)

    if !this_file
      raise "Could not use backtrace to determine file for #{verb} child #{child}"
    end
    if !decl_file
      raise "#{parent} does not seem to be a sealed module (#{verb} by #{child})"
    end

    if !this_file.start_with?(decl_file)
      whitelist = T::Configuration.sealed_violation_whitelist
      if !whitelist.nil? && whitelist.any? { |pattern| this_file =~ pattern }
        return
      end

      raise "#{parent} was declared sealed and can only be #{verb} in #{decl_file}, not #{this_file}"
    end
  end
end
