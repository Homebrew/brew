# frozen_string_literal: true

module Net
  class IMAP < Protocol

    # -------------------------------------------------------------------------
    # :section: Message Flags: system flags
    #
    # A message has a list of zero or more named tokens, known as "flags",
    # associated with it. A flag is set by its addition to this list and is
    # cleared by its removal. There are two types of flags in IMAP4rev2: system
    # flags and keywords. A flag of either type can be permanent or
    # session-only.
    #
    # A "system flag" is a message flag name that is predefined in the IMAP
    # specification and begins with "\".  +Net::IMAP+ returns all system flags
    # as symbols, without the "\" prefix.
    #
    # The descriptions here were copied from the IMAP4rev2 specification:
    # [RFC-9051 § 2.3.2](https://www.rfc-editor.org/rfc/rfc9051.html#section-2.3.2)
    #
    # See [RFC-3501 § 2.3.2](https://www.rfc-editor.org/rfc/rfc3501.html#section-2.3.2)
    # for a description of the flags message attribute and system flag semantics
    # in IMAP4rev1.
    # -------------------------------------------------------------------------

    # Flag indicating a message has been read.
    SEEN = :Seen

    # Flag indicating a message has been answered.
    ANSWERED = :Answered

    # A message flag indicating a message has been flagged for special or urgent
    # attention.
    #
    # Also a mailbox special use attribute, which indicates that this mailbox
    # presents all messages marked in some way as "important".  When this
    # special use is supported, it is likely to represent a virtual mailbox
    # collecting messages (from other mailboxes) that are marked with the
    # "\Flagged" message flag.
    FLAGGED = :Flagged

    # Flag indicating a message has been marked for deletion.  This
    # will occur when the mailbox is closed or expunged.
    DELETED = :Deleted

    # Flag indicating a message is only a draft or work-in-progress version.
    DRAFT = :Draft

    # Flag indicating that the message is "recent," meaning that this
    # session is the first session in which the client has been notified
    # of this message.
    #
    # This flag was defined by
    # IMAP4rev1 [RFC-3501](https://www.rfc-editor.org/rfc/rfc3501.html),
    # and has been deprecated by
    # IMAP4rev2 [RFC-9051](https://www.rfc-editor.org/rfc/rfc9051.html).
    RECENT = :Recent

    # -------------------------------------------------------------------------
    # :section: Mailbox Name Attributes, Base attributes
    # Mailbox name attributes will be returned in LIST responses.  Base
    # attributes must be returned according to the server's capabilities.
    #
    # IMAP4 specifies that all mailbox name attributes, including future
    # extensions, begin with "\".  +Net::IMAP+ returns all mailbox attributes as
    # symbols, without the "\" prefix.
    #
    # The descriptions here were copied from the IMAP4rev2 specification:
    # [RFC9051 § 7.3.1](https://www.rfc-editor.org/rfc/rfc9051.html#section-7.3.1).
    #
    # Other mailbox name attributes can be found in the [IANA IMAP Mailbox Name
    # Attributes registry](https://www.iana.org/assignments/imap-mailbox-name-attributes/imap-mailbox-name-attributes.xhtml)].
    # -------------------------------------------------------------------------

    # The "\NonExistent" attribute indicates that a mailbox name does not refer
    # to an existing mailbox. Note that this attribute is not meaningful by
    # itself, as mailbox names that match the canonical LIST pattern but don't
    # exist must not be returned unless one of the two conditions listed below
    # is also satisfied:
    #
    # 1. The mailbox name also satisfies the selection criteria (for example,
    #    it is subscribed and the "SUBSCRIBED" selection option has been
    #    specified).
    #
    # 2. "RECURSIVEMATCH" has been specified, and the mailbox name has at least
    #    one descendant mailbox name that does not match the LIST pattern and
    #    does match the selection criteria.
    #
    # In practice, this means that the "\NonExistent" attribute is usually
    # returned with one or more of "\Subscribed", "\Remote", "\HasChildren", or
    # the CHILDINFO extended data item.
    #
    # The client must treat the presence of the \NonExistent attribute as if the
    # \NoSelect attribute was also sent by the server
    NONEXISTENT = :NonExistent

    # Mailbox attribute indicating it is not possible for any child levels of
    # hierarchy to exist under this name; no child levels exist now and none can
    # be created in the future children.
    #
    # The client must treat the presence of the \NoInferiors attribute as if the
    # \HasNoChildren attribute was also sent by the server
    NOINFERIORS = :Noinferiors

    # Mailbox attribute indicating it is not possible to use this name as a
    # selectable mailbox.
    NOSELECT = :Noselect

    # The presence of this attribute indicates that the mailbox has child
    # mailboxes. A server SHOULD NOT set this attribute if there are child
    # mailboxes and the user does not have permission to access any of them.  In
    # this case, \HasNoChildren SHOULD be used. In many cases, however, a server
    # may not be able to efficiently compute whether a user has access to any
    # child mailboxes. Note that even though the \HasChildren attribute for a
    # mailbox must be correct at the time of processing the mailbox, a client
    # must be prepared to deal with a situation when a mailbox is marked with
    # the \HasChildren attribute, but no child mailbox appears in the response
    # to the LIST command. This might happen, for example, due to child
    # mailboxes being deleted or made inaccessible to the user (using access
    # control) by another client before the server is able to list them.
    #
    # It is an error for the server to return both a \HasChildren and a
    # \HasNoChildren attribute in the same LIST response. A client that
    # encounters a LIST response with both \HasChildren and \HasNoChildren
    # attributes present should act as if both are absent in the LIST response.
    HAS_CHILDREN = :HasChildren

    # The presence of this attribute indicates that the mailbox has NO child
    # mailboxes that are accessible to the currently authenticated user.
    #
    # It is an error for the server to return both a \HasChildren and a
    # \HasNoChildren attribute in the same LIST response. A client that
    # encounters a LIST response with both \HasChildren and \HasNoChildren
    # attributes present should act as if both are absent in the LIST response.
    #
    # Note: the \HasNoChildren attribute should not be confused with the
    # \NoInferiors attribute, which indicates that no child mailboxes exist now
    # and none can be created in the future.
    HAS_NO_CHILDREN = :HasNoChildren

    # The mailbox has been marked "interesting" by the server; the mailbox
    # probably contains messages that have been added since the last time the
    # mailbox was selected.
    #
    # If it is not feasible for the server to determine whether or not the
    # mailbox is "interesting", the server SHOULD NOT send either \Marked or
    # \Unmarked. The server MUST NOT send more than one of \Marked, \Unmarked,
    # and \Noselect for a single mailbox, and it MAY send none of these.
    MARKED = :Marked

    # The mailbox does not contain any additional messages since the last time
    # the mailbox was selected.
    #
    # If it is not feasible for the server to determine whether or not the
    # mailbox is "interesting", the server SHOULD NOT send either \Marked or
    # \Unmarked. The server MUST NOT send more than one of \Marked, \Unmarked,
    # and \Noselect for a single mailbox, and it MAY send none of these.
    UNMARKED = :Unmarked

    # The mailbox name was subscribed to using the SUBSCRIBE command.
    SUBSCRIBED = :Subscribed

    # The mailbox is a remote mailbox.
    REMOTE = :Remove

    # -------------------------------------------------------------------------
    # :section: Mailbox Name Attributes, Special Use
    # Mailbox name attributes will be returned in LIST responses.  In addition
    # to the base mailbox name attributes defined above, an IMAP server MAY also
    # include any or all of the following attributes that denote "role" (or
    # "special-use") of a mailbox. These attributes are included along with base
    # attributes defined above. A given mailbox may have none, one, or more than
    # one of these attributes. In some cases, a special use is advice to a
    # client about what to put in that mailbox. In other cases, it's advice to a
    # client about what to expect to find there.
    #
    # IMAP4 specifies that all mailbox name attributes, including future
    # extensions, begin with "\".  +Net::IMAP+ returns all mailbox attributes as
    # symbols, without the "\" prefix.
    #
    # The descriptions here were copied from the IMAP4rev2 specification:
    # [RFC-9051 § 7.3.1](https://www.rfc-editor.org/rfc/rfc9051.html#section-7.3.1).
    #
    # Other mailbox name attributes can be found in the [IANA IMAP Mailbox Name
    # Attributes registry](https://www.iana.org/assignments/imap-mailbox-name-attributes/imap-mailbox-name-attributes.xhtml)].
    # -------------------------------------------------------------------------

    # Mailbox attribute indicating that this mailbox presents all messages in
    # the user's message store. Implementations MAY omit some messages, such as,
    # perhaps, those in \Trash and \Junk. When this special use is supported, it
    # is almost certain to represent a virtual mailbox
    ALL = :All

    # Mailbox attribute indicating that this mailbox is used to archive
    # messages. The meaning of an "archival" mailbox is server dependent;
    # typically, it will be used to get messages out of the inbox, or otherwise
    # keep them out of the user's way, while still making them accessible
    ARCHIVE = :Archive

    # Mailbox attribute indicating that this mailbox is used to hold draft
    # messages -- typically, messages that are being composed but have not yet
    # been sent. In some server implementations, this might be a virtual
    # mailbox, containing messages from other mailboxes that are marked with the
    # "\Draft" message flag. Alternatively, this might just be advice that a
    # client put drafts here
    DRAFTS = :Drafts

    # FLAGGED is defined with the system flags section.

    # Mailbox attribute indicating that this mailbox is where messages deemed to
    # be junk mail are held. Some server implementations might put messages here
    # automatically.  Alternatively, this might just be advice to a client-side
    # spam filter.
    JUNK = :Junk

    # Mailbox attribute indicating that this mailbox is used to hold copies of
    # messages that have been sent. Some server implementations might put
    # messages here automatically. Alternatively, this might just be advice that
    # a client save sent messages here.
    SENT = :Sent

    # Mailbox attribute indicating that this mailbox is used to hold messages
    # that have been deleted or marked for deletion. In some server
    # implementations, this might be a virtual mailbox, containing messages from
    # other mailboxes that are marked with the "\Deleted" message flag.
    # Alternatively, this might just be advice that a client that chooses not to
    # use the IMAP "\Deleted" model should use as its trash location. In server
    # implementations that strictly expect the IMAP "\Deleted" model, this
    # special use is likely not to be supported.
    TRASH = :Trash

  end
end
