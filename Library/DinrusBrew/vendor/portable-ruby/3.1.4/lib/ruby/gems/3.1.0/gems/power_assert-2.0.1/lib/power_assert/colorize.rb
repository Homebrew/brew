require 'power_assert/configuration'

PowerAssert.configure do |c|
  c.lazy_inspection = true
  c.colorize_message = true
  c.inspector = :pp
end
