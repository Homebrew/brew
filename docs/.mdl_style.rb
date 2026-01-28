# typed: true
# frozen_string_literal: true

all
rule "MD007", indent: 2 # Unordered list indentation
rule "MD026", punctuation: ",;:" # Trailing punctuation in header
exclude_rule "MD013" # Line length
exclude_rule "MD029" # Ordered list item prefix
exclude_rule "MD033" # Inline HTML
exclude_rule "MD034" # Bare URL used (replaced by HB034)
exclude_rule "MD046" # Code block style
