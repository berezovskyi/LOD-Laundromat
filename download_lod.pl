:- module(
  download_lod,
  [
    download_lod/1, % +Urls:or([iri,list(iri)])
    download_lod/3 % +Directory:or([atom,compound])
                   % +Urls:or([iri,list(iri)])
                   % +NumberOfThreads:nonneg
  ]
).

/** <module> Download LOD

@author Wouter Beek
@version 2014/03-2014/05
*/

:- use_module(library(aggregate)).
:- use_module(library(apply)).
:- use_module(library(http/http_client)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(thread)).

:- use_module(ap(ap_db)). % XML namespace.
:- use_module(generics(db_ext)).
:- use_module(generics(uri_ext)).
:- use_module(os(remote_ext)).
:- use_module(os(unpack)).
:- use_module(pl(pl_log)).
:- use_module(void(void_db)). % XML namespace.
:- use_module(xsd(xsd_dateTime_ext)).

:- use_module(plRdf_ser(rdf_ntriples_write)).
:- use_module(plRdf_ser(rdf_serial)).

:- dynamic(data_directory/1).

:- rdf_meta(store_triple(r,r,o,+)).

%! seen_dataset(?Url:url) is nondet.

:- thread_local(seen_dataset/1).

%! todo_dataset(?Url:url) is nondet.

:- thread_local(todo_dataset/1).

%! failed(?Url:url) is nondet.

:- dynamic(failed/1).

%! finished(?Url:url) is nondet.

:- dynamic(finished/1).

%! rdf_triple(
%!   ?Subject:or([bnode,iri]),
%!   ?Predicate:iri,
%!   ?Object:or([bnode,iri,literal]),
%!   ?DataDocument:url
%! ) is nondet.
% Since threads load data in RDF transactions with snapshots,
% we cannot use the triple store for anything else during
% the load-save cycle of a data document.
% Therefore, we store triples that arise during this cycle
% as thread-specific Prolog assertions.

:- thread_local(rdf_triple/4).

:- db_add_novel(user:prolog_file_type(log, logging)).



download_lod(Iris):-
  absolute_file_name(data(.), DataDir, [access(write),file_type(directory)]),
  download_lod(DataDir, Iris, 1).

%! download_lod(
%!   +DataDirectory:atom,
%!   +Urls:or([iri,list(iri)]),
%!   +NumberOfThreads:nonneg
%! ) is det.

download_lod(DataDir, Iris, N):-
  is_list(Iris), !,

  flag(number_of_processed_files, _, 0),
  flag(number_of_skipped_files, _, 0),
  flag(number_of_triples_written, _, 0),
  read_lod_urls(DataDir),

  % Assert the data directory.
  db_replace_novel(data_directory(DataDir), [e]),

  % IRI -> URI
  maplist(uri_iri, Uris1, Iris),

  % Exclude URIs that were (succesfully or unsuccesfully) processed
  % in the past.
  exclude(finished, Uris1, Uris2),
  exclude(failed, Uris2, Uris3),

  % Process the resources by authority.
  % This avoids being blocked by servers that do not allow
  % multiple simultaneous requests.
  findall(
    Authority-Uri,
    (
      member(Uri, Uris3),
      uri_components(Uri, Components),
      uri_data(authority, Components, Authority)
    ),
    Pairs1
  ),
  group_pairs_by_key(Pairs1, Pairs2),

  % Construct the set of goals that will be distributed accross
  % the given number of treads.
  findall(
    download_lod_authority(DataDir, Pair),
    member(Pair, Pairs2),
    Goals
  ),

  % Each file is loaded in an RDF serialization + snapshot.
  % These inherit the triples that are not in an RDF serialization.
  % We therefore have to clear all such triples before we begin.
  rdf_retractall(_, _, _),

  % Run the goals in threads.
  % The number of threads can be given as an option.
  thread_create(run_goals_in_threads(N, Goals), _, []).
download_lod(DataDir, Iri, N):-
  download_lod(DataDir, [Iri], N).


%! download_lod_authority(
%!   +DataDirectory:compound,
%!   +AuthorityPair:pair(atom,list(pair(atom)))
%! ) is det.
% Downloads the datasets at the given authority.
%
% An authority is represented as a pair of an authority name
% and a list of CKAN resources that -- according to the metadata --
% reside at that authority.

% Skip the first N authorities.
download_lod_authority(DataDir, _-Urls):-
  forall(
    member(Url, Urls),
    (
      % Add another LOD input to the pool.
      register_input(Url),
      download_lod_files(DataDir)
    )
  ).


