:- module(
  lwm_basket,
  [
    cleaned/1, % ?Md5:atom
    pending/1, % ?Md5:atom
    pick_pending/1, % +Md5:atom
    pick_unpacked/1 % +Md5:atom
  ]
).

/** <module> LOD Laundromat: basket

The LOD basket for URLs that are to be processed by the LOD Washing Machine.

~~~{.sh}
$ curl --data "url=http://acm.rkbexplorer.com/id/998550" http://lodlaundry.wbeek.ops.few.vu.nl/lwm/basket
~~~

@author Wouter Beek
@version 2014/05-2014/06, 2014/08
*/

:- use_module(plRdf_term(rdf_literal)).

:- use_module(lwm_sparql(lwm_sparql_api)).
:- use_module(lwm(store_triple)).



%! cleaned(+Md5:atom) is semidet.
%! cleaned(-Md5:atom) is nondet.

cleaned(Md5):-
  var(Md5), !,
  with_mutex(lwm_basket, (
    lwm_sparql_select([ll], [md5],
        [rdf(var(md5res),ll:end_clean,var(end_clean)),
         rdf(var(md5res),ll:md5,var(md5))],
        [[Literal]], [limit(1)]),
    rdf_literal(Literal, Md5, _)
  )).
cleaned(Md5):-
  with_mutex(lwm_basket, (
    lwm_sparql_ask([ll],
        [rdf(var(md5),ll:md5,literal(type(xsd:string,Md5))),
         rdf(var(md5),ll:end_clean,var(end))], [])
  )).


%! cleaning(+Md5:atom) is semidet.
%! cleaning(-Md5:atom) is nondet.

cleaning(Md5):-
  var(Md5), !,
  with_mutex(lwm_basket, (
    lwm_sparql_select([ll], [md5],
        [rdf(var(md5res),ll:start_clean,var(start_clean)),
         not([rdf(var(md5res),ll:end_clean,var(end_clean))]),
         rdf(var(md5res),ll:md5,var(md5))],
        [[Literal]], [limit(1)]),
    rdf_literal(Literal, Md5, _)
  )).
cleaning(Md5):-
  with_mutex(lwm_basket, (
    lwm_sparql_ask([ll],
        [rdf(var(md5),ll:md5,literal(type(xsd:string,Md5))),
         rdf(var(md5),ll:start_clean,var(end)),
         not([rdf(var(md5),ll:end_clean,var(end))])],
        [])
  )).


%! pending(+Md5:atom) is semidet.
%! pending(-Md5:atom) is nondet.

pending(Md5):-
  var(Md5), !,
  with_mutex(lwm_basket, (
    lwm_sparql_select([ll], [md5],
        [rdf(var(md5res),ll:added,var(added)),
         not([rdf(var(md5res),ll:start_unpack,var(start))]),
         rdf(var(md5res),ll:md5,var(md5))],
        [[Literal]], [limit(1)]),
    rdf_literal(Literal, Md5, _)
  )).
pending(Md5):-
  with_mutex(lwm_basket, (
    lwm_sparql_ask([ll],
        [rdf(var(md5),ll:md5,literal(type(xsd:string,Md5))),
         rdf(var(md5),ll:added,var(added)),
         not([rdf(var(md5),ll:start_unpack,var(start))])], [])
  )).


% pick_pending(-Md5:atom) is det.

pick_pending(Md5):-
  with_mutex(lwm_basket, (
    pending(Md5),
    store_start_unpack(Md5)
  )).


% pick_unpacked(-Md5:atom) is det.

pick_unpacked(Md5):-
  with_mutex(lwm_basket, (
    unpacked(Md5),
    store_start_clean(Md5)
  )).


%! unpacked(+Md5:atom) is semidet.
%! unpacked(-Md5:atom) is nondet.

unpacked(Md5):-
  var(Md5), !,
  with_mutex(lwm_basket, (
    lwm_sparql_select([ll], [md5],
        [rdf(var(md5res),ll:end_unpack,var(start)),
         not([rdf(var(md5res),ll:start_clean,var(clean))]),
         rdf(var(md5res),ll:md5,var(md5))],
        [[Literal]], [limit(1)]),
    rdf_literal(Literal, Md5, _)
  )).
unpacked(Md5):-
  with_mutex(lwm_basket, (
    lwm_sparql_ask([ll],
        [rdf(var(md5),ll:md5,literal(type(xsd:string,Md5))),
         rdf(var(md5),ll:end_unpack,var(start)),
         not([rdf(var(md5res),ll:start_clean,var(clean))])],
        [])
  )).


%! unpacking(+Md5:atom) is semidet.
%! unpacking(-Md5:atom) is nondet.

unpacking(Md5):-
  var(Md5), !,
  with_mutex(lwm_basket, (
    lwm_sparql_select([ll], [md5],
        [rdf(var(md5res),ll:start_unpack,var(start)),
         not([rdf(var(md5res),ll:end_unpack,var(clean))]),
         rdf(var(md5res),ll:md5,var(md5))],
        [[Literal]], [limit(1)]),
    rdf_literal(Literal, Md5, _)
  )).
unpacking(Md5):-
  with_mutex(lwm_basket, (
    lwm_sparql_ask([ll],
        [rdf(var(md5),ll:md5,literal(type(xsd:string,Md5))),
         rdf(var(md5),ll:start_unpack,var(start)),
         not([rdf(var(md5res),ll:end_unpack,var(clean))])],
        [])
  )).
