# frozen_string_literal: true

RBS.print_warning {
  "RBS::Parser::SyntaxError is deprecated and will be deleted in RBS 2.0."
}
RBS::Parser::SyntaxError = RBS::ParsingError
