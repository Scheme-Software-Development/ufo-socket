;; Chez-socket: Common scheme implementation layer.
;;
;; Written by Akce 2019-2020.
;;
;; SPDX-License-Identifier: Unlicense

(library (ufo-socket socket impl)
  (export
    make-client-socket make-server-socket
    call-with-socket
    open-socket-input-port
    open-socket-output-port
    open-socket-input/output-port
    (rename
     (bitwise-ior socket-merge-flags)
     (bitwise-xor socket-purge-flags))
    address-family ip-protocol message-type name-info socket-domain shutdown-method)
  (import
   (chezscheme)
   (ufo-socket socket c)
   (ufo-socket socket ftypes-util))

  (define-enum address-family
    [inet	*af-inet*]
    [inet6	*af-inet6*]
    [unspec	*af-unspec*])

  (define-enum ip-protocol
    [ip		*ipproto-ip*]
    [tcp	*ipproto-tcp*]
    [udp	*ipproto-udp*])

  (define-bits message-type
    [none	0]
    [peek	*msg-peek*]
    [oob	*msg-oob*]
    [wait-all	*msg-waitall*])

  ;; getnameinfo(3) flags.
  (define-bits name-info
    [none		0]
    [namereqd		*ni-namereqd*]
    [dgram		*ni-dgram*]
    [nofqdn		*ni-nofqdn*]
    [numerichost	*ni-numerichost*]
    [numericserv	*ni-numericserv*])

  (define-enum socket-domain
    [stream	*sock-stream*]
    [datagram	*sock-dgram*])

  (define-syntax shutdown-method
    (lambda (x)
      (syntax-case x ()
        [(_ v)
         (eq? (datum v) 'read)
         #'*shut-rd*]
        [(_ v)
         (eq? (datum v) 'write)
         #'*shut-wr*]
        [(_ v1 v2)
         (let ([d1 (datum v1)]
               [d2 (datum v2)])
           (and
             (or (eq? d1 'read) (eq? d1 'write))
             (or (eq? d2 'read) (eq? d2 'write))
             (not (eq? d1 d2))))
         #'*shut-rdwr*])))

  (define make-client-socket
    (case-lambda
     [(node service)
      (make-client-socket node service *af-inet*)]
     [(node service ai-family)
      (make-client-socket node service ai-family *sock-stream*)]
     [(node service ai-family ai-socktype)
      (make-client-socket node service ai-family ai-socktype (bitwise-ior *ai-v4mapped* *ai-addrconfig*))]
     [(node service ai-family ai-socktype ai-flags)
      (make-client-socket node service ai-family ai-socktype ai-flags *ipproto-ip*)]
     [(node service ai-family ai-socktype ai-flags ai-protocol)
      (connect-client-socket node service ai-family ai-socktype ai-flags ai-protocol)]))

  (define make-server-socket
    (case-lambda
      [(service)
       (make-server-socket service *af-inet*)]
      [(service ai-family)
       (make-server-socket service ai-family *sock-stream*)]
      [(service ai-family ai-socktype)
       (make-server-socket service ai-family ai-socktype *ipproto-ip*)]
      [(service ai-family ai-socktype ai-protocol)
       (make-server-socket service ai-family ai-socktype ai-protocol #f)]
      [(service ai-family ai-socktype ai-protocol reuse-addr?)
       (connect-server-socket #f service ai-family ai-socktype (bitwise-ior *ai-v4mapped* *ai-addrconfig*) ai-protocol reuse-addr?)]))

  ;; call-with-socket is adapted from the call-with-port example found here:
  ;; https://scheme.com/tspl4/control.html#defn:call-with-port
  (define call-with-socket
    (lambda (conn proc)
      (call-with-values (lambda () (proc conn))
        (case-lambda
          [(val) (socket-close conn) val]
          [val* (socket-close conn) (apply values val*)]))))

  (define socket-port-reader
    (lambda (socket)
      (lambda (bytevector-dest start n)
        (let ([in (socket-recv socket n)])
          (cond
            [(bytevector? in)
              (let ([in-length (bytevector-length in)])
                (bytevector-copy! in 0 bytevector-dest start in-length)
                in-length)]
            [else
              ;; 'in' is 0 (representing EOF) as per the custom port r! protocol.
              in])))))

  (define socket-port-writer
    (lambda (socket)
      (lambda (bytevector-src start n)
        (socket-send socket bytevector-src start n))))

  (define open-socket-input-port
    (lambda (socket)
      (make-custom-binary-input-port
        "socket-input-port" (socket-port-reader socket) #f #f #f)))

  (define open-socket-output-port
    (lambda (socket)
      (make-custom-binary-output-port
        "socket-output-port" (socket-port-writer socket) #f #f #f)))

  (define open-socket-input/output-port
    (lambda (socket)
      (make-custom-binary-input/output-port
        "socket-input/output-port" (socket-port-reader socket) (socket-port-writer socket) #f #f #f)))

  )
