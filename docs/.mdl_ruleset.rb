# typed: true
# frozen_string_literal: true

rule "HB034", "Bare unstyled URL used" do
  tags :links, :url
  aliases "no-bare-unstyled-urls"
  check do |doc|
    doc.matching_text_element_lines(%r{(?<=\s)https?://})
  end
end
rule "HB100", "Full URL for internal link used" do
  tags :links, :url
  aliases "no-full-urls-for-internal-links"
  check do |doc|
    doc.matching_lines(%r{\]\(https://docs.brew.sh/.+?\)})
  end
end
rule "HB101", "File extension missing from internal link" do
  tags :links, :url
  aliases "file-extension-required-for-internal-links"
  check do |doc|
    doc.matching_lines(/\]\((?!#|\w+:)(?>[^#.)]+)(?!\.\w+)/)
  end
end
