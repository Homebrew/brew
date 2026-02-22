# typed: strict
# frozen_string_literal: true

require "bundle/checker"

module Homebrew
  module Bundle
    module Checker
      class UvChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :uv
        PACKAGE_TYPE_NAME = "uv Tool"

        sig {
          params(entries: T::Array[Bundle::Dsl::Entry]).returns(T::Array[T::Hash[Symbol, T.untyped]])
        }
        def format_checkable(entries)
          checkable_entries(entries).map do |entry|
            { name: entry.name, options: entry.options || {} }
          end
        end

        sig { params(package: T::Hash[Symbol, T.untyped], no_upgrade: T::Boolean).returns(String) }
        def failure_reason(package, no_upgrade:)
          name = T.cast(package[:name], String)
          "#{PACKAGE_TYPE_NAME} #{name} needs to be installed."
        end

        sig {
          params(package: T::Hash[Symbol, T.untyped], no_upgrade: T::Boolean).returns(T::Boolean)
        }
        def installed_and_up_to_date?(package, no_upgrade: false)
          require "bundle/uv_installer"

          options = T.cast(package[:options], T::Hash[Symbol, T.untyped])
          Homebrew::Bundle::UvInstaller.package_installed?(
            T.cast(package[:name], String),
            specifier: T.cast(options[:specifier], T.nilable(String)),
            with:      T.cast(options[:with] || [], T::Array[String]),
          )
        end
      end
    end
  end
end
