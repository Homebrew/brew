---
last_review_date: "1970-01-01"
---

# Nomination for Mozilla Open Source Support, Track III

## Solicitation

The open source and free software ecosystem needs to be secure; thank you for your desire to help make that even more of a reality by suggesting a project for an SOS audit. Note that this form allows you to make a *suggestion*, not an *application* - please do not expect to hear back from us. Unlike other tracks of MOSS, Mozilla will take the initiative to approach organizations it wishes to make offers to, perhaps guided by a suggestion, perhaps not.

We have a series of factors we consider when evaluating an application. For example:

* How commonly used is the software?
* Is the software network-facing or does it regularly process untrusted data?
* How vital is the software to the continued functioning of the Internet or the Web?
* Does the software depend on closed-source code, e.g. in a web service?
* Are the software’s maintainers aware of and supportive of the application for support from the SOS fund?
* Has the software been audited before? If so, when and how extensively? Was the audit made public? If so, where?
* Does the software have existing corporate backing or involvement?

The answers to such questions are often not “yes” or “no”, but matters of degree, and so Mozilla will take the entire picture into account when assessing projects.

## Application

### Project name

Homebrew

### Your name

Jonathan Chang

### Your relationship to the project

Maintainer

### Project website (This needs to be somewhere we can obtain the source code.)

<https://brew.sh>

### Project description

Homebrew aims to be the missing package manager for macOS (and Linux). Its primary goal is to be useful to as many people as possible, while remaining maintainable to a professional, high standard by a small group of volunteers. Where possible and sensible, it should seek to use features of macOS to blend in with the macOS and Apple ecosystems. On Linux and Windows, it should seek to be as self-contained as possible.

### What copyright license or licenses cover the project's source code?

Homebrew's code is licensed under a BSD 2-clause license. Homebrew also vendors three dependencies, which are all MIT licensed (<https://github.com/Homebrew/brew/tree/master/Library/Homebrew/vendor>).

### Does the project contain any proprietary code, or depend on or use a proprietary web service? If so, please give details

Homebrew's source code is hosted on GitHub. Homebrew interacts with the Bintray API to upload and host our binary packages. Homebrew also relies on Microsoft's Azure Pipelines continuous integration service to run our test suite on macOS and Linux.

### What is the maintenance status of the project?

*Is the project actively maintained? If so, please give contact details of the maintainers and indicate whether they are aware of and/or supportive of this application. When was the most recent release?*

Homebrew is actively maintained, and its last release was v2.1.0 on April 5, 2019. Homebrew has 22 maintainers; their GitHub handle is listed below as well as other specific administrative roles they might have:

* Mike McQuaid (@MikeMcQuaid, Project Leader)
* Misty De Meo (@mistydemeo, Project Leadership, Technical Steering)
* Markus Reiter (@reitermarkus, Project Leadership, Technical Steering)
* Jonathan Chang (@jonchang, Project Leadership)
* Shaun Jackman (@sjackman, Project Leadership)
* FX Coudert (@fxcoudert, Technical Steering)
* Michka Popoff (@iMichka, Technical Steering)
* Chongyu Zhu (@lembacon)
* Claudia Pellegrino (@claui)
* Eric Knibbe (@EricFromCanada)
* Gautham Goli (@GauthamGoli)
* Igor Kapkov (@igas)
* Izaak "Zaak" Beekman (@zbeekman)
* Jan Viljanen (@javian)
* Jason Tedor (@jasontedor)
* Sean Molenaar (@SMillerDev)
* Steven Peters (@scpeters)
* Thierry Moisan (@Moisan)
* Tom Schoonjans (@tschoonj)
* Viktor Szakats (@vszakats)
* Vítor Galvão (@vitorgalvao)
* William Woodruff (@woodruffw)

The other maintainers reviewed this application and have expressed their support.

### How popular is the project?

*How many installed/used instances are there? Please give as much data as possible, including the source of any numbers.*

According to anonymous analytics data collected per our policy (<https://docs.brew.sh/Analytics>), Homebrew on macOS has approximately 1.24 million instances that have been active in the past month. This is an increase of 19.3% over the same period last year, with 1.04 million active instances.

Homebrew on Linux has approximately 15 thousand active instances, an increase of 75% over last year with 8.6 thousand instances.

Each installed instance of Homebrew is quite active: over the last year we recorded approximately 166 million installation events; meaning on average, a instance will install software about 1.7 times per day.

### Please give pointers to advisories or other documentation for any recent security bugs that have been found in the project

<https://brew.sh/2018/08/05/security-incident-disclosure/>

### Has the project had a security source code audit before? If so, when and how extensively?

*If it has been audited before and the report is public, please give the URL.*

Homebrew has not been previously audited for security issues. Our HackerOne project receives ad-hoc reports of security issues.

### What formal or informal corporate involvement is there in the development process?

No maintainer is currently employed by a corporation to work specifically on Homebrew. Our bylaws (<https://docs.brew.sh/Homebrew-Governance>) forbid more than two employees of the same company serving on either our Project Leadership Committee or Technical Steering Committee.

We receive in-kind sponsorship for several services we use for our infrastructure, but these corporations are not involved in our development process:

* MacStadium (server colocation)
* DigitalOcean (virtual private servers)
* CommsWorld (server colocation)
* Bintray (binary hosting)
* AgileBits (password & key storage)

### Why do you think this project is a suitable recipient of an SOS award?

*This is the most important question. Please refer to the criteria at <https://wiki.mozilla.org/MOSS/Secure_Open_Source> . Also, please explain in what ways the code is exposed to attackers, and the possible impact of a security problem.*

Homebrew on macOS has over a million installed instances and, as measured via Google Trends ("homebrew mac" vs "macports"), has been the most popular package manager for macOS since 2015. As such, any security vulnerability in Homebrew could affect many macOS users.

As a package manager, Homebrew often accesses the network to download and install binaries, or to extract and compile tarballs from their original source. Homebrew formulae have the ability to run untrusted code from the network, such as Makefiles and build scripts. Vulnerabilities in Homebrew's network handling and verification code could therefore deliver malware to end-users.

Homebrew is often used in continuous integration (CI) infrastructure to install development tools on macOS. Travis CI, for example, recommends Homebrew as its default for installing development packages on CI containers. Any  weakness in the Homebrew build environment could compromise software built via CI for macOS systems, compounding the effects of any security vulnerability.

Furthermore, many web developers currently use macOS as their development platform of choice. The 2017 Stack Overflow Developer Survey, the last year these data were available, indicated that of the 26,235 self-described web developers, 4,220 (16%) used macOS as their development platform. When only examining front-end developers, nearly 70% used macOS. Homebrew's analytics reinforces its importance for web development---its most installed package is Node.js, which accounts for nearly 5% of all package installations recorded (2.9M install events). A security vulnerability in Homebrew could compromise a large proportion of web development machines.

Homebrew on Linux is often used by high performance computing and other scientific computing users, and managed by a special role account called "linuxbrew". Compromise of the Homebrew software on Linux could result in the misuse or takeover of computing clusters with up to tens of thousands of nodes, each with significant computing resources and network access to crack passwords or conduct denial-of-service attacks.
