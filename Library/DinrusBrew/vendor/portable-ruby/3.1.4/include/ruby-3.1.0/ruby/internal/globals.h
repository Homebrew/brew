#ifndef RBIMPL_GLOBALS_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_GLOBALS_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Ruby-level global variables / constants, visible from C.
 */
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"

/**
 * @defgroup object Core objects and their operations
 *
 * @internal
 *
 * There are several  questionable constants listed in this  header file.  They
 * are intentionally left untouched for purely academic backwards compatibility
 * concerns.  But for instance do any one of 3rd party extension libraries even
 * need to know that there is NameError::Message?
 *
 * @endinternal
 *
 * @{
 */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RUBY_INTEGER_UNIFICATION 1

RUBY_EXTERN VALUE rb_mKernel;                 /**< `Kernel` module. */
RUBY_EXTERN VALUE rb_mComparable;             /**< `Comparable` module. */
RUBY_EXTERN VALUE rb_mEnumerable;             /**< `Enumerable` module. */
RUBY_EXTERN VALUE rb_mErrno;                  /**< `Errno` module. */
RUBY_EXTERN VALUE rb_mFileTest;               /**< `FileTest` module. */
RUBY_EXTERN VALUE rb_mGC;                     /**< `GC` module. */
RUBY_EXTERN VALUE rb_mMath;                   /**< `Math` module. */
RUBY_EXTERN VALUE rb_mProcess;                /**< `Process` module. */
RUBY_EXTERN VALUE rb_mWaitReadable;           /**< `IO::WaitReadable` module. */
RUBY_EXTERN VALUE rb_mWaitWritable;           /**< `IO::WaitReadable` module. */

RUBY_EXTERN VALUE rb_cBasicObject;            /**< `BasicObject` class. */
RUBY_EXTERN VALUE rb_cObject;                 /**< `Object` class. */
RUBY_EXTERN VALUE rb_cArray;                  /**< `Array` class. */
RUBY_EXTERN VALUE rb_cBinding;                /**< `Binding` class. */
RUBY_EXTERN VALUE rb_cClass;                  /**< `Class` class. */
RUBY_EXTERN VALUE rb_cDir;                    /**< `Dir` class. */
RUBY_EXTERN VALUE rb_cEncoding;               /**< `Encoding` class. */
RUBY_EXTERN VALUE rb_cEnumerator;             /**< `Enumerator` class. */
RUBY_EXTERN VALUE rb_cFalseClass;             /**< `FalseClass` class. */
RUBY_EXTERN VALUE rb_cFile;                   /**< `File` class. */
RUBY_EXTERN VALUE rb_cComplex;                /**< `Complex` class. */
RUBY_EXTERN VALUE rb_cFloat;                  /**< `Float` class. */
RUBY_EXTERN VALUE rb_cHash;                   /**< `Hash` class. */
RUBY_EXTERN VALUE rb_cIO;                     /**< `IO` class. */
RUBY_EXTERN VALUE rb_cInteger;                /**< `Module` class. */
RUBY_EXTERN VALUE rb_cMatch;                  /**< `MatchData` class. */
RUBY_EXTERN VALUE rb_cMethod;                 /**< `Method` class. */
RUBY_EXTERN VALUE rb_cModule;                 /**< `Module` class. */
RUBY_EXTERN VALUE rb_cRefinement;             /**< `Refinement` class. */
RUBY_EXTERN VALUE rb_cNameErrorMesg;          /**< `NameError::Message` class. */
RUBY_EXTERN VALUE rb_cNilClass;               /**< `NilClass` class. */
RUBY_EXTERN VALUE rb_cNumeric;                /**< `Numeric` class. */
RUBY_EXTERN VALUE rb_cProc;                   /**< `Proc` class. */
RUBY_EXTERN VALUE rb_cRandom;                 /**< `Random` class. */
RUBY_EXTERN VALUE rb_cRange;                  /**< `Range` class. */
RUBY_EXTERN VALUE rb_cRational;               /**< `Rational` class. */
RUBY_EXTERN VALUE rb_cRegexp;                 /**< `Regexp` class. */
RUBY_EXTERN VALUE rb_cStat;                   /**< `File::Stat` class. */
RUBY_EXTERN VALUE rb_cString;                 /**< `String` class. */
RUBY_EXTERN VALUE rb_cStruct;                 /**< `Struct` class. */
RUBY_EXTERN VALUE rb_cSymbol;                 /**< `Sumbol` class. */
RUBY_EXTERN VALUE rb_cThread;                 /**< `Thread` class. */
RUBY_EXTERN VALUE rb_cTime;                   /**< `Time` class. */
RUBY_EXTERN VALUE rb_cTrueClass;              /**< `TrueClass` class. */
RUBY_EXTERN VALUE rb_cUnboundMethod;          /**< `UnboundMethod` class. */

/**
 * @}
 * @addtogroup exception
 * @{
 */

