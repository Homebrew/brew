# frozen_string_literal: false
# :stopdoc:
module IRB
  class Locale
    @@legacy_encoding_alias_map = {
      'ujis' => Encoding::EUC_JP,
      'euc' => Encoding::EUC_JP
    }.freeze
  end
end
# :startdoc:
