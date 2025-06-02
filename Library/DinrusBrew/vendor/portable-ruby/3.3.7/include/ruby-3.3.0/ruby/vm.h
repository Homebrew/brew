#ifndef RUBY_VM_H                                    /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_VM_H 1
/**
 * @file
 * @author     $Author$
 * @date       Sat May 31 15:17:36 2008
 * @copyright  Copyright (C) 2008 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 *
 * We  planned to  have multiple  VMs  run side-by-side.   The API  here was  a
 * preparation of that feature.  The topic branch was eventually abandoned, and
 * we now have Ractor.  This file is kind of obsolescent.
 */
#include "ruby/internal/dllexport.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * The opaque struct to hold VM internals.  Its fields are intentionally hidden
 * from extension libraries because it changes drastically time to time.
 */
typedef struct rb_vm_struct ruby_vm_t;

/**
 * Destructs the  passed VM.   You don't  have to call  this API  directly now,
 * because there is  no way to create one.   There is only one VM  at one time.
 * ruby_stop() should just suffice.
 */
int ruby_vm_destruct(ruby_vm_t *vm);

/**
 * ruby_vm_at_exit registers a function _func_ to be invoked when a VM
 * passed away.  Functions registered this way runs in reverse order
 * of registration, just like END {} block does.  The difference is
 * its timing to be triggered. ruby_vm_at_exit functions runs when a
 * VM _passed_ _away_, while END {} blocks runs just _before_ a VM
 * _is_ _passing_ _away_.
 *
 * You cannot register a function to another VM than where you are in.
 * So where to register is intuitive, omitted.  OTOH the argument
 * _func_ cannot know which VM it is in because at the time of
 * invocation, the VM has already died and there is no execution
 * context.  The VM itself is passed as the first argument to it.
 *
 * @param[in] func the function to register.
 */
void ruby_vm_at_exit(void(*func)(ruby_vm_t *));

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_VM_H */
