% Debug file for the llWashingMachine project.


:- use_module(library(debug)).

% PLC
:- debug(list_script).

% plSparql
%:- debug(sparql_graph_store).
%:- debug(sparql_update).

% Show idle looping on threads.
%:- debug(lwm_idle_loop(clean_large)).
%:- debug(lwm_idle_loop(clean_medium)).
%:- debug(lwm_idle_loop(clean_small)).
%:- debug(lwm_idle_loop(unpack)).

% Show progress.
:- debug(lwm_progress(clean_large)).
:- debug(lwm_progress(clean_medium)).
:- debug(lwm_progress(clean_small)).
:- debug(lwm_progress(unpack)).

:- debug(lwm_restart).
:- debug(lwm_seedpoint).
:- debug(lwm_unpack).

:- [load].


:- use_module(debug_project).
%:- debug_all_files.


% Debugging specific data documents, based on their MD5.

:- dynamic(debug:debug_md5/2).
:- multifile(debug:debug_md5/2).

debug:debug_md5('2721b133d3b0ede8950a30971d536481', unpack).
debug:debug_md5('32814bc748dd6e90244a9a2018132ea0', unpack).
debug:debug_md5('3ee5a3f4b758e0fa5d487a4495484cd2', unpack).
debug:debug_md5('531c0106e2a3b0afe97035f41135f7eb', unpack).
debug:debug_md5('8ecf4770e677bbe29d0aaee9dcb4cf9f', unpack).

show_idle:-
  flag(number_of_idle_loops_clean_small, Small, Small),
  flag(number_of_idle_loops_clean_medium, Medium, Medium),
  flag(number_of_idle_loops_clean_large, Large, Large),
  format(
    user_output,
    'Idle loops:\n  - Small: ~D\n  - Medium: ~D\n  - Large: ~D\n',
    [Small,Medium,Large]
  ).


:- use_module(lwm(lwm_reset)).
:- use_module(lwm(debug/debug_datadoc)).
:- use_module(lwm(debug/debug_query)).

