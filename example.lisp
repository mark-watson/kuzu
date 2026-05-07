;;;; Kuzu Graph Database — Common Lisp Demo Example
;;;; ==================================================
;;;; This script demonstrates using Kuzu's C API from Common Lisp
;;;; via CFFI.  It mirrors the queries in example.py: creates a
;;;; database, defines a schema, loads CSV data, and runs several
;;;; Cypher queries.
;;;;
;;;; Prerequisites:
;;;;   1. Build the shared library + CFFI wrapper:
;;;;        make release
;;;;        make cffi-wrapper
;;;;   2. Install SBCL and Quicklisp (with cffi)
;;;;
;;;; Run:
;;;;   sbcl --load example.lisp

(require :asdf)
(asdf:load-system :cffi)

(defpackage #:kuzu-example
  (:use #:cl #:cffi))

(in-package #:kuzu-example)

;;; ── Library paths ─────────────────────────────────────────────────

(defvar *base-dir*
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "KUZU_HOME")
       (error "KUZU_HOME environment variable is not set"))))

(define-foreign-library libkuzu
  (:darwin (:or #.(namestring
                   (merge-pathnames "build/release/src/libkuzu.dylib" *base-dir*))))
  (:unix  "libkuzu.so")
  (t      "libkuzu"))

;; Thin C wrapper that converts struct-by-value calls to pointer-based
;; calls, avoiding cffi-libffi dependency.
(define-foreign-library libkuzu-cffi
  (:darwin (:or #.(namestring
                   (merge-pathnames "build/release/src/libkuzu_cffi.dylib" *base-dir*))))
  (:unix  "libkuzu_cffi.so")
  (t      "libkuzu_cffi"))

(use-foreign-library libkuzu)
(use-foreign-library libkuzu-cffi)

;;; ── Struct definitions ────────────────────────────────────────────

(defcstruct kuzu-database
  (_database :pointer))

(defcstruct kuzu-connection
  (_connection :pointer))

(defcstruct kuzu-query-result
  (_query-result :pointer)
  (_is-owned-by-cpp :bool))

(defcstruct kuzu-flat-tuple
  (_flat-tuple :pointer)
  (_is-owned-by-cpp :bool))

(defcstruct kuzu-value
  (_value :pointer)
  (_is-owned-by-cpp :bool))

