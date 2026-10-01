# typed: strict
# frozen_string_literal: true

require "formula"
require "utils"
require "cask/caskroom"
require "cask/tab"

module Homebrew
  module Missing
    sig {
      params(formulae: T::Array[Formula], casks: T::Array[Cask::Cask], hide: T::Array[String], _block: T.nilable(
        T.proc.params(package_name: String, missing_dependencies: T::Array[String]).void,
      )).returns(T::Hash[String, T::Array[String]])
    }
    def self.deps(formulae, casks = [], hide = [], &_block)
      missing = {}
      formulae.each do |formula|
        missing_dependencies = formula.missing_dependencies(hide: hide).map(&:to_s)
        next if missing_dependencies.empty?

        yield formula.full_name, missing_dependencies if block_given?
        missing[formula.full_name] = missing_dependencies
      end

      casks.each do |cask|
        missing_dependencies = cask_deps(cask, hide)
        next if missing_dependencies.empty?

        yield cask.full_name, missing_dependencies if block_given?
        missing[cask.full_name] = missing_dependencies
      end
      missing
    end

    sig { params(cask: Cask::Cask, hide: T::Array[String]).returns(T::Array[String]) }
    def self.cask_deps(cask, hide)
      tab_deps = T.let(Cask::Tab.for_cask(cask).runtime_dependencies, T.untyped)
      return [] unless tab_deps.is_a?(Hash)

      tab_deps.keys.flat_map do |type|
        deps = tab_deps[type]
        next [] unless deps.is_a?(Array)

        deps.filter_map do |dep|
          next unless dep.is_a?(Hash)

          full_name = T.cast(dep["full_name"], T.nilable(String))
          next if full_name.blank?

          name = Utils.name_from_full_name(full_name)
          installed = case type.to_s
          when "cask"
            (Cask::Caskroom.path/name).directory?
          when "formula"
            (HOMEBREW_CELLAR/name).directory?
          else
            true
          end
          next if hide.exclude?(name) && installed

          full_name
        end
      end.sort
    end
    private_class_method :cask_deps
  end
end
