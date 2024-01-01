# typed: true
# frozen_string_literal: true

require_relative "../../global"
require_relative "../../env_config"

File.open("#{__dir__}/../../env_config.rbi", "w") do |file|
  file.write(<<~RUBY)
    # typed: strict

    module Homebrew::EnvConfig
  RUBY

  dynamic_methods = {}
  Homebrew::EnvConfig::ENVS.each do |env, hash|
    next if Homebrew::EnvConfig::CUSTOM_IMPLEMENTATIONS.include?(env)

    name = Homebrew::EnvConfig.env_method_name(env, hash)
    dynamic_methods[name] = { default: hash[:default] }
  end

  methods = Homebrew::EnvConfig.methods(false).map(&:to_s).select { |method| dynamic_methods.key?(method) }.sort

  methods.each do |method|
    return_type = if method.end_with?("?")
      T::Boolean
    elsif (default = dynamic_methods[method][:default])
      default.class
    else
      T.nilable(String)
    end

    file.write(<<-RUBY)
  sig { returns(#{return_type}) }
  def self.#{method}; end
    RUBY

    file.write("\n") if method != methods.last
  end

  file.puts "end"
end
