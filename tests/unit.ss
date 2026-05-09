#! /usr/bin/env -S chez-scheme --debug-on-exception --script

;; Unit tests for ufo-socket internals.
;; SPDX-License-Identifier: Unlicense

(import
  (rnrs)
  (ufo-socket)
  (ufo-socket socket bytevector))

(define fail-count 0)
(define pass-count 0)

(define (assert-equal who expected actual)
  (if (equal? expected actual)
      (begin
        (set! pass-count (+ pass-count 1))
        (display "PASS ")(display who)(newline))
      (begin
        (set! fail-count (+ fail-count 1))
        (display "FAIL ")(display who)
        (display ": expected ")(display expected)
        (display ", got ")(display actual)(newline))))

;;; bytevector tests
(let ([bv (let ([h (string->utf8 "hello")]
                  [w (string->utf8 "world")])
            (let ([out (make-bytevector (+ (bytevector-length h) 1 (bytevector-length w)))])
              (bytevector-copy! h 0 out 0 (bytevector-length h))
              (bytevector-u8-set! out (bytevector-length h) 0)
              (bytevector-copy! w 0 out (+ (bytevector-length h) 1) (bytevector-length w))
              out))])
  (assert-equal 'bytevector/null->string "hello" (bytevector/null->string bv)))

(let ([bv (string->utf8 "no-null")])
  (assert-equal 'bytevector/null->string-all "no-null" (bytevector/null->string bv)))

;;; UDP loopback test
(let ([srv (connect-server-socket #f "15000" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (let ([cli (connect-client-socket "127.0.0.1" "15000" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
    (socket-send cli (string->utf8 "hello udp"))
    (let ([data (socket-recv srv 100)])
      (assert-equal 'udp-loopback "hello udp" (utf8->string data)))
    (socket-close cli)
    (socket-close srv)))

;;; Error path test: connection refused
(guard (e [(socket-error? e)
            (assert-equal 'connection-refused 'socket-error-raised 'socket-error-raised)])
  (make-client-socket "127.0.0.1" "65000"
                      (address-family inet)
                      (socket-domain stream)
                      (address-info v4mapped addrconfig)
                      (ip-protocol tcp))
  (assert-equal 'connection-refused 'socket-error-raised 'no-error))

;;; socket-recvfrom/address test (UDP loopback)
(let ([srv (connect-server-socket #f "15001" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (let ([cli (connect-client-socket "127.0.0.1" "15001" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
    (socket-send cli (string->utf8 "from-addr"))
    (let-values ([(data host service) (socket-recvfrom/address srv 100)])
      (assert-equal 'recvfrom-address-data "from-addr" (utf8->string data))
      ;; host should be localhost or 127.0.0.1 in some form
      (if (or (string=? host "localhost") (string=? host "127.0.0.1"))
          (assert-equal 'recvfrom-address-host host host)
          (begin
            (set! fail-count (+ fail-count 1))
            (display "FAIL recvfrom-address-host: unexpected host ")(display host)(newline))))
    (socket-close cli)
    (socket-close srv)))

;;; AF_UNIX loopback test
(let ([path "/tmp/ufo-socket-test.sock"])
  ;; clean up stale socket
  (when (file-exists? path)
    (delete-file path))
  (let ([srv (make-unix-server-socket path)])
    (let ([cli (make-unix-client-socket path)])
      ;; accept the pending connection
      (let ([conn (socket-accept srv)])
        (socket-send cli (string->utf8 "unix hello"))
        (let ([data (socket-recv conn 100)])
          (assert-equal 'unix-loopback "unix hello" (utf8->string data))
          (socket-close conn)
          (socket-close cli)
          (socket-close srv))))))

;;; socket-set-timeout! test (indirect: verify it doesn't raise)
(let ([srv (make-server-socket "15002")])
  (socket-set-timeout! srv 2 2)
  (socket-close srv)
  (assert-equal 'set-timeout! 'ok 'ok))

;;; socket-recv! test
(let ([srv (connect-server-socket #f "15003" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (let ([cli (connect-client-socket "127.0.0.1" "15003" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
    (socket-send cli (string->utf8 "recv!"))
    (let ([buf (make-bytevector 100)])
      (let ([n (socket-recv! srv buf)])
        (assert-equal 'socket-recv!-len 5 n)
        (assert-equal 'socket-recv!-data "recv!" (utf8->string (bytevector-slice buf n)))))
    (socket-close cli)
    (socket-close srv)))

;;; socket-set-nonblocking! test
(let ([srv (connect-server-socket #f "15004" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (socket-set-nonblocking! srv #t)
  (let ([data (socket-recv srv 100)])
    (assert-equal 'nonblocking-recv #f data))
  (socket-close srv))

;;; Summary
(display "=== ")(display pass-count)(display " passed, ")(display fail-count)(display " failed ===")(newline)
(if (> fail-count 0) (exit 1) (exit 0))
