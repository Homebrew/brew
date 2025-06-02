# frozen_string_literal: true
module RubyVM::RJIT
  # Return a Hash for \RJIT statistics. \--rjit-stats makes more information available.
  def self.runtime_stats
    stats = {}

    # Insn exits
    INSNS.each_value do |insn|
      exits = C.rjit_insn_exits[insn.bin]
      if exits > 0
        stats[:"exit_#{insn.name}"] = exits
      end
    end

    # Runtime stats
    C.rb_rjit_runtime_counters.members.each do |member|
      stats[member] = C.rb_rjit_counters.public_send(member)
    end
    stats[:vm_insns_count] = C.rb_vm_insns_count

    # Other stats are calculated here
    stats[:side_exit_count] = stats.select { |name, _count| name.start_with?('exit_') }.sum(&:last)
    if stats[:vm_insns_count] > 0
      retired_in_rjit = stats[:rjit_insns_count] - stats[:side_exit_count]
      stats[:total_insns_count] = retired_in_rjit + stats[:vm_insns_count]
      stats[:ratio_in_rjit] = 100.0 * retired_in_rjit / stats[:total_insns_count]
    else
      stats.delete(:vm_insns_count)
    end

    stats
  end

  # :nodoc: all
  class << self
    private

    # --yjit-stats at_exit
    def print_stats
      stats = runtime_stats
      $stderr.puts("***RJIT: Printing RJIT statistics on exit***")

      print_counters(stats, prefix: 'send_', prompt: 'method call exit reasons')
      print_counters(stats, prefix: 'invokeblock_', prompt: 'invokeblock exit reasons')
      print_counters(stats, prefix: 'invokesuper_', prompt: 'invokesuper exit reasons')
      print_counters(stats, prefix: 'getblockpp_', prompt: 'getblockparamproxy exit reasons')
      print_counters(stats, prefix: 'getivar_', prompt: 'getinstancevariable exit reasons')
      print_counters(stats, prefix: 'setivar_', prompt: 'setinstancevariable exit reasons')
      print_counters(stats, prefix: 'optaref_', prompt: 'opt_aref exit reasons')
      print_counters(stats, prefix: 'optgetconst_', prompt: 'opt_getconstant_path exit reasons')
      print_counters(stats, prefix: 'expandarray_', prompt: 'expandarray exit reasons')

      $stderr.puts "compiled_block_count:  #{format_number(13, stats[:compiled_block_count])}"
      $stderr.puts "side_exit_count:       #{format_number(13, stats[:side_exit_count])}"
      $stderr.puts "total_insns_count:     #{format_number(13, stats[:total_insns_count])}" if stats.key?(:total_insns_count)
      $stderr.puts "vm_insns_count:        #{format_number(13, stats[:vm_insns_count])}" if stats.key?(:vm_insns_count)
      $stderr.puts "rjit_insns_count:      #{format_number(13, stats[:rjit_insns_count])}"
      $stderr.puts "ratio_in_rjit:         #{format('%12.1f', stats[:ratio_in_rjit])}%" if stats.key?(:ratio_in_rjit)

      print_exit_counts(stats)
    end

    def print_counters(stats, prefix:, prompt:)
      $stderr.puts("#{prompt}: ")
      counters = stats.filter { |key, _| key.start_with?(prefix) }
      counters.filter! { |_, value| value != 0 }
      counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }

      if counters.empty?
        $stderr.puts("    (all relevant counters are zero)")
        return
      end

      counters = counters.to_a
      counters.sort_by! { |(_, counter_value)| counter_value }
      longest_name_length = counters.max_by { |(name, _)| name.length }.first.length
      total = counters.sum { |(_, counter_value)| counter_value }

      counters.reverse_each do |(name, value)|
        percentage = value.fdiv(total) * 100
        $stderr.printf("    %*s %s (%4.1f%%)\n", longest_name_length, name, format_number(10, value), percentage)
      end
    end

    def print_exit_counts(stats, how_many: 20, padding: 2)
      exits = stats.filter_map { |name, count| [name.to_s.delete_prefix('exit_'), count] if name.start_with?('exit_') }.to_h
      return if exits.empty?

      top_exits = exits.sort_by { |_name, count| -count }.first(how_many).to_h
      total_exits = exits.values.sum
      $stderr.puts "Top-#{top_exits.size} most frequent exit ops (#{format("%.1f", 100.0 * top_exits.values.sum / total_exits)}% of exits):"

      name_width  = top_exits.map { |name, _count| name.length }.max + padding
      count_width = top_exits.map { |_name, count| format_number(10, count).length }.max + padding
      top_exits.each do |name, count|
        ratio = 100.0 * count / total_exits
        $stderr.puts "#{format("%#{name_width}s", name)}: #{format_number(count_width, count)} (#{format('%4.1f', ratio)}%)"
      end
    end

    # Format large numbers with comma separators for readability
    def format_number(pad, number)
      integer, decimal = number.to_s.split('.')
      d_groups = integer.chars.reverse.each_slice(3)
      with_commas = d_groups.map(&:join).join(',').reverse
      [with_commas, decimal].compact.join('.').rjust(pad, ' ')
    end

    # --yjit-trace-exits at_exit
    def dump_trace_exits
      filename = "#{Dir.pwd}/rjit_exit_locations.dump"
      File.binwrite(filename, Marshal.dump(exit_traces))
      $stderr.puts("RJIT exit locations dumped to:\n#{filename}")
    end

    # Convert rb_rjit_raw_samples and rb_rjit_line_samples into a StackProf format.
    def exit_traces
      results = C.rjit_exit_traces
      raw_samples = results[:raw].dup
      line_samples = results[:lines].dup
      frames = results[:frames].dup
      samples_count = 0

      # Loop through the instructions and set the frame hash with the data.
      # We use nonexistent.def for the file name, otherwise insns.def will be displayed
      # and that information isn't useful in this context.
      RubyVM::INSTRUCTION_NAMES.each_with_index do |name, frame_id|
        frame_hash = { samples: 0, total_samples: 0, edges: {}, name: name, file: "nonexistent.def", line: nil, lines: {} }
        results[:frames][frame_id] = frame_hash
        frames[frame_id] = frame_hash
      end

      # Loop through the raw_samples and build the hashes for StackProf.
      # The loop is based off an example in the StackProf documentation and therefore
      # this functionality can only work with that library.
      #
      # Raw Samples:
      # [ length, frame1, frame2, frameN, ..., instruction, count
      #
      # Line Samples
      # [ length, line_1, line_2, line_n, ..., dummy value, count
      i = 0
      while i < raw_samples.length
        stack_length = raw_samples[i] + 1
        i += 1 # consume the stack length

        prev_frame_id = nil
        stack_length.times do |idx|
          idx += i
          frame_id = raw_samples[idx]

          if prev_frame_id
            prev_frame = frames[prev_frame_id]
            prev_frame[:edges][frame_id] ||= 0
            prev_frame[:edges][frame_id] += 1
          end

          frame_info = frames[frame_id]
          frame_info[:total_samples] += 1

          frame_info[:lines][line_samples[idx]] ||= [0, 0]
          frame_info[:lines][line_samples[idx]][0] += 1

          prev_frame_id = frame_id
        end

        i += stack_length # consume the stack

        top_frame_id = prev_frame_id
        top_frame_line = 1

        sample_count = raw_samples[i]

        frames[top_frame_id][:samples] += sample_count
        frames[top_frame_id][:lines] ||= {}
        frames[top_frame_id][:lines][top_frame_line] ||= [0, 0]
        frames[top_frame_id][:lines][top_frame_line][1] += sample_count

        samples_count += sample_count
        i += 1
      end

      results[:samples] = samples_count
      # Set missed_samples and gc_samples to 0 as their values
      # don't matter to us in this context.
      results[:missed_samples] = 0
      results[:gc_samples] = 0
      results
    end
  end
end
