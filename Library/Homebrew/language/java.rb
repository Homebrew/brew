# typed: strict
# frozen_string_literal: true

module Language
  # Helper functions for Java formulae.
  #
  # @api public
  module Java
    sig { params(version: T.nilable(String)).returns(T.nilable(Formula)) }
    def self.find_openjdk_formula(version = nil)
      can_be_newer = version&.end_with?("+")
      version = version.to_i

      openjdk = Formula["openjdk"]
      [openjdk, *openjdk.versioned_formulae].find do |f|
        next false unless f.any_version_installed?

        unless version.zero?
          major = T.must(f.any_installed_version).major
          next false if major < version
          next false if major > version && !can_be_newer
        end

        true
      end
    rescue FormulaUnavailableError
      nil
    end
    private_class_method :find_openjdk_formula

    # Returns the directory of the newest matching OpenJDK installation or
    # `nil` if none is available. When used in a {Formula}, there should be
    # a dependency and corresponding `version` for reproducible output.
    #
    # @api public
    # @param version OpenJDK version constraint which can be specific
    #   (e.g. `"21"`) or a lower-bounded range (e.g. `"21+"`)
    sig { params(version: T.nilable(String)).returns(T.nilable(Pathname)) }
    def self.java_home(version = nil)
      find_openjdk_formula(version)&.opt_libexec
    end

    sig { params(version: T.nilable(String)).returns(String) }
    def self.java_home_shell(version = nil)
      java_home(version).to_s
    end
    private_class_method :java_home_shell

    # Returns a `JAVA_HOME` environment variable to use a specific OpenJDK.
    # Usually combined with either {Pathname#write_env_script} or
    # {Pathname#env_script_all_files}.
    #
    # ### Example
    #
    # Use `openjdk@21` for all commands:
    #
    # ```ruby
    # bin.env_script_all_files libexec/"bin", Language::Java.java_home_env("21")
    # ```
    #
    # @api public
    sig { params(version: T.nilable(String)).returns({ JAVA_HOME: String }) }
    def self.java_home_env(version = nil)
      { JAVA_HOME: java_home_shell(version) }
    end

    # Returns a `JAVA_HOME` environment variable to use a default OpenJDK.
    # Unlike {.java_home_env} the OpenJDK can be overridden at runtime.
    #
    # ### Example
    #
    # Use latest `openjdk` as default:
    #
    # ```ruby
    # bin.env_script_all_files libexec/"bin", Language::Java.overridable_java_home_env
    # ```
    #
    # @api public
    sig { params(version: T.nilable(String)).returns({ JAVA_HOME: String }) }
    def self.overridable_java_home_env(version = nil)
      { JAVA_HOME: "${JAVA_HOME:-#{java_home_shell(version)}}" }
    end
  end
end

require "extend/os/language/java"
