($aliases | split("\n") | map(select(length > 0) | split("|") |
  { key: .[0], value: .[1] }) | from_entries) as $aliases |
($names | split("\n") | map(select(length > 0) | { key: ., value: true }) | from_entries) as $names |
[inputs | { name: (input_filename | split("/")[-3]), tab: . }] |
if all(.[]; (.tab | type) == "object" and
             (.tab.installed_on_request == true or .tab.installed_on_request == false or
              .tab.installed_on_request == null) and
             (.tab.source.tap | type) == "string" and
             (if .tab.source.tap == "homebrew/core"
              then $names[$aliases[.name] // .name] == true
              else (.tab.source.tap | startswith("homebrew/") | not) end))
then map(select(.tab.source.tap == "homebrew/core") |
         .name = ($aliases[.name] // .name)) |
     unique_by(.name) | .[] | select(.tab.installed_on_request == true) | .name
else error("invalid installation receipt") end
