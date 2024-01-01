# typed: true
# frozen_string_literal: true

require_relative "../../global"
require_relative "../../env_config"
require_relative "../../utils/tty"

File.open("#{File.dirname(__FILE__)}/../../utils/tty.rbi", "w") do |file|
  file.write(<<~RUBY)
    # typed: strict

    module Tty
  RUBY

  dynamic_methods = Tty::COLOR_CODES.keys + Tty::STYLE_CODES.keys + Tty::SPECIAL_CODES.keys
  methods = Tty.methods(false).sort.select { |method| dynamic_methods.include?(method) }

  methods.each do |method|
    return_type = (method.to_s.end_with?("?") ? T::Boolean : String)
    signature = "sig { returns(#{return_type}) }"

    file.write(<<-RUBY)
  #{signature}
  def self.#{method}; end
    RUBY

    file.write("\n") if methods.last != method
  end

  file.write("end\n")
end