RUBY_EXTERN VALUE rb_eException;                 /**< Mother of all exceptions. */
RUBY_EXTERN VALUE rb_eStandardError;             /**< `StandardError` exception. */
RUBY_EXTERN VALUE rb_eSystemExit;                /**< `SystemExit` exception. */
RUBY_EXTERN VALUE rb_eInterrupt;                 /**< `Interrupt` exception. */
RUBY_EXTERN VALUE rb_eSignal;                    /**< `SignalException` exception. */
RUBY_EXTERN VALUE rb_eFatal;                     /**< `fatal` exception. */
RUBY_EXTERN VALUE rb_eArgError;                  /**< `ArgumentError` exception. */
RUBY_EXTERN VALUE rb_eEOFError;                  /**< `EOFError` exception. */
RUBY_EXTERN VALUE rb_eIndexError;                /**< `IndexError` exception. */
RUBY_EXTERN VALUE rb_eStopIteration;             /**< `StopIteration` exception. */
RUBY_EXTERN VALUE rb_eKeyError;                  /**< `KeyError` exception. */
RUBY_EXTERN VALUE rb_eRangeError;                /**< `RangeError` exception. */
RUBY_EXTERN VALUE rb_eIOError;                   /**< `IOError` exception. */
RUBY_EXTERN VALUE rb_eRuntimeError;              /**< `RuntimeError` exception. */
RUBY_EXTERN VALUE rb_eFrozenError;               /**< `FrozenError` exception. */
RUBY_EXTERN VALUE rb_eSecurityError;             /**< `SecurityError` exception. */
RUBY_EXTERN VALUE rb_eSystemCallError;           /**< `SystemCallError` exception. */
RUBY_EXTERN VALUE rb_eThreadError;               /**< `ThreadError` exception. */
RUBY_EXTERN VALUE rb_eTypeError;                 /**< `TypeError` exception. */
RUBY_EXTERN VALUE rb_eZeroDivError;              /**< `ZeroDivisionError` exception. */
RUBY_EXTERN VALUE rb_eNotImpError;               /**< `NotImplementedError` exception. */
RUBY_EXTERN VALUE rb_eNoMemError;                /**< `NoMemoryError` exception. */
RUBY_EXTERN VALUE rb_eNoMethodError;             /**< `NoMethodError` exception. */
RUBY_EXTERN VALUE rb_eFloatDomainError;          /**< `FloatDomainError` exception. */
RUBY_EXTERN VALUE rb_eLocalJumpError;            /**< `LocalJumpError` exception. */
RUBY_EXTERN VALUE rb_eSysStackError;             /**< `SystemStackError` exception. */
RUBY_EXTERN VALUE rb_eRegexpError;               /**< `RegexpError` exception. */
RUBY_EXTERN VALUE rb_eEncodingError;             /**< `EncodingError` exception. */
RUBY_EXTERN VALUE rb_eEncCompatError;            /**< `Encoding::CompatibilityError` exception. */
RUBY_EXTERN VALUE rb_eNoMatchingPatternError;    /**< `NoMatchingPatternError` exception. */
RUBY_EXTERN VALUE rb_eNoMatchingPatternKeyError; /**< `NoMatchingPatternKeyError` exception. */

RUBY_EXTERN VALUE rb_eScriptError;               /**< `ScriptError` exception. */
RUBY_EXTERN VALUE rb_eNameError;                 /**< `NameError` exception. */
RUBY_EXTERN VALUE rb_eSyntaxError;               /**< `SyntaxError` exception. */
RUBY_EXTERN VALUE rb_eLoadError;                 /**< `LoadError` exception. */

RUBY_EXTERN VALUE rb_eMathDomainError;           /**< `Math::DomainError` exception. */

/**
 * @}
 * @addtogroup object
 * @{
 */

RUBY_EXTERN VALUE rb_stdin;                      /**< `STDIN` constant. */
RUBY_EXTERN VALUE rb_stdout;                     /**< `STDOUT` constant. */
RUBY_EXTERN VALUE rb_stderr;                     /**< `STDERR` constant. */

RBIMPL_ATTR_PURE()
/**
 * Object  to class  mapping  function.   Every object  have  its class.   This
 * function obtains that.
 *
 * @param[in]  obj  Target object to query.
 * @return     The class of the given object.
 *
 * @internal
 *
 * This  function is  a super-duper  hot  path.  Optimised  targeting modern  C
 * compilers and x86_64 architecture.
 */
static inline VALUE
rb_class_of(VALUE obj)
{
    if (! RB_SPECIAL_CONST_P(obj)) {
        return RBASIC_CLASS(obj);
    }
    else if (obj == RUBY_Qfalse) {
        return rb_cFalseClass;
    }
    else if (obj == RUBY_Qnil) {
        return rb_cNilClass;
    }
    else if (obj == RUBY_Qtrue) {
        return rb_cTrueClass;
    }
    else if (RB_FIXNUM_P(obj)) {
        return rb_cInteger;
    }
    else if (RB_STATIC_SYM_P(obj)) {
        return rb_cSymbol;
    }
    else if (RB_FLONUM_P(obj)) {
        return rb_cFloat;
    }

#if !RUBY_DEBUG
    RBIMPL_UNREACHABLE_RETURN(Qfalse);
#else
    RUBY_ASSERT_FAIL("unexpected type");
#endif
}

#define CLASS_OF rb_class_of /**< @old{rb_class_of} */

RBIMPL_SYMBOL_EXPORT_END()

/** @} */

#endif /* RBIMPL_GLOBALS_H */
