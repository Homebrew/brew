# typed: false

module RuboCop::RSpec::ExpectOffense
  def format_offense(source, **replacements); end
  def expect_offense(source, file = nil, severity: nil, chomp: false, **replacements); end
  def expect_correction(correction, loop: true, source: nil); end
  def expect_no_corrections; end
  def expect_no_offenses(source, file = nil); end
  def parse_annotations(source, raise_error: true, **replacements); end
  def parse_processed_source(source, file = nil); end
  def set_formatter_options; end
end
