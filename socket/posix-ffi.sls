;; POSIX socket FFI layer for Chez Scheme.
;; Extracted from socket/c.sls to separate raw bindings from high-level logic.
;; SPDX-License-Identifier: Unlicense

(library (ufo-socket socket posix-ffi)
  (export
    ;; Socket constants
    *af-inet* *af-inet6* *af-unspec*
    *sock-dgram* *sock-stream*
    *ai-all* *ai-addrconfig* *ai-canonname* *ai-numerichost* *ai-v4mapped*
    *ai-numericserv* *ai-passive*
    *ipproto-ip* *ipproto-tcp* *ipproto-udp*
    *msg-oob* *msg-peek* *msg-waitall*
    *shut-rd* *shut-wr* *shut-rdwr*
    *somaxconn*
    *sol-socket*
    *so-acceptconn* *so-broadcast* *so-domain* *so-dontroute* *so-error* *so-keepalive* *so-linger* *so-oobinline*
    *so-protocol* *so-reuseaddr* *so-type* *so-reuseport*
    *so-rcvbuf* *so-sndbuf*
    *tcp-nodelay*
    *ip-multicast-loop* *ip-multicast-ttl* *ip-multicast-if*
    *ip-add-membership* *ip-drop-membership*
    *ni-namereqd* *ni-dgram* *ni-nofqdn* *ni-numerichost* *ni-numericserv*
    *ni-maxhost* *ni-maxserv*
    *s-sizeof-sockaddr*
    *eagain* *ewouldblock* *eintr*
    *so-rcvtimeo* *so-sndtimeo*
    *af-unix*
    *sizeof-sockaddr-un*

    ;; ftypes
    addrinfo* sockaddr* socklen-t

    ;; Raw C functions
    socket accept close bind connect listen recv recvfrom send shutdown strerror
    getaddrinfo freeaddrinfo getpeername getsockname getnameinfo gai-strerror gethostname
    getsockopt setsockopt
    make-addrinfo-hints addrinfo-flags addrinfo-family addrinfo-socktype
    addrinfo-protocol addrinfo-addrlen addrinfo-addr addrinfo-next
    mcast4-add-membership mcast6-add-membership
    mcast4-drop-membership mcast6-drop-membership
    socket-set-timeout make-sockaddr-un
    socket-set-nonblocking socket-get-nonblocking
    recv-offset send-offset

    ;; Socket record type
    sockobj make-socket socket? socket-file-descriptor)
  (import
    (chezscheme)
    (ufo-socket socket bytevector)
    (ufo-socket socket ftypes-util))

  (define lib-load
    (load-shared-object (locate-library-object "socket/libsocket.so")))

  ;; [syntax] c-const: extract integer value/s from memory address/es.
  (define-syntax c-const
    (lambda (stx)
      (define (*sym->c-var-str sym)
        (list->string
          `(#\c #\_
            ,@(filter
                (lambda (c)
                  (not (char=? c #\*)))
                (map
                  (lambda (c)
                    (cond
                      [(char=? c #\-)
                       #\_]
                      [else
                        (char-upcase c)]))
                  (string->list (symbol->string sym)))))))
      (syntax-case stx ()
        [(_ name name* ...)
         (with-syntax ([(frefs ...)
                        (map
                         (lambda (n)
                           #`(define #,n
                               (foreign-ref 'int (foreign-entry #,(*sym->c-var-str (syntax->datum n))) 0)))
                         #'(name name* ...))])
                      #'(begin
                          frefs ...))])))

  (c-const
    *af-inet* *af-inet6* *af-unspec*
    *sock-dgram* *sock-stream*
    *ai-all* *ai-addrconfig* *ai-canonname* *ai-numerichost* *ai-v4mapped*
    *ai-numericserv* *ai-passive*
    *ipproto-ip* *ipproto-tcp* *ipproto-udp*
    *msg-oob* *msg-peek* *msg-waitall*
    *shut-rd* *shut-wr* *shut-rdwr*
    *somaxconn*
    *sol-socket*
    *so-acceptconn* *so-broadcast* *so-domain* *so-dontroute* *so-error* *so-keepalive* *so-linger* *so-oobinline*
    *so-protocol* *so-reuseaddr* *so-type*
    *so-rcvbuf* *so-sndbuf* *so-reuseport*
    *ip-multicast-loop* *ip-multicast-ttl* *ip-multicast-if*
    *ip-add-membership* *ip-drop-membership*
    *ni-namereqd* *ni-dgram* *ni-nofqdn* *ni-numerichost* *ni-numericserv*
    *ni-maxhost* *ni-maxserv*
    *s-sizeof-sockaddr*
    *eagain* *ewouldblock* *eintr*
    *so-rcvtimeo* *so-sndtimeo*
    *af-unix*
    *sizeof-sockaddr-un*
    *tcp-nodelay*)

  (define-ftype addrinfo* void*)
  (define-ftype sockaddr* void*)
  (define-ftype socklen-t integer-32)

  (c-function
    ;;;;;; POSIX raw socket API.
    [socket (int int int) int]
    [accept (int void* void*) int]
    [close (int) int]
    [bind (int sockaddr* socklen-t) int]
    [connect (int sockaddr* socklen-t) int]
    [listen (int int) int]
    [recv (int u8* size_t int) ssize_t]
    [recvfrom (int u8* size_t int u8* (* socklen-t)) ssize_t]
    [send (int u8* size_t int) ssize_t]
    [shutdown (int int) int]
    [strerror (int) string]

    ;;;; Address info.
    [getaddrinfo (string string addrinfo* (* addrinfo*)) int]
    [freeaddrinfo (addrinfo*) void]
    [getpeername (int u8* (* socklen-t)) int]
    [getsockname (int u8* (* socklen-t)) int]
    [getnameinfo (u8* socklen-t u8* socklen-t u8* socklen-t int) int]
    [gai-strerror (int) string]
    [gethostname (u8* size_t) int]

    ;;;; Socket options.
    [getsockopt (int int int void* (* socklen-t)) int]
    [setsockopt (int int int void* socklen-t) int]

    ;;;; libsocket.so helper functions.
    [make-addrinfo-hints (int int int int) addrinfo*]
    [addrinfo-flags (addrinfo*) int]
    [addrinfo-family (addrinfo*) int]
    [addrinfo-socktype (addrinfo*) int]
    [addrinfo-protocol (addrinfo*) int]
    [addrinfo-addrlen (addrinfo*) socklen-t]
    [addrinfo-addr (addrinfo*) sockaddr*]
    [addrinfo-next (addrinfo*) addrinfo*]

    ;; multicasting.
    [mcast4-add-membership (int string int) int]
    [mcast6-add-membership (int string int) int]
    [mcast4-drop-membership (int string int) int]
    [mcast6-drop-membership (int string int) int]
    [socket-set-timeout (int long long long long) int]
    [make-sockaddr-un (string) void*]
    [socket-set-nonblocking (int int) int]
    [socket-get-nonblocking (int) int]
    [recv-offset (int u8* size_t size_t int) ssize_t]
    [send-offset (int u8* size_t size_t int) ssize_t]
)

  ;; The socket record type.
  (define-record-type (sockobj make-socket socket?)
    (fields
      [immutable file-descriptor socket-file-descriptor]))
)
