:- use_module(library(debug)).

:- dynamic
    currently_debugging0/1.

:- multifile
    currently_debugging0/1.

currently_debugging0('0c2cda72fb982c1d312ec533a8dfb359').
currently_debugging0('1cbe5a4bd869c2f5e64ce08480996a97').
currently_debugging0('360a93fb8026fef121088cd7cfa44ab9').
currently_debugging0('9f251a7f61cff3fd85550a1b5c2f4efd').
currently_debugging0('bc03c42d0f8bd054abe94fa0a3e8d0d7').
currently_debugging0('c557802a90c57502d99e71d356dec90f').

:- debug(lclean).
:- debug(lotus(_)).
:- debug(seedlist(_)).
:- debug(wm(_)).
