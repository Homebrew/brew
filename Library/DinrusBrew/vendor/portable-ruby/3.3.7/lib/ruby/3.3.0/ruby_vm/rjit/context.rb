module RubyVM::RJIT
  # Maximum number of temp value types we keep track of
  MAX_TEMP_TYPES = 8
  # Maximum number of local variable types we keep track of
  MAX_LOCAL_TYPES = 8

  # Operand to a YARV bytecode instruction
  SelfOpnd = :SelfOpnd # The value is self
  StackOpnd = Data.define(:index) # Temporary stack operand with stack index

  # Potential mapping of a value on the temporary stack to self,
  # a local variable, or constant so that we can track its type
  MapToStack = :MapToStack # Normal stack value
  MapToSelf  = :MapToSelf  # Temp maps to the self operand
  MapToLocal = Data.define(:local_index) # Temp maps to a local variable with index

  class Context < Struct.new(
    :stack_size,   # @param [Integer] The number of values on the stack
    :sp_offset,    # @param [Integer] JIT sp offset relative to the interpreter's sp
    :chain_depth,  # @param [Integer] jit_chain_guard depth
    :local_types,  # @param [Array<RubyVM::RJIT::Type>] Local variable types we keep track of
    :temp_types,   # @param [Array<RubyVM::RJIT::Type>] Temporary variable types we keep track of
    :self_type,    # @param [RubyVM::RJIT::Type] Type we track for self
    :temp_mapping, # @param [Array<Symbol>] Mapping of temp stack entries to types we track
  )
    def initialize(
      stack_size:   0,
      sp_offset:    0,
      chain_depth:  0,
      local_types:  [Type::Unknown] * MAX_LOCAL_TYPES,
      temp_types:   [Type::Unknown] * MAX_TEMP_TYPES,
      self_type:    Type::Unknown,
      temp_mapping: [MapToStack] * MAX_TEMP_TYPES
    ) = super

    # Deep dup by default for safety
    def dup
      ctx = super
      ctx.local_types = ctx.local_types.dup
      ctx.temp_types = ctx.temp_types.dup
      ctx.temp_mapping = ctx.temp_mapping.dup
      ctx
    end

    # Create a new Context instance with a given stack_size and sp_offset adjusted
    # accordingly. This is useful when you want to virtually rewind a stack_size for
    # generating a side exit while considering past sp_offset changes on gen_save_sp.
    def with_stack_size(stack_size)
      ctx = self.dup
      ctx.sp_offset -= ctx.stack_size - stack_size
      ctx.stack_size = stack_size
      ctx
    end

    def stack_opnd(depth_from_top)
      [SP, C.VALUE.size * (self.sp_offset - 1 - depth_from_top)]
    end

    def sp_opnd(offset_bytes = 0)
      [SP, (C.VALUE.size * self.sp_offset) + offset_bytes]
    end

    # Push one new value on the temp stack with an explicit mapping
    # Return a pointer to the new stack top
    def stack_push_mapping(mapping_temp_type)
      stack_size = self.stack_size

      # Keep track of the type and mapping of the value
      if stack_size < MAX_TEMP_TYPES
        mapping, temp_type = mapping_temp_type
        self.temp_mapping[stack_size] = mapping
        self.temp_types[stack_size] = temp_type

        case mapping
        in MapToLocal[idx]
          assert(idx < MAX_LOCAL_TYPES)
        else
        end
      end

      self.stack_size += 1
      self.sp_offset += 1

      return self.stack_opnd(0)
    end

    # Push one new value on the temp stack
    # Return a pointer to the new stack top
    def stack_push(val_type)
      return self.stack_push_mapping([MapToStack, val_type])
    end

    # Push the self value on the stack
    def stack_push_self
      return self.stack_push_mapping([MapToStack, Type::Unknown])
    end

    # Push a local variable on the stack
    def stack_push_local(local_idx)
      if local_idx >= MAX_LOCAL_TYPES
        return self.stack_push(Type::Unknown)
      end

      return self.stack_push_mapping([MapToLocal[local_idx], Type::Unknown])
    end

    # Pop N values off the stack
    # Return a pointer to the stack top before the pop operation
    def stack_pop(n = 1)
      assert(n <= self.stack_size)

      top = self.stack_opnd(0)

      # Clear the types of the popped values
      n.times do |i|
        idx = self.stack_size - i - 1

        if idx < MAX_TEMP_TYPES
          self.temp_types[idx] = Type::Unknown
          self.temp_mapping[idx] = MapToStack
        end
      end

      self.stack_size -= n
      self.sp_offset -= n

      return top
    end

    def shift_stack(argc)
      assert(argc < self.stack_size)

      method_name_index = self.stack_size - argc - 1

      (method_name_index...(self.stack_size - 1)).each do |i|
        if i + 1 < MAX_TEMP_TYPES
          self.temp_types[i] = self.temp_types[i + 1]
          self.temp_mapping[i] = self.temp_mapping[i + 1]
        end
      end
      self.stack_pop(1)
    end

    # Get the type of an instruction operand
    def get_opnd_type(opnd)
      case opnd
      in SelfOpnd
        self.self_type
      in StackOpnd[idx]
        assert(idx < self.stack_size)
        stack_idx = self.stack_size - 1 - idx

        # If outside of tracked range, do nothing
        if stack_idx >= MAX_TEMP_TYPES
          return Type::Unknown
        end

        mapping = self.temp_mapping[stack_idx]

        case mapping
        in MapToSelf
          self.self_type
        in MapToStack
          self.temp_types[self.stack_size - 1 - idx]
        in MapToLocal[idx]
          assert(idx < MAX_LOCAL_TYPES)
          self.local_types[idx]
        end
      end
    end

    # Get the currently tracked type for a local variable
    def get_local_type(idx)
      self.local_types[idx] || Type::Unknown
    end

    # Upgrade (or "learn") the type of an instruction operand
    # This value must be compatible and at least as specific as the previously known type.
    # If this value originated from self, or an lvar, the learned type will be
    # propagated back to its source.
    def upgrade_opnd_type(opnd, opnd_type)
      case opnd
      in SelfOpnd
        self.self_type = self.self_type.upgrade(opnd_type)
      in StackOpnd[idx]
        assert(idx < self.stack_size)
        stack_idx = self.stack_size - 1 - idx

        # If outside of tracked range, do nothing
        if stack_idx >= MAX_TEMP_TYPES
          return
        end

        mapping = self.temp_mapping[stack_idx]

        case mapping
        in MapToSelf
          self.self_type = self.self_type.upgrade(opnd_type)
        in MapToStack
          self.temp_types[stack_idx] = self.temp_types[stack_idx].upgrade(opnd_type)
        in MapToLocal[idx]
          assert(idx < MAX_LOCAL_TYPES)
          self.local_types[idx] = self.local_types[idx].upgrade(opnd_type)
        end
      end
    end

    # Get both the type and mapping (where the value originates) of an operand.
    # This is can be used with stack_push_mapping or set_opnd_mapping to copy
    # a stack value's type while maintaining the mapping.
    def get_opnd_mapping(opnd)
      opnd_type = self.get_opnd_type(opnd)

      case opnd
      in SelfOpnd
        return [MapToSelf, opnd_type]
      in StackOpnd[idx]
        assert(idx < self.stack_size)
        stack_idx = self.stack_size - 1 - idx

        if stack_idx < MAX_TEMP_TYPES
          return [self.temp_mapping[stack_idx], opnd_type]
        else
          # We can't know the source of this stack operand, so we assume it is
          # a stack-only temporary. type will be UNKNOWN
          assert(opnd_type == Type::Unknown)
          return [MapToStack, opnd_type]
        end
      end
    end

    # Overwrite both the type and mapping of a stack operand.
    def set_opnd_mapping(opnd, mapping_opnd_type)
      case opnd
      in SelfOpnd
        raise 'self always maps to self'
      in StackOpnd[idx]
        assert(idx < self.stack_size)
        stack_idx = self.stack_size - 1 - idx

        # If outside of tracked range, do nothing
        if stack_idx >= MAX_TEMP_TYPES
          return
        end

        mapping, opnd_type = mapping_opnd_type
        self.temp_mapping[stack_idx] = mapping

        # Only used when mapping == MAP_STACK
        self.temp_types[stack_idx] = opnd_type
      end
    end

    # Set the type of a local variable
    def set_local_type(local_idx, local_type)
      if local_idx >= MAX_LOCAL_TYPES
        return
      end

      # If any values on the stack map to this local we must detach them
      MAX_TEMP_TYPES.times do |stack_idx|
        case self.temp_mapping[stack_idx]
        in MapToStack
          # noop
        in MapToSelf
          # noop
        in MapToLocal[idx]
          if idx == local_idx
            self.temp_types[stack_idx] = self.local_types[idx]
            self.temp_mapping[stack_idx] = MapToStack
          else
            # noop
          end
        end
      end

      self.local_types[local_idx] = local_type
    end

    # Erase local variable type information
    # eg: because of a call we can't track
    def clear_local_types
      # When clearing local types we must detach any stack mappings to those
      # locals. Even if local values may have changed, stack values will not.
      MAX_TEMP_TYPES.times do |stack_idx|
        case self.temp_mapping[stack_idx]
        in MapToStack
          # noop
        in MapToSelf
          # noop
        in MapToLocal[local_idx]
          self.temp_types[stack_idx] = self.local_types[local_idx]
          self.temp_mapping[stack_idx] = MapToStack
        end
      end

      # Clear the local types
      self.local_types = [Type::Unknown] * MAX_LOCAL_TYPES
    end

    # Compute a difference score for two context objects
    def diff(dst)
      # Self is the source context (at the end of the predecessor)
      src = self

      # Can only lookup the first version in the chain
      if dst.chain_depth != 0
        return TypeDiff::Incompatible
      end

      # Blocks with depth > 0 always produce new versions
      # Sidechains cannot overlap
      if src.chain_depth != 0
        return TypeDiff::Incompatible
      end

      if dst.stack_size != src.stack_size
        return TypeDiff::Incompatible
      end

      if dst.sp_offset != src.sp_offset
        return TypeDiff::Incompatible
      end

      # Difference sum
      diff = 0

      # Check the type of self
      diff += case src.self_type.diff(dst.self_type)
      in TypeDiff::Compatible[diff] then diff
      in TypeDiff::Incompatible then return TypeDiff::Incompatible
      end

      # For each local type we track
      src.local_types.size.times do |i|
        t_src = src.local_types[i]
        t_dst = dst.local_types[i]
        diff += case t_src.diff(t_dst)
        in TypeDiff::Compatible[diff] then diff
        in TypeDiff::Incompatible then return TypeDiff::Incompatible
        end
      end

      # For each value on the temp stack
      src.stack_size.times do |i|
        src_mapping, src_type = src.get_opnd_mapping(StackOpnd[i])
        dst_mapping, dst_type = dst.get_opnd_mapping(StackOpnd[i])

        # If the two mappings aren't the same
        if src_mapping != dst_mapping
          if dst_mapping == MapToStack
            # We can safely drop information about the source of the temp
            # stack operand.
            diff += 1
          else
            return TypeDiff::Incompatible
          end
        end

        diff += case src_type.diff(dst_type)
        in TypeDiff::Compatible[diff] then diff
        in TypeDiff::Incompatible then return TypeDiff::Incompatible
        end
      end

      return TypeDiff::Compatible[diff]
    end

    private

    def assert(cond)
      unless cond
        raise "'#{cond.inspect}' was not true"
      end
    end
  end
end
