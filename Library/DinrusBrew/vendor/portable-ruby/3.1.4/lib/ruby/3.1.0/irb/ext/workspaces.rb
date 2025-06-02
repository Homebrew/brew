# frozen_string_literal: false
#
#   push-ws.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

module IRB # :nodoc:
  class Context

    # Size of the current WorkSpace stack
    def irb_level
      workspace_stack.size
    end

    # WorkSpaces in the current stack
    def workspaces
      if defined? @workspaces
        @workspaces
      else
        @workspaces = []
      end
    end

    # Creates a new workspace with the given object or binding, and appends it
    # onto the current #workspaces stack.
    #
    # See IRB::Context#change_workspace and IRB::WorkSpace.new for more
    # information.
    def push_workspace(*_main)
      if _main.empty?
        if workspaces.empty?
          print "No other workspace\n"
          return nil
        end
        ws = workspaces.pop
        workspaces.push @workspace
        @workspace = ws
        return workspaces
      end

      workspaces.push @workspace
      @workspace = WorkSpace.new(@workspace.binding, _main[0])
      if !(class<<main;ancestors;end).include?(ExtendCommandBundle)
        main.extend ExtendCommandBundle
      end
    end

    # Removes the last element from the current #workspaces stack and returns
    # it, or +nil+ if the current workspace stack is empty.
    #
    # Also, see #push_workspace.
    def pop_workspace
      if workspaces.empty?
        print "workspace stack empty\n"
        return
      end
      @workspace = workspaces.pop
    end
  end
end
