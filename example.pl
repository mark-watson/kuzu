%% Kuzu Graph Database — SWI-Prolog Demo Example
%% ================================================
%% This script demonstrates using Kuzu's C API from SWI-Prolog
%% via a thin foreign-language bridge (kuzu_swi.c).  It mirrors
%% the queries in example.py, example.lisp, and example.ts:
%% creates a database, defines a schema, loads CSV data, and
%% runs several Cypher queries.
%%
%% Prerequisites:
%%   1. Build the shared library + SWI-Prolog bridge:
%%        make swi-prolog
%%   2. SWI-Prolog 9+ installed (tested with 10.0.2)
%%
%% Run:
%%     swipl example.pl

:- use_module(library(filesex)).
:- use_module(library(process)).

%% ── Load foreign library ──────────────────────────────────────────
%% The kuzu_swi shared library lives in build/release/src/.

:- load_foreign_library('build/release/src/kuzu_swi').

%% ── Helpers ───────────────────────────────────────────────────────

%% execute(+Conn, +Cypher)
%%   Run a Cypher statement and discard the result.
execute(Conn, Cypher) :-
    kuzu_query(Conn, Cypher, Result),
    kuzu_destroy_result(Result).

%% print_rows(+Result, +Formatter)
%%   Iterate all rows of a query result, calling Formatter(Result)
%%   for each row.
print_rows(Result, Formatter) :-
    (   kuzu_result_has_next(Result)
    ->  kuzu_result_next_row(Result),
        call(Formatter, Result),
        print_rows(Result, Formatter)
    ;   true
    ).

%% ── Row formatters ────────────────────────────────────────────────

format_user(Result) :-
    kuzu_get_value(Result, 0, Name),
    kuzu_get_value(Result, 1, Age),
    format("  ~w (age ~w)~n", [Name, Age]).

format_follows(Result) :-
    kuzu_get_value(Result, 0, Follower),
    kuzu_get_value(Result, 1, Followee),
    kuzu_get_value(Result, 2, Since),
    format("  ~w → ~w (since ~w)~n", [Follower, Followee, Since]).

format_residence(Result) :-
    kuzu_get_value(Result, 0, Person),
    kuzu_get_value(Result, 1, City),
    kuzu_get_value(Result, 2, Pop),
    format("  ~w lives in ~w (pop. ~w)~n", [Person, City, Pop]).

format_2hop(Result) :-
    kuzu_get_value(Result, 0, S),
    kuzu_get_value(Result, 1, M),
    kuzu_get_value(Result, 2, D),
    format("  ~w → ~w → ~w~n", [S, M, D]).

%% ── Main demo ─────────────────────────────────────────────────────

main :-
    DbPath = 'example_db_pl',

    %% Clean up any previous run (rm -rf handles files and directories)
    atom_string(DbPath, DbPathStr),
    (   (exists_file(DbPath) ; exists_directory(DbPath))
    ->  process_create(path(rm), ['-rf', DbPathStr], [process(Pid)]),
        process_wait(Pid, _)
    ;   true
    ),

    %% Print version
    kuzu_version(Version),
    format("Kuzu version: ~w~n~n", [Version]),

    %% Create database and connection
    kuzu_open_db(DbPath, Db),
    format("✓ Created Kuzu database at ./~w~n~n", [DbPath]),
    kuzu_open_conn(Db, Conn),

    %% Define schema
    execute(Conn, "CREATE NODE TABLE User(name STRING, age INT64, PRIMARY KEY (name))"),
    execute(Conn, "CREATE NODE TABLE City(name STRING, population INT64, PRIMARY KEY (name))"),
    execute(Conn, "CREATE REL TABLE Follows(FROM User TO User, since INT64)"),
    execute(Conn, "CREATE REL TABLE LivesIn(FROM User TO City)"),
    format("✓ Schema created (User, City, Follows, LivesIn)~n~n", []),

    %% Load data from bundled CSV files
    working_directory(Cwd, Cwd),
    atom_concat(Cwd, 'dataset/demo-db/csv/', CsvDir),
    atomic_list_concat(['COPY User FROM "',    CsvDir, 'user.csv"'],    CopyUser),
    atomic_list_concat(['COPY City FROM "',    CsvDir, 'city.csv"'],    CopyCity),
    atomic_list_concat(['COPY Follows FROM "', CsvDir, 'follows.csv"'], CopyFollows),
    atomic_list_concat(['COPY LivesIn FROM "', CsvDir, 'lives-in.csv"'], CopyLivesIn),
    execute(Conn, CopyUser),
    execute(Conn, CopyCity),
    execute(Conn, CopyFollows),
    execute(Conn, CopyLivesIn),
    format("✓ Loaded demo data from ~w~n~n", [CsvDir]),

    %% Query 1: List all users
    format("─── All Users ───────────────────────────────────────────~n", []),
    kuzu_query(Conn,
        "MATCH (u:User) RETURN u.name AS name, u.age AS age ORDER BY u.name",
        R1),
    print_rows(R1, format_user),
    kuzu_destroy_result(R1),
    nl,

    %% Query 2: Who follows whom?
    format("─── Follow Relationships ────────────────────────────────~n", []),
    kuzu_query(Conn,
        "MATCH (a:User)-[f:Follows]->(b:User) RETURN a.name AS follower, b.name AS followee, f.since AS since ORDER BY f.since",
        R2),
    print_rows(R2, format_follows),
    kuzu_destroy_result(R2),
    nl,

    %% Query 3: Where does everyone live?
    format("─── Residence ───────────────────────────────────────────~n", []),
    kuzu_query(Conn,
        "MATCH (u:User)-[:LivesIn]->(c:City) RETURN u.name AS person, c.name AS city, c.population AS pop ORDER BY u.name",
        R3),
    print_rows(R3, format_residence),
    kuzu_destroy_result(R3),
    nl,

    %% Query 4: 2-hop follows from Adam
    format("─── 2-Hop Follows from Adam ─────────────────────────────~n", []),
    kuzu_query(Conn,
        "MATCH (a:User)-[:Follows]->(b:User)-[:Follows]->(c:User) WHERE a.name = 'Adam' RETURN a.name AS start, b.name AS mid, c.name AS dest",
        R4),
    print_rows(R4, format_2hop),
    kuzu_destroy_result(R4),
    nl,

    %% Query 5: Shortest path (use result_to_string for complex types)
    format("─── Shortest Path: Adam → Noura ─────────────────────────~n", []),
    kuzu_query(Conn,
        "MATCH p = (a:User)-[:Follows* SHORTEST 1..10]->(b:User) WHERE a.name = 'Adam' AND b.name = 'Noura' RETURN nodes(p), length(p) AS hops",
        R5),
    kuzu_result_to_string(R5, PathStr),
    format("~w", [PathStr]),
    kuzu_destroy_result(R5),

    %% Cleanup
    kuzu_close_conn(Conn),
    kuzu_close_db(Db),
    (   (exists_file(DbPath) ; exists_directory(DbPath))
    ->  atom_string(DbPath, DbPathStr2),
        process_create(path(rm), ['-rf', DbPathStr2], [process(Pid2)]),
        process_wait(Pid2, _)
    ;   true
    ),
    format("✓ Cleaned up ~w. Done!~n", [DbPath]),
    halt.

:- main.
