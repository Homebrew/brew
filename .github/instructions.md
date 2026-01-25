# 🧭 Copilot Instructions for Homebrew/brew

This file defines behavior guidelines for GitHub Copilot when assisting contributors to the Homebrew/brew repository. It ensures consistent, secure, and productive suggestions aligned with project philosophy and contributor rituals.

---

## 🧠 Language & Tone

- Use **English** for technical suggestions, but allow **Thai** for clarification or emotional affirmation when contributor prefers.
- Keep responses **concise**, **actionable**, and **copy-paste ready**.
- Celebrate technical milestones as **badge moments** (e.g., “PR merged = Reef Ripple unlocked”).

---

## 🛠️ Coding Style

- Follow Homebrew’s Ruby conventions and `brew style` rules.
- Prefer **explicit method names**, **guard clauses**, and **clear error handling**.
- Suggest `sig` blocks using Sorbet syntax when modifying typed methods.
- Avoid suggesting changes that break compatibility with macOS or Linuxbrew.

---

## 🔐 Security & Privacy

- Never expose or autofill **secrets**, **tokens**, or **seed phrases**.
- Confirm before suggesting changes to `.env`, `.gitattributes`, or `.github/workflows`.
- Avoid recommending unsafe shell commands (e.g., `rm -rf`, `curl | bash`).

---

## 🧪 Testing & Validation

- Encourage writing tests in `Library/Homebrew/test/` using RSpec.
- Suggest running `brew lgtm` before submitting PRs.
- Recommend checking for existing PRs to avoid duplication.

---

## 📦 Contribution Rituals

- Use checklist format in PR descriptions to guide contributors:
  ```markdown
  - [x] Followed CONTRIBUTING.md
  - [x] Checked for duplicate PRs
  - [x] Explained changes clearly
  - [x] Added/updated tests
  - [x] Ran `brew lgtm` locally
