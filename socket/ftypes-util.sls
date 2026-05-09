;; ftypes util functions for Chez scheme.
;; Written by Jerry 2019-2021.
;; SPDX-License-Identifier: Unlicense

;; Use the chezscheme reader due to #% primitive access.
#!chezscheme
(library (ufo-socket socket ftypes-util)
  (export
   alloc
   c-function c-default-function c-enum c-bitmap
   call-procedure/errno
   locate-library-object
   get-errno-proc
   define-enum
   define-bits
   )
  (import
   (chezscheme))

  ;; [syntax] define-enum: generates a syntax transformer that evaluates the value of an enum at compile time.
  (define-syntax define-enum
    (syntax-rules ()
      [(_ group (var* val*) ...)
       (define-syntax group
         (lambda (x)
           (syntax-case x ()
             [(_ v)
              (eq? (datum v) (syntax->datum #'var*))
              #'val*] ...)))]))

  ;; [syntax] define-bits: creates a syntax generator that bitwise ORs provided flags at compile time.
  (define-syntax define-bits
    (syntax-rules ()
      [(_ group (var* val*) ...)
       (define-syntax group
         (lambda (x)
           (define (sym->bits sym)
             (case sym
               [var* val*]
               ...
               [else
                 (error 'group "invalid value" sym)]))
           (...
             (syntax-case x ()
               [(_ v ...)
                (with-syntax ([bits (apply bitwise-ior (map sym->bits (syntax->datum #'(v ...))))])
                  #'bits)]))))]))

  ;; [syntax] (alloc ((var varptr type)) ...)
  ;; Exception-safe foreign memory allocation using dynamic-wind.
  (define-syntax alloc
    (syntax-rules ()
      [(_ ((var varptr type) ...) first rest ...)
       (let ([var (foreign-alloc (ftype-sizeof type))] ...)
         (dynamic-wind
           (lambda () #f)
           (lambda ()
             (let ([varptr (make-ftype-pointer type var)] ...)
               first rest ...))
           (lambda ()
             (unlock-object var) ...
             (foreign-free var) ...)))]
      [(_ ((var varptr type num) ...) first rest ...)
       (let ([var (foreign-alloc (* num (ftype-sizeof type)))] ...)
         (dynamic-wind
           (lambda () #f)
           (lambda ()
             (let ([varptr (make-ftype-pointer type var)] ...)
               first rest ...))
           (lambda ()
             (unlock-object var) ...
             (foreign-free var) ...)))]))

  (meta define string-map
        (lambda (func str)
          (list->string (map func (string->list str)))))

  (meta define symbol->function-name-string
        (lambda (sym)
          (string-map (lambda (c)
                        (if (eqv? c #\-)
                            #\_ c))
                      (symbol->string sym))))

  ;; [syntax] c-function: converts scheme-like function names to c-like function names before passing to foreign-procedure.
  (define-syntax c-function
    (lambda (stx)
      (syntax-case stx ()
        [(_ (name args return) ...)
         (with-syntax ([(function-string ...)
                        (map (lambda (n)
                               (datum->syntax n
                                 (symbol->function-name-string (syntax->datum n))))
                             #'(name ...))])
            #'(begin
                (define name
                  (foreign-procedure function-string args return)) ...))])))

  ;; [syntax] c-default-function: define c functions that take a default argument.
  (define-syntax c-default-function
    (lambda (stx)
      (syntax-case stx ()
        [(_ (type instance) (name (arg ...) return) ...)
         (with-syntax ([(function-string ...)
                        (map (lambda (n)
                               (datum->syntax n
                                 (symbol->function-name-string (syntax->datum n))))
                             #'(name ...))])
            #'(begin
                (define name
                  (let ([ffi-func (foreign-procedure function-string (type arg ...) return)])
                    (lambda args
                      (apply ffi-func instance args)))) ...))])))

  ;; [parameter] get-errno-proc: function to retrieve errno after a C call.
  ;; Defaults to Chez internal #%$errno.  Libraries may override this with a
  ;; foreign-procedure bound to a C helper (e.g.  from libsocket.so).
  (define get-errno-proc
    (make-parameter
      (lambda () (#%$errno))))

  ;; [syntax] call-procedure/errno: call a foreign procedure and capture errno.
  ;; Uses get-errno-proc so that callers can supply a thread-safe or
  ;; library-specific errno accessor.
  (define-syntax call-procedure/errno
    (syntax-rules ()
      [(_ func args* ...)
       (with-interrupts-disabled
         (let ([rc (func args* ...)])
           (values rc ((get-errno-proc)))))]))

  ;; parse-enum-bit-defs: internal function.
  (meta define parse-enum-bit-defs
        (lambda (ebdefs)
          (let loop ([i 0] [ds ebdefs])
            (cond
             [(null? ds) #'()]
             [else
              (syntax-case (car ds) ()
                [(id val)
                 (cons (list #'id #'val) (loop (fx+ (syntax->datum #'val) 1) (cdr ds)))]
                [id
                 (identifier? #'id)
                 (cons (list #'id (datum->syntax #'id i)) (loop (fx+ i 1) (cdr ds)))])]))))

  ;; [syntax] c-enum: creates a function representing the enumeration.
  (define-syntax c-enum
    (lambda (stx)
      (syntax-case stx ()
        [(_ name enumdef1 enumdef* ...)
         (with-syntax
          ([((esym eid) ...) (parse-enum-bit-defs #'(enumdef1 enumdef* ...))])
          #'(define name
              (case-lambda
               [()
                '((esym . eid) ...)]
               [(x)
                (name
                 (cond
                  [(symbol? x)	'get-value]
                  [(number? x)	'get-id]
                  [else x])
                 x)]
               [(cmd arg)
                (case cmd
                  [(get-value)
                   (case arg
                     [(esym) eid] ...
                     [else (error (syntax->datum #'name) (format #f "value not defined for identifier ~s in enum" arg))])]
                  [(get-id)
                   (case arg
                     [(eid) 'esym] ...
                     [else (error (syntax->datum #'name) (format #f "identifier not defined for value ~d in enum" arg))])]
                  [else
                   (error (syntax->datum #'name) (format #f "unknown enum command ~s" cmd))])])))])))

  ;; [syntax] c-bitmap: define a bitmap enumeration.
  (define-syntax c-bitmap
    (lambda (stx)
      (syntax-case stx ()
        [(_ name bitdef1 bitdef* ...)
         (with-syntax
          ([((esym eid) ...) (parse-enum-bit-defs #'(bitdef1 bitdef* ...))])
          #'(define name
              (case-lambda
               [()
                '((esym . eid) ...)]
               [(x)
                (name
                 (cond
                  [(symbol? x)	'get-value]
                  [(number? x)	'get-symbols]
                  [else x])
                 x)]
               [(cmd arg)
                (case cmd
                  [(get-value)
                   (case arg
                     [(esym) eid] ...
                     [else (error (syntax->datum #'name) (format #f "value not defined for identifier ~s in bitmap" arg))])]
                  [(get-symbols)
                   (let loop ([ids '(eid ...)] [syms '(esym ...)])
                     (cond
                      [(null? ids) '()]
                      [else
                       (if (bitwise-bit-set? arg (car ids))
                           (cons (car syms) (loop (cdr ids) (cdr syms)))
                           (loop (cdr ids) (cdr syms)))]))]
                  [else
                   (error (syntax->datum #'name) (format #f "unknown bitmap command ~s" cmd))])])))])))

  ;; [procedure] locate-library-object: find first instance of filename within (library-directories) object directories.
  (define locate-library-object
    (lambda (filename)
      (let loop ([fps (map (lambda (d) (string-append (cdr d) "/" filename)) (library-directories))])
        (cond
         [(null? fps)
          filename]
         [(file-exists? (car fps))
          (car fps)]
         [else
          (loop (cdr fps))]))))

  )
