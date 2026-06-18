# frozen_string_literal: true

require "yaml"

AI_MENTION = /\b(?:AI|LLM)\b/i
CHECKBOX_MARKER = /\A- \[[ xX]\] /
HTML_COMMENT_LINE = /\A<!--.*-->\z/
ISSUE_FORM_HEADING_MARKER = "### "
MARKDOWN_HEADING = /\A#+ /
MARKDOWN_HORIZONTAL_LINE = /\A-+\z/
NORMALISED_CHECKBOX_MARKER = "- [ ] "
REQUIRED_TEMPLATE_PERCENTAGE = 75
PERCENTAGE_SCALE = 100

lines = lambda do |path|
  File.read(path, mode: "rb")
      .encode("UTF-8", invalid: :replace, undef: :replace)
      .lines(chomp: true)
end

normalised_lines = lambda do |path|
  lines.call(path).each_with_object([]) do |line, normalised_lines|
    line = line.strip.sub(CHECKBOX_MARKER, NORMALISED_CHECKBOX_MARKER)
    next if line.empty?
    next if line.match?(MARKDOWN_HORIZONTAL_LINE)
    next if line.match?(HTML_COMMENT_LINE)

    normalised_lines << line
  end.uniq
end

case ARGV.fetch(0)
when "pull-request"
  # Pass when the body keeps at least REQUIRED_TEMPLATE_PERCENTAGE of the template's
  # headings and checkboxes combined (ticked or not) and still discloses AI usage:
  # either the template's AI disclosure checkbox (whose label mentions AI) or any
  # mention of AI/LLM in the text. This blocks bodies that strip out the template
  # (e.g. AI-generated pull requests) without caring whether boxes are ticked.
  body_lines = lines.call(ARGV.fetch(1))
  normalised_body = normalised_lines.call(ARGV.fetch(1))
  template_items = normalised_lines.call(ARGV.fetch(2)).select do |line|
    line.start_with?(NORMALISED_CHECKBOX_MARKER) || line.match?(MARKDOWN_HEADING)
  end
  present_count = template_items.count { |item| normalised_body.include?(item) }
  preserves_template = present_count * PERCENTAGE_SCALE >= template_items.count * REQUIRED_TEMPLATE_PERCENTAGE
  discloses_ai = body_lines.any? { |line| line.match?(AI_MENTION) }

  puts preserves_template && discloses_ai
when "issue"
  # Pass when the body keeps at least REQUIRED_TEMPLATE_PERCENTAGE of some template's
  # headings and checkboxes combined (ticked or not). Counting headings as well as
  # checkboxes lets the feature template (a single checkbox) be told apart from a
  # stripped body. The missing items from the closest template are reported on stderr.
  body_lines = lines.call(ARGV.fetch(1))

  templates = Dir.glob("#{ARGV.fetch(2)}/*.{yml,yaml}").filter_map do |template_path|
    fields = YAML.safe_load_file(template_path).fetch("body", [])
    headings = fields.filter_map { |field| field.dig("attributes", "label") if field["type"] != "markdown" }
    checkboxes = fields.flat_map do |field|
      next [] if field["type"] != "checkboxes"

      field.fetch("attributes", {}).fetch("options", []).map { |option| option.fetch("label") }
    end
    items = headings.map { |label| [:heading, label] } + checkboxes.map { |label| [:checkbox, label] }
    next if items.empty?

    missing = items.reject { |_kind, label| body_lines.any? { |line| line.include?(label) } }
    present_count = items.length - missing.length
    { total: items.length, present_count: present_count, missing: missing }
  end

  preserves_template = templates.any? do |template|
    template[:present_count] * PERCENTAGE_SCALE >= template[:total] * REQUIRED_TEMPLATE_PERCENTAGE
  end

  if preserves_template
    puts true
  else
    puts false
    closest_missing = templates.min_by { |template| template[:missing].length }&.fetch(:missing)
    closest_missing&.each do |kind, label|
      warn((kind == :checkbox) ? "- [ ] #{label}" : "- `#{ISSUE_FORM_HEADING_MARKER}#{label}` section")
    end
  end
else
  warn "Usage: check_template.rb pull-request BODY TEMPLATE"
  warn "       check_template.rb issue BODY TEMPLATE_DIRECTORY"
  exit 1
end