%! download_lod_files(+DataDirectory:or([atom,compound])) is det.
% We log the status, all warnings, and all informational messages
% that are emitted while processing a file.

download_lod_files(DataDir):-
  % Take another LOD input from the pool.
  pick_input(Url), !,
  store_triple(Url, rdf:type, ap:'LOD-URL', ap),
  store_triple(Url, ap:scrape_version, literal(type(xsd:integer,6)), ap),
  get_dateTime(DateTime),
  store_triple(Url, ap:scrape_date, literal(type(xsd:dateTime,DateTime)), ap),

  run_collect_messages(
    download_lod_file(Url, DataDir, OldStatus),
    Status,
    Messages
  ),
  log_status(Url, Status),
  maplist(log_message(Url), Messages),

  print_message(
    informational,
    lod_skipped_file(Url,OldStatus,Status,Messages)
  ),

  write_lod_url(finished, Url),

  download_lod_files(DataDir).
% No more inputs to pick.
download_lod_files(_).


%! download_lod_file(
%!   +Url:url,
%!   +DataDirectory:or([atom,compound]),
%!   -Status:oneof([false,true])
%! ) is det.

download_lod_file(Url0, DataDir, Status):-
  % NON-DETERMINISTIC for multiple entries in one archive stream.
  unpack(Url0, Read, Location),

  store_location_properties(Url0, Location, Url),

  print_message(informational, lod_download_start(X,Url)),

  % Make sure the remote directory exists.
  url_flat_directory(DataDir, Url, UrlDir),
  make_remote_directory_path(UrlDir),
  % Clear any previous, incomplete results.
  clear_remote_directory(UrlDir),

  % Process individual RDF files in a separate RDF transaction and snapshot.
  run_collect_messages(
    call_cleanup(
      rdf_transaction(
        download_lod_file_transaction(Url, Read, UrlDir, Location),
        _,
        [snapshot(true)]
      ),
      (
        store_stream_properties(Url, Read),
        close(Read)
      )
    ),
    Status,
    Messages
  ),
  (
    Status == false
  -> !,
    post_rdf_triples
  ;
    log_status(Url, Status),
    maplist(log_message(Url), Messages),
    print_message(informational, lod_downloaded_file(Url,X,Status,Messages)),

    post_rdf_triples,

    % Unpack the next entry by backtracking.
    fail
  ).
download_lod_file(_, _, true).


%! download_lod_file_transaction(
%!   +Url:url,
%!   +Read:stream,
%!   +UrlDirectory:atom,
%!   +Location:dict
%! ) is det.

download_lod_file_transaction(Url, Read, UrlDir, Location):-
  % Guess the serialization format that is used in the given stream.
  rdf_guess_format([], Read, Location, Base, Format),
  store_triple(Url, ap:serialization_format, literal(type(xsd:string,Format)), ap),
  set_stream(Read, file_name(Base)),
  %%%%store_triple(Url, ap:base_iri, Base, ap),

  % Load triples in any serialization format.
  rdf_load(
    stream(Read),
    [base_uri(Base),format(Format),register_namespaces(false)]
  ),
  % Count the number of triples including duplicates
  % (in between loading and saving the data).
  aggregate_all(
    count,
    rdf(_, _, _, _),
    TIn
  ),

  % Save triples using the N-Triples serialization format.
  directory_file_path(UrlDir, 'input.nt.gz', Path),
  setup_call_cleanup(
    remote_open(Path, append, Write, [filter(gzip)]),
    rdf_ntriples_write(Write, [bnode_base(Base),number_of_triples(TOut)]),
    close(Write)
  ),

  % Asssert some statistics for inclusion in the messages file.
  assert_number_of_triples(Url, Path, TIn, TOut),
  store_void_triples(Url),

  % Make sure any VoID datadumps are considered as well.
  register_void_datasets.



% HELPERS

%! assert_number_of_triples(
%!   +Url:url,
%!   +Path:atom,
%!   +ReadTriples:nonneg,
%!   +WrittenTriples:nonneg
%! ) is det.

assert_number_of_triples(Url, Path, TIn, TOut):-
  store_triple(Url, ap:triples, literal(type(xsd:integer,TOut)), ap),
  TDup is TIn - TOut,
  store_triple(Url, ap:duplicates, literal(type(xsd:integer,TDup)), ap),
  print_message(informational, rdf_ntriples_written(Path,TDup,TOut)).


