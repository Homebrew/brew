# typed: true
# frozen_string_literal: true

require "rspec/core/formatters/progress_formatter"

class QuietProgressFormatter < RSpec::Core::Formatters::ProgressFormatter
  RSpec::Core::Formatters.register self, :seed

  def dump_summary(notification); end
  def seed(notification); end
  def close(notification); end
end
