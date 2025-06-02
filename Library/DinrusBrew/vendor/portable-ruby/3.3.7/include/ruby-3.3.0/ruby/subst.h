#ifndef RUBY_SUBST_H                                 /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_SUBST_H 1
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#undef snprintf
#undef vsnprintf
#define snprintf ruby_snprintf
#define vsnprintf ruby_vsnprintf

#ifdef BROKEN_CLOSE
#undef getpeername
#define getpeername ruby_getpeername
#undef getsockname
#define getsockname ruby_getsockname
#undef shutdown
#define shutdown ruby_shutdown
#undef close
#define close ruby_close
#endif
#endif