%! read_lod_urls(+DataDirectory:atom) is det.

read_lod_urls(DataDir):-
  read_lod_urls(failed, DataDir),
  read_lod_urls(finished, DataDir).


%! read_lod_urls(+Kind:oneof([failed,finished]), +DataDirectory:atom) is det.

read_lod_urls(Kind, DataDir):-
  absolute_file_name(
    Kind,
    File,
    [access(read),file_errors(fail),file_type(logging),relative_to(DataDir)]
  ), !,
  ensure_loaded(File).
read_lod_urls(_, _).


%! log_message(+Dataset:iri, +Message:compound) is det.

log_message(Dataset, Message):-
  with_output_to(atom(String), write_canonical_blobs(Message)),
  store_triple(Dataset, ap:message, literal(type(xsd:string,String)), ap).


%! log_status(+Dataset:iri, +Exception:compound) is det.

log_status(_, false):- !.
log_status(_, true):- !.
log_status(Dataset, exception(Error)):-
  with_output_to(atom(String), write_canonical_blobs(Error)),
  store_triple(Dataset, ap:exception, literal(type(xsd:string,String)), ap).


%! pick_input(-Url:url) is nondet.

pick_input(Url):-
  retract(todo_dataset(Url)).


%! post_rdf_triples is det.

post_rdf_triples:-
  sparql_update_url(Url),
  setup_call_cleanup(
    forall(
      rdf_triple(S, P, O, _),
      rdf_assert(S, P, O)
    ),
    (
      with_output_to(codes(Codes), sparql_insert_data([])),
atom_codes(Atom, Codes), %DEB
format(user_output, '~w~n', [Atom]), %DEB
      http_post(
        Url,
        codes('application/sparql-update', Codes),
        Reply,
        []
      ),
      format(user_output, '~w~n', [Reply])
    ),
    (
      rdf_retractall(_, _, _),
      retractall(rdf_triple(_, _, _, _))
    )
  ).

sparql_update_url(Url):-
  uri_components(
    Url,
    uri_components(
      http,
      'stardog.lodlaundromat.ops.few.vu.nl',
      '/laundromat/update',
      _,
      _
    )
  ).


%! register_input(+Url:url) is det.

register_input(Url):-
  assert(todo_dataset(Url)),
  assert(seen_dataset(Url)).


%! register_void_datasets is det.

register_void_datasets:-
  % Add all VoID datadumps to the TODO list.
  aggregate_all(
    set(Url),
    (
      rdf(_, void:dataDump, Url),
      \+ seen_dataset(Url)
    ),
    Urls
  ),
  print_message(informational, found_void_lod_urls(Urls)),
  forall(
    member(Url, Urls),
    register_input(Url)
  ).


%! run_goals_in_threads(+NumberOfThreads:nonneg, :Goals) is det.

run_goals_in_threads(N, Goals):-
  N > 1, !,
  concurrent(N, Goals, []).
run_goals_in_threads(_, Goals):-
  maplist(call, Goals).


%! store_location_properties(+Url1:url, +Location:dict, -Url2:url) is det.

store_location_properties(Url1, Location, Url2):-
  (
    Data1 = Location.get(data),
    exclude(filter, Data1, Data2),
    last(Data2, ArchiveEntry)
  ->
    Name = ArchiveEntry.get(name),
    atomic_list_concat([Url1,Name], '/', Url2),
    store_triple(Url1, ap:archive_contains, Url2, ap),
    ignore(store_triple(Url2, ap:format,
        literal(type(xsd:string,ArchiveEntry.get(format))), ap)),
    ignore(store_triple(Url2, ap:size,
        literal(type(xsd:integer,ArchiveEntry.get(size))), ap)),
    store_triple(Url2, rdf:type, ap:'LOD-URL', ap)
  ;
    Url2 = Url1
  ),
  ignore(store_triple(Url2, ap:http_content_type,
      literal(type(xsd:string,Location.get(content_type))), ap)),
  ignore(store_triple(Url2, ap:http_content_length,
      literal(type(xsd:integer,Location.get(content_length))), ap)),
  ignore(store_triple(Url2, ap:http_last_modified,
      literal(type(xsd:string,Location.get(last_modified))), ap)),
  store_triple(Url2, ap:url, literal(type(xsd:string,Location.get(url))), ap),

  (
    location_base(Location, Base),
    file_name_extension(_, Ext, Base),
    Ext \== ''
  ->
    store_triple(Url2, ap:file_extension, literal(type(xsd:string,Ext)), ap)
  ;
    true
  ).
