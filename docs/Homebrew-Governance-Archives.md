---
last_review_date: "1970-01-01"
---

# Homebrew Governance Archives

{% assign governance_pages = site.pages | where: "category", "governance-archives" %}
{% assign marker = "-" %}

{% for item in governance_pages -%}
{{ marker }} [{{ item.title }}]({{ item.url }})
{% endfor %}
