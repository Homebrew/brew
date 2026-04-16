# typed: strict
# frozen_string_literal: true

# Validates that:
# 1. Style/Documentation.Include in .rubocop.yml matches files containing @api public
# 2. FORMULA_COOKBOOK_METHODS includes every rubydoc-linked method in the Formula Cookbook
# 3. CASK_COOKBOOK_METHODS includes every @api public method in the cask source files
#
# Run via: brew ruby Library/Homebrew/github_actions_utils/public_api_check.rb

HELPER_PATH = T.let((HOMEBREW_LIBRARY_PATH/"rubocops/shared/api_annotation_helper.rb").freeze, Pathname)
HELPER_TEXT = T.let(HELPER_PATH.read.freeze, String)

failed = false

# --- 1. Style/Documentation.Include vs @api public files ---
doc_includes = YAML.safe_load_file(HOMEBREW_LIBRARY_PATH / ".rubocop.yml")
                   .dig("Style/Documentation", "Include")&.sort || []

api_files = []
HOMEBREW_LIBRARY_PATH.find do |path|
  Find.prune if path.basename.to_s.match?(/\A(sorbet|vendor|rubocops|test|github_actions_utils)\z/) && path.directory?
  next if !path.file? || path.extname != ".rb"

  api_files << path.relative_path_from(HOMEBREW_LIBRARY_PATH).to_s if path.read.include?("# @api public")
end
api_files.sort!

missing_from_docs = api_files - doc_includes
extra_in_docs     = doc_includes - api_files

if missing_from_docs.any? || extra_in_docs.any?
  warn "::error::Style/Documentation Include list is out of sync with @api public files."
  if missing_from_docs.any?
    warn "Files with @api public missing from Style/Documentation.Include:"
    missing_from_docs.each { |f| warn "  #{f}" }
  end
  if extra_in_docs.any?
    warn "Files in Style/Documentation.Include that no longer contain @api public:"
    extra_in_docs.each { |f| warn "  #{f}" }
  end
  warn "Update Library/Homebrew/.rubocop.yml accordingly."
  failed = true
end

# --- 2. FORMULA_COOKBOOK_METHODS vs cookbook rubydoc links ---
cookbook_methods = (HOMEBREW_REPOSITORY / "docs/Formula-Cookbook.md").read
                   .scan(%r{/rubydoc/\w+(?:/\w+)*\.html#(\w+[!?]?)-(class|instance)_method})
                   .to_set(&:first)
formula_block = HELPER_TEXT[/FORMULA_COOKBOOK_METHODS\s*=.*?\{(.*?)\.freeze/m, 1] || ""
formula_list  = formula_block.scan(/"(\w+[!?]?)"/).flatten.reject { |m| m.end_with?(".rb") }.to_set
missing_formula = (cookbook_methods - formula_list).sort

if missing_formula.any?
  warn "::error::Formula Cookbook references methods not in FORMULA_COOKBOOK_METHODS."
  warn "These methods have rubydoc links in docs/Formula-Cookbook.md but are"
  warn "missing from FORMULA_COOKBOOK_METHODS in #{HELPER_PATH.relative_path_from(HOMEBREW_LIBRARY_PATH)}:"
  missing_formula.each { |m| warn "  #{m}" }
  failed = true
end

# --- 3. CASK_COOKBOOK_METHODS vs @api public in cask source ---
cask_block = HELPER_TEXT[/CASK_COOKBOOK_METHODS\s*=.*?\{(.*?)\.freeze/m, 1] || ""
cask_list  = cask_block.scan(/"(\w+[!?]?)"/).flatten.reject { |m| m.end_with?(".rb") }.to_set
%w[cask/dsl.rb cask/cask.rb cask/dsl/version.rb].each do |src|
  source_methods = Set.new
  lines = (HOMEBREW_LIBRARY_PATH / src).readlines
  lines.each_with_index do |line, idx|
    next if line.strip != "# @api public"

    (1..5).each do |offset|
      target = lines[idx + offset]&.strip
      break if target.blank?

      m = target.match(/\A(?:def\s+(?:self\.)?|attr_reader\s+:|attr_accessor\s+:)(\w+[!?]?)/) ||
          target.match(/\Adelegate\s+(\w+[!?]?):/)
      if m
        source_methods.add(m[1])
        break
      end
    end
  end

  missing_cask = (source_methods - cask_list).sort
  next if missing_cask.empty?

  warn "::error::#{src} has @api public methods not in CASK_COOKBOOK_METHODS."
  warn "Add these to CASK_COOKBOOK_METHODS in #{HELPER_PATH.relative_path_from(HOMEBREW_LIBRARY_PATH)}:"
  missing_cask.each { |m| warn "  #{m}" }
  failed = true
end

exit 1 if failed
puts "All public API lists are in sync."
