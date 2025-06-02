# frozen_string_literal: true
#
#   push-ws.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB # :nodoc:
  class Context
    # Creates a new workspace with the given object or binding, and appends it
    # onto the current #workspaces stack.
    #
    # See IRB::Context#change_workspace and IRB::WorkSpace.new for more
    # information.
    def push_workspace(*_main)
      if _main.empty?
        if @workspace_stack.size > 1
          # swap the top two workspaces
          previous_workspace, current_workspace = @workspace_stack.pop(2)
          @workspace_stack.push current_workspace, previous_workspace
        end
      else
        new_workspace = WorkSpace.new(workspace.binding, _main[0])
        @workspace_stack.push new_workspace
        new_workspace.load_helper_methods_to_main
      end
    end

    # Removes the last element from the current #workspaces stack and returns
    # it, or +nil+ if the current workspace stack is empty.
    #
    # Also, see #push_workspace.
    def pop_workspace
      @workspace_stack.pop if @workspace_stack.size > 1
    end
  end
end
