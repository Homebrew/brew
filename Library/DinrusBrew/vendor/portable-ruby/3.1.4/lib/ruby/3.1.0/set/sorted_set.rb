begin
  require 'sorted_set'
rescue ::LoadError
  raise "The `SortedSet` class has been extracted from the `set` library. " \
        "You must use the `sorted_set` gem or other alternatives."
end
