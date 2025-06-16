# typed: strict
# frozen_string_literal: true

module Language
  module Java
    def self.java_home(version = nil)
      openjdk = find_openjdk_formula(version)
      return unless openjdk

      openjdk.opt_libexec/"openjdk.jdk/Contents/Home"
    end
  end
end
