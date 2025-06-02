require "pp"

unless ARGV[0]
  puts "usage: #$0 /path/to/ruby/trunk/insns.def"
  exit
end

r = %r(
  ^DEFINE_INSN\n
  (?<name>\w+)\n
  \((?<operands>.*)\)\n
  \((?<inputs>.*)\)\n
  \((?<outputs>.*)\)\n
  (?://(?<inc>.*)\n)?
)x

INSN_TABLE = {}
Insn = Struct.new(:operands, :inputs, :outputs)
File.read(ARGV[0]).scan(r) do
  name, operands, _inputs, _outputs, _inc =
    $~[:name], $~[:operands], $~[:inputs], $~[:outputs], $~[:inc]
  next if name.start_with?("opt_")
  next if name == "bitblt" || name == "answer"
  operands = operands.split(",").map {|s| s.strip }.map do |s|
    s.split(" ").map {|s| s.strip }[0]
  end
  INSN_TABLE[name.to_sym] = operands
end
target = File.join(__dir__, "../lib/typeprof/insns-def.rb")
File.write(target, "TypeProf::INSN_TABLE = " + INSN_TABLE.pretty_inspect)
