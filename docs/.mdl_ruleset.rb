# typed: true
# frozen_string_literal: true

rule "HB034", "Bare unstyled URL used" do
  tags :links, :url
  aliases "no-bare-unstyled-urls"
  check do |doc|
    doc.matching_text_element_lines(%r{(?<=\s)https?://})
  end
end