filter(filter(_)).


%! store_stream_properties(+Url:url, +Stream:stream) is det.

store_stream_properties(Url, Stream):-
  stream_property(Stream, position(Position)),
  forall(
    stream_position_data(Field, Position, Value),
    (
      atomic_list_concat([stream,Field], '_', Name),
      rdf_global_id(ap:Name, Predicate),
      store_triple(Url, Predicate, literal(type(xsd:integer,Value)), ap)
    )
  ).


%! store_triple(
%!   +Subject:or([bnode,iri]),
%!   +Predicate:iri,
%!   +Object:or([bnode,iri,literal]),
%!   +Graph:atom
%! ) is det.

store_triple(S, P, O, G):-
  assert(rdf_triple(S, P, O, G)).


%! store_void_triples(+DataDocument:url) is det.

store_void_triples(DataDocument):-
  aggregate_all(
    set(P),
    (
      rdf_current_predicate(P),
      rdf_global_id(void:_, P)
    ),
    Ps
  ),
  forall(
    (
      member(P, Ps),
      rdf(S, P, O)
    ),
    store_triple(S, P, O, DataDocument)
  ).


%! write_lod_url(+Kind:oneof([failed,finished]), +Dataset:atom) is det.

write_lod_url(Kind, Url):-
  with_mutex(
    Kind,
    (
      data_directory(DataDir),
      absolute_file_name(
        Kind,
        File,
        [access(write),file_type(logging),relative_to(DataDir)]
      ),
      setup_call_cleanup(
        open(File, append, Stream),
        (
          Term =.. [Kind,Url],
          writeq(Stream, Term),
          write(Stream, '.'),
          nl(Stream)
        ),
        close(Stream)
      )
    )
  ).



% MESSAGES

:- multifile(prolog:message/1).

prolog:message(found_void_lod_urls([])) --> !.
prolog:message(found_void_lod_urls([H|T])) -->
  ['[VoID] Found: ',H,nl],
  prolog:message(found_void_lod_urls(T)).

prolog:message(lod_download_start(X,Url)) -->
  {flag(number_of_processed_files, X, X + 1)},
  ['[START ~D] [~w]'-[X,Url]].

prolog:message(lod_downloaded_file(Url,X,Status,Messages)) -->
  prolog_status(Status, Url),
  prolog_messages(Messages),
  ['[DONE ~D]'-[X]],
  [nl,nl].

prolog:message(lod_skipped_file(_,true,_,_)) --> !, [].
prolog:message(lod_skipped_file(Url,false,_,_)) --> !,
  {write_lod_url(failed, Url)},
  [].
prolog:message(lod_skipped_file(Url,_,Status,Messages)) -->
  {flag(number_of_skipped_files, X, X + 1)},
  ['[SKIP ~D] '-[X],nl],
  prolog_status(Status, Url),
  prolog_messages(Messages).

prolog:message(rdf_ntriples_written(File,TDup,TOut)) -->
  ['['],
    number_of_triples_written(TOut),
    number_of_duplicates_written(TDup),
    total_number_of_triples_written(TOut),
  ['] ['],
    remote_file(File),
  [']'].

number_of_duplicates_written(0) --> !, [].
number_of_duplicates_written(T) --> [' (~D dups)'-[T]].

number_of_triples_written(0) --> !, [].
number_of_triples_written(T) --> ['+~D'-[T]].

prolog_status(false, Url) --> !,
  {write_lod_url(failed, Url)},
  [].
prolog_status(true, _) --> !, [].
prolog_status(exception(Error), _) -->
  {print_message(error, Error)}.

prolog_messages([]) --> !, [].
prolog_messages([message(_,Kind,Lines)|T]) -->
  ['  [~w] '-[Kind]],
  prolog_lines(Lines),
  [nl],
  prolog_messages(T).

prolog_lines([]) --> [].
prolog_lines([H|T]) -->
  [H],
  prolog_lines(T).

remote_file(remote(User,Machine,Path)) --> !,
  [User,'@',Machine,':',Path].
remote_file(File) -->
  [File].

total_number_of_triples_written(0) --> !, [].
total_number_of_triples_written(T) -->
  {
    with_mutex(
      number_of_triples_written,
      (
        flag(number_of_triples_written, All1, All1 + T),
        All2 is All1 + T
      )
    )
  },
  [' (~D tot)'-[All2]].
