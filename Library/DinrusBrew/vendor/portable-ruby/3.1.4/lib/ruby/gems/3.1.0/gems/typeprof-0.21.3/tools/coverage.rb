require "coverage"
require "coverage/helpers"

cov = Coverage::Helpers.load("coverage.dump")
cov.delete("<compiled>")
cov2 = {}
cov.each do |path, data|
  path = path.sub(/^exe\/..\//, "")
  data2 = Coverage.line_stub(path)
  data.each_with_index {|v, i| data2[i] = v if v }
  cov2[path] = data2
end
File.write("coverage.info", Coverage::Helpers.to_lcov_info(cov2))
system("genhtml", "-o", "coverage", "coverage.info")
