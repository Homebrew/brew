# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "../rubygems"

# forward-declare

module Gem::Security # :nodoc:
  class Policy # :nodoc:
  end
end

##
# Mixin methods for security option for Gem::Commands

module Gem::SecurityOption
  def add_security_option
    Gem::OptionParser.accept Gem::Security::Policy do |value|
      require_relative "security"

      raise Gem::OptionParser::InvalidArgument, "OpenSSL not installed" unless
        defined?(Gem::Security::HighSecurity)

      policy = Gem::Security::Policies[value]
      unless policy
        valid = Gem::Security::Policies.keys.sort
        raise Gem::OptionParser::InvalidArgument, "#{value} (#{valid.join ", "} are valid)"
      end
      policy
    end

    add_option(:"Install/Update", "-P", "--trust-policy POLICY",
               Gem::Security::Policy,
               "Specify gem trust policy") do |value, options|
      options[:security_policy] = value
    end
  end
end
