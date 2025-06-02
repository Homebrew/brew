class String # :nodoc:
  # Equivalent to CSV::parse_line(self, options)
  #
  #   "CSV,data".parse_csv
  #     #=> ["CSV", "data"]
  def parse_csv(**options)
    CSV.parse_line(self, **options)
  end
end
