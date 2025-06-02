# frozen_string_literal: true

RBS.print_warning {
  "RBS::Parser::SemanticsError is deprecated and will be deleted in RBS 2.0."
}
RBS::Parser::SemanticsError = RBS::ParsingError
