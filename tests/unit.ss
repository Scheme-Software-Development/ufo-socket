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

;;; socket-set-timeout! test (integer + float seconds)
(let ([srv (make-server-socket "15002")])
  (socket-set-timeout! srv 2 2)       ; integer seconds
  (socket-set-timeout! srv 1.5 0.5)   ; float seconds -> 1s500000us / 0s500000us
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

;;; socket-get-int / socket-set-int! test (SO_REUSEADDR round-trip)
(let ([srv (make-server-socket "15005")])
  ;; default reuse-addr may be 0 or 1; set it to 1 explicitly
  (socket-set-int! srv *sol-socket* *so-reuseaddr* 1)
  (assert-equal 'socket-get-int-reuseaddr 1 (socket-get-int srv *sol-socket* *so-reuseaddr*))
  (socket-set-int! srv *sol-socket* *so-reuseaddr* 0)
  (assert-equal 'socket-get-int-reuseaddr-off 0 (socket-get-int srv *sol-socket* *so-reuseaddr*))
  (socket-close srv))

;;; nonblocking socket-accept returns #f when no pending connection
(let ([srv (make-server-socket "15006")])
  (socket-set-nonblocking! srv #t)
  (let ([conn (socket-accept srv)])
    (assert-equal 'nonblocking-accept-no-conn #f conn))
  (socket-close srv))

;;; socket-set-timeout! microsecond precision test
(let ([srv (make-server-socket "15007")])
  (socket-set-timeout! srv 1 1 500000 500000)
  (socket-close srv)
  (assert-equal 'set-timeout-usec 'ok 'ok))

;;; make-server-socket with custom backlog
(let ([srv (make-server-socket "15008" *af-inet* *sock-stream* *ipproto-ip* #f 5)])
  (socket-close srv)
  (assert-equal 'make-server-socket-backlog 'ok 'ok))

;;; socket options: SO_RCVBUF / SO_SNDBUF
;; Linux doubles the user value for sk_buff overhead, so we only verify
;; the value is >= what we asked for and that get/set don't raise.
(let ([srv (make-server-socket "15009")])
  (socket-set-int! srv *sol-socket* *so-rcvbuf* 8192)
  (let ([rcv (socket-get-int srv *sol-socket* *so-rcvbuf*)])
    (if (>= rcv 8192)
        (begin (set! pass-count (+ pass-count 1)) (display "PASS socket-option-rcvbuf")(newline))
        (begin (set! fail-count (+ fail-count 1)) (display "FAIL socket-option-rcvbuf: expected >= 8192, got ")(display rcv)(newline))))
  (socket-set-int! srv *sol-socket* *so-sndbuf* 8192)
  (let ([snd (socket-get-int srv *sol-socket* *so-sndbuf*)])
    (if (>= snd 8192)
        (begin (set! pass-count (+ pass-count 1)) (display "PASS socket-option-sndbuf")(newline))
        (begin (set! fail-count (+ fail-count 1)) (display "FAIL socket-option-sndbuf: expected >= 8192, got ")(display snd)(newline))))
  (socket-close srv))

;;; TCP_NODELAY round-trip
(let ([srv (make-server-socket "15010")])
  (socket-set-int! srv *ipproto-tcp* *tcp-nodelay* 1)
  (assert-equal 'socket-option-nodelay 1 (socket-get-int srv *ipproto-tcp* *tcp-nodelay*))
  (socket-set-int! srv *ipproto-tcp* *tcp-nodelay* 0)
  (assert-equal 'socket-option-nodelay-off 0 (socket-get-int srv *ipproto-tcp* *tcp-nodelay*))
  (socket-close srv))

;;; socket-shutdown test
(let ([srv (make-server-socket "15015")])
  (let ([cli (make-client-socket "127.0.0.1" "15015")])
    (let ([conn (socket-accept srv)])
      (socket-send cli (string->utf8 "hello"))
      (let ([data (socket-recv conn 100)])
        (assert-equal 'shutdown-recv "hello" (utf8->string data)))
      ;; shutdown the accepted connection for writing
      (socket-shutdown conn *shut-wr*)
      ;; client should see EOF (0 bytes) on next recv
      (let ([eof-data (socket-recv cli 100)])
        (assert-equal 'shutdown-eof 0 eof-data))
      (socket-close conn)
      (socket-close cli)
      (socket-close srv))))

;;; socket-peerinfo test
(let ([srv (make-server-socket "15016")])
  (let ([cli (make-client-socket "127.0.0.1" "15016")])
    (let ([conn (socket-accept srv)])
      (let-values ([(host service) (socket-peerinfo conn)])
        ;; getnameinfo may return "localhost" or "127.0.0.1" depending on /etc/hosts
        (if (or (string=? host "localhost") (string=? host "127.0.0.1"))
            (assert-equal 'peerinfo-host host host)
            (begin
              (set! fail-count (+ fail-count 1))
              (display "FAIL peerinfo-host: unexpected host ")(display host)(newline))))
      (socket-close conn)
      (socket-close cli)
      (socket-close srv))))

;;; socket-recv! start/count test
(let ([srv (connect-server-socket #f "15017" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (let ([cli (connect-client-socket "127.0.0.1" "15017" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
    (socket-send cli (string->utf8 "hello"))
    (let ([buf (make-bytevector 10 0)])
      (let ([n (socket-recv! srv buf 2 5)])
        (assert-equal 'socket-recv!-start-len 5 n)
        (assert-equal 'socket-recv!-start-b2 104 (bytevector-u8-ref buf 2))
        (assert-equal 'socket-recv!-start-b3 101 (bytevector-u8-ref buf 3))
        (assert-equal 'socket-recv!-start-b6 111 (bytevector-u8-ref buf 6))
        (assert-equal 'socket-recv!-start-b7 0 (bytevector-u8-ref buf 7))))
    (socket-close cli)
    (socket-close srv)))

;;; socket-nonblocking? test
(let ([srv (make-server-socket "15018")])
  (assert-equal 'nonblocking-initial #f (socket-nonblocking? srv))
  (socket-set-nonblocking! srv #t)
  (assert-equal 'nonblocking-after-set #t (socket-nonblocking? srv))
  (socket-set-nonblocking! srv #f)
  (assert-equal 'nonblocking-after-clear #f (socket-nonblocking? srv))
  (socket-close srv))

;;; socket-recv with MSG_PEEK flag
(let ([srv (connect-server-socket #f "15019" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (let ([cli (connect-client-socket "127.0.0.1" "15019" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
    (socket-send cli (string->utf8 "peektest"))
    (let ([data1 (socket-recv srv 100 *msg-peek*)])
      (assert-equal 'recv-peek-data "peektest" (utf8->string data1))
      ;; data should still be in buffer, recv again without PEEK
      (let ([data2 (socket-recv srv 100)])
        (assert-equal 'recv-after-peek "peektest" (utf8->string data2))))
    (socket-close cli)
    (socket-close srv)))

;;; open-socket-input-port / open-socket-output-port test
(let ([srv (make-server-socket "15020")])
  (let ([cli (make-client-socket "127.0.0.1" "15020")])
    (let ([conn (socket-accept srv)])
      (let ([out-port (open-socket-output-port cli)]
            [in-port (open-socket-input-port conn)])
        (put-u8 out-port 65)  ; 'A'
        (flush-output-port out-port)
        (let ([ch (get-u8 in-port)])
          (assert-equal 'socket-port-get-u8 65 ch))
        (close-output-port out-port)
        (close-input-port in-port))
      (socket-close conn)
      (socket-close cli)
      (socket-close srv))))

;;; call-with-socket test
(let ([srv (connect-server-socket #f "15021" *af-inet* *sock-dgram* 0 *ipproto-udp*)])
  (let ([result (call-with-socket srv
                   (lambda (sock)
                     (socket-set-int! sock *sol-socket* *so-reuseaddr* 1)
                     'ok))])
    (assert-equal 'call-with-socket 'ok result)))

;;; socket-send-all test (TCP)
(let ([srv (make-server-socket "15022")])
  (let ([cli (make-client-socket "127.0.0.1" "15022")])
    (let ([conn (socket-accept srv)])
      (socket-send-all cli (string->utf8 "hello-all"))
      (let ([data (socket-recv conn 100)])
        (assert-equal 'socket-send-all "hello-all" (utf8->string data)))
      (socket-close conn)
      (socket-close cli)
      (socket-close srv))))

;;; Summary
(display "=== ")(display pass-count)(display " passed, ")(display fail-count)(display " failed ===")(newline)
(if (> fail-count 0) (exit 1) (exit 0))
