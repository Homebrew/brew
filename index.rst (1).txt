Welcome to Bandit
=================

Bandit is a tool designed to find common security issues in Python code. To do
this, Bandit processes each file, builds an AST from it, and runs appropriate
plugins against the AST nodes.  Once Bandit has finished scanning all the files,
it generates a report.

Using and Extending Bandit
==========================
.. toctree::
   :maxdepth: 1

   start
   config
   integrations
   plugins/index
   blacklists/index
   formatters/index
   ci-cd/index
   faq

Contributing
============

* `Source code`_
* `Issue tracker`_
* Join us on `Discord`_

.. _`Source code`: https://github.com/PyCQA/bandit
.. _`Issue tracker`: https://github.com/PyCQA/bandit/issues
.. _`Discord`: https://discord.gg/qYxpadCgkx

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`

License
=======

The ``bandit`` library is provided under the terms and conditions of the
`Apache License 2.0 <https://www.apache.org/licenses/LICENSE-2.0.txt>`_
