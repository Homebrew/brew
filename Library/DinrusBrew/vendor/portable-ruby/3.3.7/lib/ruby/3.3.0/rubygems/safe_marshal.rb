# frozen_string_literal: true

require "stringio"

require_relative "safe_marshal/reader"
require_relative "safe_marshal/visitors/to_ruby"

module Gem
  ###
  # This module is used for safely loading Marshal specs from a gem.  The
  # `safe_load` method defined on this module is specifically designed for
  # loading Gem specifications.

  module SafeMarshal
    PERMITTED_CLASSES = %w[
      Date
      Time
      Rational

      Gem::Dependency
      Gem::NameTuple
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement

      YAML::Syck::DefaultKey
      YAML::PrivateType
    ].freeze
    private_constant :PERMITTED_CLASSES

    PERMITTED_SYMBOLS = %w[
      development
      runtime

      name
      number
      platform
      dependencies
    ].freeze
    private_constant :PERMITTED_SYMBOLS

    PERMITTED_IVARS = {
      "String" => %w[E encoding @taguri @debug_created_info],
      "Time" => %w[
        offset zone nano_num nano_den submicro
        @_zone @marshal_with_utc_coercion
      ],
      "Gem::Dependency" => %w[
        @name @requirement @prerelease @version_requirement @version_requirements @type
        @force_ruby_platform
      ],
      "Gem::NameTuple" => %w[@name @version @platform],
      "Gem::Platform" => %w[@os @cpu @version],
      "Psych::PrivateType" => %w[@value @type_id],
    }.freeze
    private_constant :PERMITTED_IVARS

    def self.safe_load(input)
      load(input, permitted_classes: PERMITTED_CLASSES, permitted_symbols: PERMITTED_SYMBOLS, permitted_ivars: PERMITTED_IVARS)
    end

    def self.load(input, permitted_classes: [::Symbol], permitted_symbols: [], permitted_ivars: {})
      root = Reader.new(StringIO.new(input, "r").binmode).read!

      Visitors::ToRuby.new(
        permitted_classes: permitted_classes,
        permitted_symbols: permitted_symbols,
        permitted_ivars: permitted_ivars,
      ).visit(root)
    end
  end
end
