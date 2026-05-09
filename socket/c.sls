;; Chez scheme high-level socket layer.
;; Raw FFI bindings have been extracted to (ufo-socket socket posix-ffi).
;; SPDX-License-Identifier: Unlicense

(library (ufo-socket socket c)
  (export
    create-socket-reuseaddr
    socket? socket-file-descriptor socket-accept socket-close
    socket-peerinfo socket-recv socket-recvfrom socket-send socket-shutdown
    connect-server-socket connect-client-socket

    *af-inet* *af-inet6* *af-unspec*
    *sock-dgram* *sock-stream*
    *ai-all* *ai-addrconfig* *ai-canonname* *ai-numerichost* *ai-v4mapped*
    *ipproto-ip* *ipproto-tcp* *ipproto-udp*
    *msg-oob* *msg-peek* *msg-waitall*
    *shut-rd* *shut-wr* *shut-rdwr*

    *ai-numericserv* *ai-passive*
    socket-get-int socket-set-int!
    *ip-multicast-loop* *ip-multicast-ttl* *ip-multicast-if*
    *ip-add-membership* *ip-drop-membership*

    *sol-socket*
    *so-acceptconn* *so-broadcast* *so-domain* *so-dontroute* *so-error* *so-keepalive* *so-linger* *so-oobinline*
    *so-protocol* *so-reuseaddr* *so-type*
    *so-rcvbuf* *so-sndbuf* *tcp-nodelay*

    *ni-namereqd* *ni-dgram* *ni-nofqdn* *ni-numerichost* *ni-numericserv*
    *ni-maxhost* *ni-maxserv*
    *eagain* *ewouldblock* *eintr*
    *somaxconn*
    *so-rcvtimeo* *so-sndtimeo*
    *af-unix*
    *sizeof-sockaddr-un*

    (rename
      (getnameinfo/bv getnameinfo)
      (gethostname* gethostname))

    mcast-add-membership mcast-drop-membership
    socket-error socket-error? raise-socket-error
    getaddrinfo*
    socket-recvfrom/address
    socket-set-timeout!
    make-unix-client-socket make-unix-server-socket
    socket-recv! socket-set-nonblocking! socket-nonblocking?
    socket-send-all
    )
  (import
   (chezscheme)
   (ufo-socket socket posix-ffi)
   (ufo-socket socket ftypes-util)
   (ufo-socket socket bytevector))

  ;; Re-export all POSIX constants so downstream libraries don't need to
  ;; import posix-ffi directly.

  ;; Structured exception type for socket operations.
  (define-record-type socket-error
    (fields who errno message))

  (define raise-socket-error
    (case-lambda
      [(who msg)
       (raise (make-socket-error who #f msg))]
      [(who errno msg)
       (raise (make-socket-error who errno msg))]
      [(who errno fmt . args)
       (raise (make-socket-error who errno (apply format fmt args)))]))

  ;; [parameter] create-socket-reuseaddr: legacy parameter for SO_REUSEADDR.
  ;; Prefer passing #:reuse-addr? to make-server-socket/connect-server-socket.
  (define create-socket-reuseaddr
    (make-parameter #f))

  (define connect-server-socket
    (case-lambda
      [(node service family socktype flags protocol)
       (connect-server-socket node service family socktype flags protocol (create-socket-reuseaddr) *somaxconn*)]
      [(node service family socktype flags protocol reuse-addr?)
       (connect-server-socket node service family socktype flags protocol reuse-addr? *somaxconn*)]
      [(node service family socktype flags protocol reuse-addr? backlog)
       (let ([sock (connect-socket node service family socktype flags protocol bind reuse-addr?)])
         ;; TCP sockets (streams) also need to be listened to.
         (when (and sock (= (socket-get-int sock *sol-socket* *so-type*) *sock-stream*))
           (let-values ([(rc errno) (call-procedure/errno listen (socket-file-descriptor sock) backlog)])
             (when (fx=? rc -1)
               (socket-close sock)
               (raise-socket-error 'connect-server-socket errno "~a" (strerror errno)))))
         sock)]))

  (define connect-client-socket
    (case-lambda
      [(node service family socktype flags protocol)
       (connect-client-socket node service family socktype flags protocol #f)]
      [(node service family socktype flags protocol reuse-addr?)
       (connect-socket node service family socktype flags protocol connect reuse-addr?)]))

  (define (errno-nonblocking? errno)
    (or (fx=? errno *eagain*) (fx=? errno *ewouldblock*) (fx=? errno *eintr*)))

  (define socket-accept
    (lambda (sock)
      (let-values ([(peerfd errno) (call-procedure/errno accept (socket-file-descriptor sock) 0 0)])
        (cond
          [(fx>=? peerfd 0) (make-socket peerfd)]
          [(errno-nonblocking? errno) #f]
          [else
           (raise-socket-error 'socket-accept errno "~a" (strerror errno))]))))

  (define socket-recv
    (case-lambda
      [(sock len)
       (socket-recv sock len 0)]
      [(sock len flags)
       (let ([buf (make-bytevector len)])
         (let-values ([(rc errno) (call-procedure/errno recv (socket-file-descriptor sock) buf len flags)])
           (cond
             [(fx>? rc 0)
              (bytevector-slice buf rc)]
             [(fx=? rc 0)
              ;; UDP datagram sockets may return 0 for an empty datagram.
              ;; TCP stream sockets return 0 for EOF.
              (if (fx=? (socket-get-int sock *sol-socket* *so-type*) *sock-dgram*)
                  (bytevector-slice buf 0)
                  0)]
             [(errno-nonblocking? errno) #f]
             [else
               (raise-socket-error 'socket-recv errno "~a" (strerror errno))])))]))

  ;; [proc] socket-recv!: receive data into an existing bytevector.
  ;; [return] bytes read, 0 for EOF, or #f on EAGAIN.
  (define socket-recv!
    (case-lambda
      [(sock buf)
       (socket-recv! sock buf 0 (bytevector-length buf) 0)]
      [(sock buf flags)
       (socket-recv! sock buf 0 (bytevector-length buf) flags)]
      [(sock buf start count)
       (socket-recv! sock buf start count 0)]
      [(sock buf start count flags)
       (if (fx=? start 0)
           (let-values ([(rc errno) (call-procedure/errno recv (socket-file-descriptor sock) buf count flags)])
             (cond
               [(fx>? rc 0) rc]
               [(fx=? rc 0) 0]
               [(errno-nonblocking? errno) #f]
               [else
                (raise-socket-error 'socket-recv! errno "~a" (strerror errno))]))
           (let ([tmp (make-bytevector count)])
             (let-values ([(rc errno) (call-procedure/errno recv (socket-file-descriptor sock) tmp count flags)])
               (cond
                 [(fx>? rc 0)
                  (bytevector-copy! tmp 0 buf start rc)
                  rc]
                 [(fx=? rc 0) 0]
                 [(errno-nonblocking? errno) #f]
                 [else
                  (raise-socket-error 'socket-recv! errno "~a" (strerror errno))]))))]))

  ;; [proc] socket-recvfrom: recv data and sender info.
  ;; [return] (cons data-u8-bytevector sockaddr-u8-bytevector)
  (define socket-recvfrom
    (case-lambda
      [(sock len)
       (socket-recvfrom sock len 0)]
      [(sock len flags)
       (alloc ([salen &salen socklen-t])
         (ftype-set! socklen-t () &salen *s-sizeof-sockaddr*)
         (let*-values ([(buf) (make-bytevector len)]
                       [(saddr) (make-bytevector *s-sizeof-sockaddr*)]
                       [(rc errno) (call-procedure/errno recvfrom (socket-file-descriptor sock) buf len flags saddr &salen)])
           (cond
             [(fx>? rc 0)
              (cons (bytevector-slice buf rc) (bytevector-slice saddr (ftype-ref socklen-t () &salen)))]
             [(fx=? rc 0)
              ;; UDP may return 0 for an empty datagram.
              (if (fx=? (socket-get-int sock *sol-socket* *so-type*) *sock-dgram*)
                  (cons (bytevector-slice buf 0) (bytevector-slice saddr (ftype-ref socklen-t () &salen)))
                  0)]
             [(errno-nonblocking? errno) #f]
             [else
               (raise-socket-error 'socket-recvfrom errno "~a" (strerror errno))])))]))

  (define socket-send
    (case-lambda
      [(sock bv)
       (socket-send sock bv 0 (bytevector-length bv) 0)]
      [(sock bv flags)
       (socket-send sock bv 0 (bytevector-length bv) flags)]
      [(sock bv start n)
       (socket-send sock bv start n 0)]
      [(sock bv start n flags)
       (let ([data (if (fx=? start 0)
                       bv
                       (let ([sub (make-bytevector n)])
                         (bytevector-copy! bv start sub 0 n)
                         sub))])
         (let-values ([(rc errno) (call-procedure/errno send (socket-file-descriptor sock) data n flags)])
           (cond
             [(fx>=? rc 0)
              rc]
             [(errno-nonblocking? errno) #f]
             [else
               (raise-socket-error 'socket-send errno "~a" (strerror errno))])))]))

  (define socket-send-all
    (case-lambda
      [(sock bv)
       (socket-send-all sock bv 0 (bytevector-length bv))]
      [(sock bv start count)
       (let loop ([offset start] [remaining count])
         (when (fx>? remaining 0)
           (let ([sent (socket-send sock bv offset remaining)])
             (cond
               [(not sent)
                (raise-socket-error 'socket-send-all *eagain* "socket would block before all data sent")]
               [(fx>? sent 0)
                (loop (fx+ offset sent) (fx- remaining sent))]
               [else
                (raise-socket-error 'socket-send-all #f "send returned 0 before all data sent")]))))]))

  (define socket-close
    (lambda (sock)
      (close (socket-file-descriptor sock))))

  (define socket-shutdown
    (lambda (sock how)
      (let-values ([(rc errno) (call-procedure/errno shutdown (socket-file-descriptor sock) how)])
        (when (fx=? rc -1)
          (raise-socket-error 'socket-shutdown errno "~a" (strerror errno))))))

  (define socket-get-int
    (let ([f (foreign-procedure "getsockopt" (int int int (* int) (* int)) int)])
      (lambda (sock level optname)
        (alloc ([sz &sz int]
                [res &res int])
          (ftype-set! int () &sz (ftype-sizeof int))
          (let-values ([(rc errno) (call-procedure/errno f (if (socket? sock) (socket-file-descriptor sock) sock) level optname &res &sz)])
            (cond
              [(fx=? rc -1)
               (raise-socket-error 'socket-get-int errno "~a" (strerror errno))]
              [else
                (ftype-ref int () &res 0)]))))))

  (define socket-set-int!
    (let ([f (foreign-procedure "setsockopt" (int int int (* int) int) int)])
      (lambda (sock level optname optval)
        (alloc ([val &val int])
          (ftype-set! int () &val optval)
          (let-values ([(rc errno)
                        (call-procedure/errno
                          f
                          (if (socket? sock)
                            (socket-file-descriptor sock)
                            sock)
                          level optname &val (ftype-sizeof int))])
            (cond
              [(fx=? rc -1)
               (raise-socket-error 'socket-set-int! errno "~a" (strerror errno))]
              [else
                rc]))))))

  ;; Largely follows the example from getaddrinfo(2).
  (define connect-socket
    (lambda (node service family socktype flags protocol action reuse-addr?)
      (let* ([hints (make-addrinfo-hints flags family socktype protocol)]
             [addrinfos (getaddrinfo* node service hints)])
        (freeaddrinfo hints)
        (let loop ([as addrinfos])
          (cond
            [(null? as)
             (freeaddrinfo-list addrinfos)
             (raise-socket-error 'connect-socket #f "no suitable address found: ~a ~a" node service)]
            [else
              (let* ([ai (car as)]
                     [sockfd (socket (addrinfo-family ai) (addrinfo-socktype ai) (addrinfo-protocol ai))])
                (case sockfd
                  [-1
                    (loop (cdr as))]
                  [else
                    (when (or reuse-addr? (create-socket-reuseaddr))
                      (socket-set-int! sockfd *sol-socket* *so-reuseaddr* 1))
                    (case (action sockfd (addrinfo-addr ai) (addrinfo-addrlen ai))
                      [0
                       (freeaddrinfo-list addrinfos)
                       (make-socket sockfd)]
                      [else
                        (close sockfd)
                        (loop (cdr as))])]))])))))

  (define getaddrinfo*
    (case-lambda
      [(node service)
       (getaddrinfo* node service 0)]
      [(node service hints)
       (alloc ([res &res addrinfo*])
         (let ([rc (getaddrinfo node service hints &res)])
           (case rc
             [0
              (let loop ([next (ftype-ref addrinfo* () &res 0)] [acc '()])
                (cond
                  [(eqv? next 0)
                   (reverse acc)]
                  [else
                    (loop (addrinfo-next next) (cons next acc))]))]
             [else
               (raise-socket-error 'getaddrinfo rc "~a" (gai-strerror rc))])))]))

  ;; freeaddrinfo releases the entire C linked list starting at the head node.
  ;; The Scheme list merely holds pointers into that list.
  (define freeaddrinfo-list
    (lambda (ais)
      (when (pair? ais)
        (freeaddrinfo (car ais)))))

  ;; [proc] getnameinfo/bv: getnameinfo bytevector interface
  ;; [args] sockaddr [flags]
  ;; [return] (values host-string service-string)
  (define getnameinfo/bv
    (case-lambda
      [(sockaddr)
       (getnameinfo/bv sockaddr 0)]
      [(sockaddr flags)
       (let* ([host (make-bytevector *ni-maxhost*)]
              [serv (make-bytevector *ni-maxserv*)]
              [rc (getnameinfo
                    sockaddr (bytevector-length sockaddr)
                    host (bytevector-length host)
                    serv (bytevector-length serv)
                    flags)])
         (cond
           [(fx=? rc 0)
            (values
              (bytevector/null->string host)
              (bytevector/null->string serv))]
           [else
             (raise-socket-error 'getnameinfo rc "~a" (gai-strerror rc))]))]))

  (define gethostname*
    (lambda ()
      (let*-values ([(buf) (make-bytevector *ni-maxhost*)]
                    [(rc errno) (call-procedure/errno gethostname buf (bytevector-length buf))])
        (cond
          [(fx=? rc 0)
           (bytevector/null->string buf)]
          [else
            (raise-socket-error 'gethostname errno "~a" (strerror errno))]))))

  (define socket-peerinfo
    (case-lambda
      [(sock)
       (socket-peerinfo sock 0)]
      [(sock flags)
       (alloc ([salen &salen socklen-t])
         (ftype-set! socklen-t () &salen *s-sizeof-sockaddr*)
         (let ([saddr (make-bytevector *s-sizeof-sockaddr*)])
           (let-values ([(rc errno) (call-procedure/errno getpeername (socket-file-descriptor sock) saddr &salen)])
             (if (fx=? rc 0)
                 (getnameinfo/bv (bytevector-slice saddr (ftype-ref socklen-t () &salen)) flags)
                 (raise-socket-error 'socket-peerinfo errno "~a" (strerror errno))))))]))

  (define socket-recvfrom/address
    (case-lambda
      [(sock len)
       (socket-recvfrom/address sock len 0)]
      [(sock len flags)
       (let ([result (socket-recvfrom sock len flags)])
         (if (pair? result)
             (let ([data (car result)]
                   [saddr (cdr result)])
               (let-values ([(host service) (getnameinfo/bv saddr)])
                 (values data host service)))
             result))]))

  (define mcast-add-membership
    (case-lambda
      [(sock node)
       (mcast-add-membership sock node 0)]
      [(sock node interface)
       (let ([domain (socket-get-int sock *sol-socket* *so-domain*)])
         (cond
           [(= domain *af-inet*)
            (mcast4-add-membership (socket-file-descriptor sock) node interface)]
           [(= domain *af-inet6*)
            (mcast6-add-membership (socket-file-descriptor sock) node interface)]
           [else
             #f]))]))

  (define mcast-drop-membership
    (case-lambda
      [(sock node)
       (mcast-drop-membership sock node 0)]
      [(sock node interface)
       (let ([domain (socket-get-int sock *sol-socket* *so-domain*)])
         (cond
           [(= domain *af-inet*)
            (mcast4-drop-membership (socket-file-descriptor sock) node interface)]
           [(= domain *af-inet6*)
            (mcast6-drop-membership (socket-file-descriptor sock) node interface)]
           [else
             #f]))]))

  (define (timeout->sec-usec t)
    (cond
      [(not t) (values -1 0)]
      [(integer? t) (values t 0)]
      [else
       (let* ([sec (exact (truncate t))]
              [usec (exact (round (* (- t sec) 1000000)))])
         (if (fx>=? usec 1000000)
             (values (fx+ sec 1) 0)
             (values sec usec)))]))

  (define socket-set-timeout!
    (case-lambda
      [(sock recv-timeout send-timeout)
       (let-values ([(rs rus) (timeout->sec-usec recv-timeout)]
                    [(ss sus) (timeout->sec-usec send-timeout)])
         (socket-set-timeout! sock rs ss rus sus))]
      [(sock recv-sec send-sec recv-usec send-usec)
       (let-values ([(rc errno) (call-procedure/errno socket-set-timeout
                                   (socket-file-descriptor sock)
                                   (if recv-sec recv-sec -1)
                                   (if recv-usec recv-usec 0)
                                   (if send-sec send-sec -1)
                                   (if send-usec send-usec 0))])
         (when (fx=? rc -1)
           (raise-socket-error 'socket-set-timeout! errno "~a" (strerror errno))))]))

  (define socket-set-nonblocking!
    (lambda (sock nonblocking)
      (let-values ([(rc errno) (call-procedure/errno socket-set-nonblocking
                                  (socket-file-descriptor sock)
                                  (if nonblocking 1 0))])
        (when (fx=? rc -1)
          (raise-socket-error 'socket-set-nonblocking! errno "~a" (strerror errno))))))

  (define socket-nonblocking?
    (lambda (sock)
      (let-values ([(rc errno) (call-procedure/errno socket-get-nonblocking (socket-file-descriptor sock))])
        (cond
          [(fx=? rc -1)
           (raise-socket-error 'socket-nonblocking? errno "~a" (strerror errno))]
          [else (fx=? rc 1)]))))

  (define make-unix-client-socket
    (lambda (path)
      (let-values ([(sockfd errno) (call-procedure/errno socket *af-unix* *sock-stream* 0)])
        (when (fx=? sockfd -1)
          (raise-socket-error 'make-unix-client-socket errno "~a" (strerror errno)))
        (let ([addr (make-sockaddr-un path)])
          (when (eqv? addr 0)
            (close sockfd)
            (raise-socket-error 'make-unix-client-socket #f "failed to allocate sockaddr_un"))
          (let-values ([(rc errno) (call-procedure/errno connect sockfd addr *sizeof-sockaddr-un*)])
            (foreign-free addr)
            (if (fx=? rc 0)
                (make-socket sockfd)
                (begin
                  (close sockfd)
                  (raise-socket-error 'make-unix-client-socket errno "~a" (strerror errno)))))))))

  (define make-unix-server-socket
    (lambda (path)
      (let-values ([(sockfd errno) (call-procedure/errno socket *af-unix* *sock-stream* 0)])
        (when (fx=? sockfd -1)
          (raise-socket-error 'make-unix-server-socket errno "~a" (strerror errno)))
        (socket-set-int! sockfd *sol-socket* *so-reuseaddr* 1)
        (let ([addr (make-sockaddr-un path)])
          (when (eqv? addr 0)
            (close sockfd)
            (raise-socket-error 'make-unix-server-socket #f "failed to allocate sockaddr_un"))
          (let-values ([(rc errno) (call-procedure/errno bind sockfd addr *sizeof-sockaddr-un*)])
            (foreign-free addr)
            (if (fx=? rc 0)
                (let-values ([(lrc lerrno) (call-procedure/errno listen sockfd *somaxconn*)])
                  (if (fx=? lrc 0)
                      (make-socket sockfd)
                      (begin
                        (close sockfd)
                        (raise-socket-error 'make-unix-server-socket lerrno "~a" (strerror lerrno)))))
                (begin
                  (close sockfd)
                  (raise-socket-error 'make-unix-server-socket errno "~a" (strerror errno)))))))))

  ;; Configure a thread-safe errno accessor backed by our C helper.
  (get-errno-proc (foreign-procedure "c_errno" () int))
)
