Clasp
===============
Clasp is a Common Lisp implementation that interoperates with C++ and uses LLVM for just-in-time (JIT) compilation to native code.

See http://drmeister.wordpress.com/2014/09/18/announcing-clasp/ for the announcement.

Clasp is not yet a full ANSI compliant Common Lisp - if you find differences between Clasp and the Common Lisp standard they are considered bugs in Clasp and please feel free to report them.

Libraries that clasp depends on can be obtained using the repository: externals-clasp<br>
https://github.com/drmeister/externals-clasp.git<br>
You can build externals-clasp or you can use the makefile as a guide configure your environment by hand.

**BUILDING CLASP**

Clasp has been compiled on OS X 10.9.5 using Xcode 6.0.1

Clasp has been compiled on recent (post 2013) versions of Ubuntu Linux

To build Clasp from within the top level directory do the following.

1) Copy local.config.darwin or local.config.linux to local.config

2) Edit local.config and configure it for your system

3) Type:    _make_        to build mps and boehm versions of Clasp<br>
   or type: _make-boehm_  to make the boehm version of Clasp<br>
   or type: _make-mps_    to make the MPS version of Clasp

4) Install the directory in $PREFIX/MacOS or $PREFIX/bin (from local.config) in your path<br>
   then type: clasp_mps_o     to start the Lisp REPL of the MPS version of Clasp<br>
   or type:   clasp_boehm_o   to start the Lisp REPL of the Boehm version of Clasp

5) Type: (print "Hello world")  in the REPL and away you go (more documentation to follow)


If you want to install the libraries separately they are:<br>
Contact me for more info - I can add more details to what is below.<br>
Boost build v2<br>
boost libraries ver 1.55<br>
Boehm 7.2<br>
LLVM/clang 3.5<br>
ecl ver 12<br>
gmp-5.0.5<br>
expat-2.0.1<br>
zlib-1.2.8<br>
readline-6.2<br>