(defcstruct kuzu-system-config
  (buffer-pool-size   :uint64)
  (max-num-threads    :uint64)
  (enable-compression :bool)
  (read-only          :bool)
  (max-db-size        :uint64)
  (auto-checkpoint    :bool)
  (checkpoint-threshold :uint64)
  #+darwin (thread-qos :uint32))

;;; ── Foreign function bindings ─────────────────────────────────────

;; Pointer-based wrappers (from kuzu_cffi_wrapper.c)
(defcfun ("kuzu_default_system_config_ptr" %default-system-config) :void
  (out-config :pointer))

(defcfun ("kuzu_database_init_ptr" %database-init) :int
  (database-path :string)
  (config        :pointer)
  (out-database  :pointer))

;; Direct C API bindings (all pointer-based, no struct-by-value)
(defcfun ("kuzu_database_destroy" kuzu-database-destroy) :void
  (database :pointer))

(defcfun ("kuzu_connection_init" %connection-init) :int
  (database       :pointer)
  (out-connection :pointer))

(defcfun ("kuzu_connection_destroy" kuzu-connection-destroy) :void
  (connection :pointer))

(defcfun ("kuzu_connection_query" %connection-query) :int
  (connection       :pointer)
  (query            :string)
  (out-query-result :pointer))

(defcfun ("kuzu_query_result_destroy" kuzu-query-result-destroy) :void
  (query-result :pointer))

(defcfun ("kuzu_query_result_is_success" kuzu-query-result-is-success) :bool
  (query-result :pointer))

(defcfun ("kuzu_query_result_get_error_message"
          kuzu-query-result-get-error-message) :pointer
  (query-result :pointer))

(defcfun ("kuzu_query_result_has_next" kuzu-query-result-has-next) :bool
  (query-result :pointer))

(defcfun ("kuzu_query_result_get_next" %query-result-get-next) :int
  (query-result   :pointer)
  (out-flat-tuple :pointer))

(defcfun ("kuzu_query_result_to_string" %query-result-to-string) :pointer
  (query-result :pointer))

(defcfun ("kuzu_flat_tuple_get_value" %flat-tuple-get-value) :int
  (flat-tuple :pointer)
  (index      :uint64)
  (out-value  :pointer))

(defcfun ("kuzu_value_get_string" %value-get-string) :int
  (value      :pointer)
  (out-result :pointer))

(defcfun ("kuzu_value_get_int64" %value-get-int64) :int
  (value      :pointer)
  (out-result :pointer))

(defcfun ("kuzu_destroy_string" kuzu-destroy-string) :void
  (str :pointer))

(defcfun ("kuzu_get_version" kuzu-get-version) :string)

;;; ── Helpers ───────────────────────────────────────────────────────

(defun check (state context)
  "Signal an error if STATE is not 0 (KuzuSuccess)."
  (unless (zerop state)
    (error "Kuzu error during ~A (state=~D)" context state)))

(defun copy-foreign-bytes (dst src n)
  "Copy N bytes from foreign pointer SRC to DST."
  (dotimes (i n)
    (setf (mem-ref dst :uint8 i) (mem-ref src :uint8 i))))

(defun execute (conn cypher)
  "Execute a Cypher statement and return a heap-allocated query-result
pointer.  Caller must call DESTROY-RESULT to free it."
  (with-foreign-object (qr '(:struct kuzu-query-result))
    (setf (foreign-slot-value qr '(:struct kuzu-query-result) '_query-result)
          (null-pointer))
    (setf (foreign-slot-value qr '(:struct kuzu-query-result) '_is-owned-by-cpp)
          nil)
    (check (%connection-query conn cypher qr)
           (format nil "query: ~A" cypher))
    (unless (kuzu-query-result-is-success qr)
      (let ((msg-ptr (kuzu-query-result-get-error-message qr)))
        (let ((msg (if (null-pointer-p msg-ptr) "unknown"
                       (foreign-string-to-lisp msg-ptr))))
          (unless (null-pointer-p msg-ptr) (kuzu-destroy-string msg-ptr))
          (kuzu-query-result-destroy qr)
          (error "Kuzu query error: ~A" msg))))
    ;; Copy struct to heap so it survives WITH-FOREIGN-OBJECT scope
    (let* ((sz (foreign-type-size '(:struct kuzu-query-result)))
           (result (foreign-alloc :uint8 :count sz)))
      (copy-foreign-bytes result qr sz)
      result)))

(defun destroy-result (qr)
  "Destroy a query result and free the foreign memory."
  (kuzu-query-result-destroy qr)
  (foreign-free qr))

(defun result-to-string (qr)
  "Convert a query result to a Lisp string."
  (let ((ptr (%query-result-to-string qr)))
    (prog1 (foreign-string-to-lisp ptr)
      (kuzu-destroy-string ptr))))

(defun get-string-value (val-ptr)
  "Extract a STRING typed value as a Lisp string."
  (with-foreign-object (str-ptr :pointer)
    (check (%value-get-string val-ptr str-ptr) "get_string")
    (let ((s (foreign-string-to-lisp (mem-ref str-ptr :pointer))))
      (kuzu-destroy-string (mem-ref str-ptr :pointer))
      s)))

(defun get-int64-value (val-ptr)
  "Extract an INT64 typed value as a Lisp integer."
  (with-foreign-object (out :int64)
    (check (%value-get-int64 val-ptr out) "get_int64")
    (mem-ref out :int64)))

;;; ── Main demo ─────────────────────────────────────────────────────

(defun main ()
  (let ((db-path "example_db_lisp"))

    ;; Clean up any previous run
    (when (uiop:directory-exists-p db-path)
      (uiop:delete-directory-tree
       (truename (pathname (format nil "~A/" db-path))) :validate t))

    (format t "Kuzu version: ~A~%~%" (kuzu-get-version))

    ;; ── Create database and connection ─────────────────────────────
    (with-foreign-objects ((cfg  '(:struct kuzu-system-config))
                           (db   '(:struct kuzu-database))
                           (conn '(:struct kuzu-connection)))
      (%default-system-config cfg)
      (check (%database-init db-path cfg db) "database_init")
      (format t "✓ Created Kuzu database at ./~A~%~%" db-path)

      (check (%connection-init db conn) "connection_init")

      ;; ── Define schema ────────────────────────────────────────────
      (dolist (ddl '("CREATE NODE TABLE User(name STRING, age INT64, PRIMARY KEY (name))"
                     "CREATE NODE TABLE City(name STRING, population INT64, PRIMARY KEY (name))"
                     "CREATE REL TABLE Follows(FROM User TO User, since INT64)"
                     "CREATE REL TABLE LivesIn(FROM User TO City)"))
        (destroy-result (execute conn ddl)))
      (format t "✓ Schema created (User, City, Follows, LivesIn)~%~%")

      ;; ── Load data from bundled CSV files ─────────────────────────
      (let ((csv-dir (namestring
                      (merge-pathnames "dataset/demo-db/csv/" *base-dir*))))
        (dolist (stmt
                 (list (format nil "COPY User FROM \"~Auser.csv\""       csv-dir)
                       (format nil "COPY City FROM \"~Acity.csv\""       csv-dir)
                       (format nil "COPY Follows FROM \"~Afollows.csv\"" csv-dir)
                       (format nil "COPY LivesIn FROM \"~Alives-in.csv\"" csv-dir)))
          (destroy-result (execute conn stmt)))
        (format t "✓ Loaded demo data from ~A~%~%" csv-dir))

      ;; ── Query 1: List all users ──────────────────────────────────
      (format t "─── All Users ───────────────────────────────────────────~%")
      (let ((qr (execute conn
                  "MATCH (u:User) RETURN u.name AS name, u.age AS age ORDER BY u.name")))
        (with-foreign-objects ((tuple '(:struct kuzu-flat-tuple))
                               (val   '(:struct kuzu-value)))
          (loop while (kuzu-query-result-has-next qr) do
            (check (%query-result-get-next qr tuple) "get_next")
            (check (%flat-tuple-get-value tuple 0 val) "get_value 0")
            (let ((name (get-string-value val)))
              (check (%flat-tuple-get-value tuple 1 val) "get_value 1")
              (format t "  ~A (age ~D)~%" name (get-int64-value val)))))
        (destroy-result qr))
      (terpri)

      ;; ── Query 2: Who follows whom? ──────────────────────────────
      (format t "─── Follow Relationships ────────────────────────────────~%")
      (let ((qr (execute conn
                  (concatenate 'string
                    "MATCH (a:User)-[f:Follows]->(b:User) "
                    "RETURN a.name AS follower, b.name AS followee, f.since AS since "
                    "ORDER BY f.since"))))
        (with-foreign-objects ((tuple '(:struct kuzu-flat-tuple))
                               (val   '(:struct kuzu-value)))
          (loop while (kuzu-query-result-has-next qr) do
            (check (%query-result-get-next qr tuple) "get_next")
            (check (%flat-tuple-get-value tuple 0 val) "get_value 0")
            (let ((follower (get-string-value val)))
              (check (%flat-tuple-get-value tuple 1 val) "get_value 1")
              (let ((followee (get-string-value val)))
                (check (%flat-tuple-get-value tuple 2 val) "get_value 2")
                (format t "  ~A → ~A (since ~D)~%"
                        follower followee (get-int64-value val))))))
        (destroy-result qr))
      (terpri)

      ;; ── Query 3: Where does everyone live? ──────────────────────
      (format t "─── Residence ───────────────────────────────────────────~%")
      (let ((qr (execute conn
                  (concatenate 'string
                    "MATCH (u:User)-[:LivesIn]->(c:City) "
                    "RETURN u.name AS person, c.name AS city, c.population AS pop "
                    "ORDER BY u.name"))))
        (with-foreign-objects ((tuple '(:struct kuzu-flat-tuple))
                               (val   '(:struct kuzu-value)))
          (loop while (kuzu-query-result-has-next qr) do
            (check (%query-result-get-next qr tuple) "get_next")
            (check (%flat-tuple-get-value tuple 0 val) "get_value 0")
            (let ((person (get-string-value val)))
              (check (%flat-tuple-get-value tuple 1 val) "get_value 1")
              (let ((city (get-string-value val)))
                (check (%flat-tuple-get-value tuple 2 val) "get_value 2")
                (format t "  ~A lives in ~A (pop. ~:D)~%"
                        person city (get-int64-value val))))))
        (destroy-result qr))
      (terpri)

      ;; ── Query 4: 2-hop follows from Adam ────────────────────────
      (format t "─── 2-Hop Follows from Adam ─────────────────────────────~%")
      (let ((qr (execute conn
                  (concatenate 'string
                    "MATCH (a:User)-[:Follows]->(b:User)-[:Follows]->(c:User) "
                    "WHERE a.name = 'Adam' "
                    "RETURN a.name AS start, b.name AS mid, c.name AS dest"))))
        (with-foreign-objects ((tuple '(:struct kuzu-flat-tuple))
                               (val   '(:struct kuzu-value)))
          (loop while (kuzu-query-result-has-next qr) do
            (check (%query-result-get-next qr tuple) "get_next")
            (check (%flat-tuple-get-value tuple 0 val) "get_value 0")
            (let ((s (get-string-value val)))
              (check (%flat-tuple-get-value tuple 1 val) "get_value 1")
              (let ((m (get-string-value val)))
                (check (%flat-tuple-get-value tuple 2 val) "get_value 2")
                (format t "  ~A → ~A → ~A~%" s m (get-string-value val))))))
        (destroy-result qr))
      (terpri)

      ;; ── Query 5: Shortest path ──────────────────────────────────
      ;; Recursive-rel types are complex to destructure via the C API,
      ;; so we use the built-in to_string for display.
      (format t "─── Shortest Path: Adam → Noura ─────────────────────────~%")
      (let ((qr (execute conn
                  (concatenate 'string
                    "MATCH p = (a:User)-[:Follows* SHORTEST 1..10]->(b:User) "
                    "WHERE a.name = 'Adam' AND b.name = 'Noura' "
                    "RETURN nodes(p), length(p) AS hops"))))
        (format t "~A" (result-to-string qr))
        (destroy-result qr))
      (terpri)

      ;; ── Cleanup ──────────────────────────────────────────────────
      (kuzu-connection-destroy conn)
      (kuzu-database-destroy db))

    ;; Remove the database directory
    (when (uiop:directory-exists-p db-path)
      (uiop:delete-directory-tree
       (truename (pathname (format nil "~A/" db-path))) :validate t))
    (format t "✓ Cleaned up ~A. Done!~%" db-path)))

;; Run when loaded
(main)
