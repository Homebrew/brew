# typed: strict
# frozen_string_literal: true

module OS
  provider = third_party_homebrew
  issues_url = provider ? provider.issues_url : DEFAULT_ISSUES_URL
  ISSUES_URL = T.let(issues_url.freeze, T.nilable(String))
end
