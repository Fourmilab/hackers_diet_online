# The Hacker's Diet *Online*

[**The Hacker's Diet *Online***](https://www.fourmilab.ch/hackdiet/online/hdo.html)
is a Web-based application, companion to my book,
*[The Hacker's Diet](https://www.fourmilab.ch/hackdiet/)*, which
allows you to maintain weight and exercise 
logs, produce custom charts, analyse trends, and plan diets from any 
computer with Internet connectivity and a Web browser. Data may be 
imported from and exported to other versions of the computer tools, or 
exported as CSV or XML for analysis with other programs.

This repository contains the master source code for the application,
implemented as a Common Gateway Interface (CGI) program in the Perl
programming language, with browser support in JavaScript.  The
complete tree of Web documents describing and supporting the
application is included.

## Structure of the repository

This repository is organised into the following directories.

* **src**: Source code for the CGI application and support utilities,
written in the [Literate Programming](https://en.wikipedia.org/wiki/Literate_programming)
methodology using the **[nuweb](http://nuweb.sourceforge.net/)** system.
Source code and integral documentation is provided in the `src/hdiet.pdf`
file.

* **webdoc**: Web pages providing documentation for the application
and support files such as style sheets, images, and JavaScript
programs.  The main user manual is `webdoc/hdo.html`.

## Installation

As with any Common Gateway Interface Web application, installation on
a Web server will require installing all of the prerequisites (Perl
modules, etc.) required by the programs, adapting them to the directory
structure of your server, and linking to them from access documents
accessible on the server over the Web.  This is a complicated process
which requires detailed knowledge of both your Web server's configuration
and the requirements of the application, so no cookbook procedure can
be supplied.
