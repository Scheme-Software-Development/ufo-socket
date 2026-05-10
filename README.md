# ufo-socket

This repository is basically a re-organized version of [chez-socket](https://github.com/akce/chez-socket). I just did some work making it compatible with [AKKU](https://akkuscm.org/) and [chez-exe](https://github.com/gwatt/chez-exe) and fixing bugs. Apparently, it brings several convenient features for reusing it in other softwares.

This repository requires Linux socket library.

## Prerequisite

Chez Scheme, [AKKU](https://akkuscm.org/) and [chez-exe](https://github.com/gwatt/chez-exe).

```bash
akku install
bash .akku/env
make
```

`make` compiles both the C shared library (`socket/libsocket.so`) and the Scheme libraries (`.so` / `.wpo`).

## How to use?

`(import (ufo-socket))` to use [srfi-106](https://srfi.schemers.org/srfi-106/) plus local extensions. These are highly experimental and have lots of room for improvement.

### Core procedures

```
[proc] socket-fd: returns the file descriptor for the socket.
```
```
[proc] socket->port: shortcut for creating a transcoded text port from a binary socket
```
The created port is input/output.
```
[proc] open-socket-input-port: creates a binary socket port for input only.
```
```
[proc] open-socket-output-port: creates a binary socket port for output only.
```
```
[proc] open-socket-input/output-port: creates a binary socket port for both input and output operations.
```

### Socket shutdown

```scheme
(socket-shutdown sock *shut-wr*)   ; disable further sends
(socket-shutdown sock *shut-rd*)   ; disable further receives
(socket-shutdown sock *shut-rdwr*) ; disable both
```

`socket-shutdown` raises `socket-error` on failure (e.g. `ENOTCONN`).

### Peer info

```scheme
(let-values ([(host service) (socket-peerinfo conn)])
  ...)
```

Returns the remote address of a connected socket. Raises `socket-error` if the socket is not connected.

### Socket options

Some socket options whose values are integers or boolean may also be retrieved and set. For boolean options, use 0 for FALSE, and 1 for TRUE.
See the *extended* source file for a list of the options that are defined.

```
[proc] socket-get-int: Get integer socket option.
```
```
[proc] socket-set-int!: Set integer socket option.
```

### Name resolution

```
[proc] getnameinfo: Get host and service information from a socket address.
                     Returns (values host-string service-string).
```
```
[proc] gethostname: Return the hostname of the local machine.
```
```
[proc] getaddrinfo*: Resolve a node/service to a list of addrinfo records.
```

### Non-blocking sockets

```
[proc] socket-accept: Accept a connection. On blocking sockets this waits until
                       a peer connects. On non-blocking sockets it returns #f
                       when no connection is pending (EAGAIN/EWOULDBLOCK/EINTR).
```
```
[proc] socket-recv:  Receive data. Returns a bytevector, 0 for EOF, or #f on
                       EAGAIN/EWOULDBLOCK/EINTR in non-blocking mode.
```
```
[proc] socket-send:  Send data. Returns bytes sent, or #f on EAGAIN/EWOULDBLOCK/EINTR
                       in non-blocking mode.
```
```
[proc] socket-send-all: Send the entire bytevector. Returns the total bytes sent.
                          In blocking mode, automatically retries on EINTR.
                          In non-blocking mode, raises socket-error with the real
                          errno (EAGAIN/EWOULDBLOCK) if the send would block.
```

### Client socket with connection timeout

```scheme
(make-client-socket "example.com" "80"
                    (address-family inet) (socket-domain stream)
                    (bitwise-ior *ai-v4mapped* *ai-addrconfig*)
                    (ip-protocol tcp)
                    5.0)   ; 5 second total timeout (float seconds allowed)
```

The timeout is a **total deadline**. If `getaddrinfo` returns multiple addresses, the time budget is shared across all fallback attempts.

### Server socket with SO_REUSEADDR

```scheme
(make-server-socket "8080" (address-family inet) (socket-domain stream)
                    (ip-protocol tcp) #t)   ; last arg enables SO_REUSEADDR
```

The legacy parameter `create-socket-reuseaddr` still works, but passing an explicit argument is preferred.

### Error predicates

Fine-grained error checking is available via errno-specific predicates:

```scheme
(guard (e [(socket-connection-refused-error? e)
           (display "Connection refused\n")]
          [(socket-timed-out-error? e)
           (display "Timed out\n")]
          [(socket-error? e)
           (display (socket-error-message e))])
  (make-client-socket "127.0.0.1" "9999" (address-family inet) (socket-domain stream)
                      0 (ip-protocol ip) #f 1.0))
```

Available predicates:
- `socket-error-errno-is?` — generic errno comparison
- `socket-connection-refused-error?` — `ECONNREFUSED`
- `socket-timed-out-error?` — `ETIMEDOUT`
- `socket-already-connected-error?` — `EISCONN`
- `socket-connection-reset-error?` — `ECONNRESET`
- `socket-connection-aborted-error?` — `ECONNABORTED`
- `socket-network-unreachable-error?` — `ENETUNREACH`
- `socket-host-unreachable-error?` — `EHOSTUNREACH`

New errno constants for use with `socket-error-errno-is?`:
`*einprogress*`, `*econnrefused*`, `*etimedout*`, `*eisconn*`,
`*econnreset*`, `*econnaborted*`, `*enetunreach*`, `*ehostunreach*`

### Unix Domain Sockets (AF_UNIX)

```scheme
(let ([path "/tmp/mysocket.sock"])
  (when (file-exists? path) (delete-file path))
  (let ([srv (make-unix-server-socket path)])
    (let ([cli (make-unix-client-socket path)])
      (socket-send cli (string->utf8 "hello"))
      (let ([conn (socket-accept srv)])
        (socket-recv conn 100)
        ...))))
```

### Socket timeouts

```scheme
(socket-set-timeout! sock 5 5)       ; 5 second receive and send timeout
(socket-set-timeout! sock 1.5 0.5)   ; float seconds are auto-split into sec/usec
(socket-set-timeout! sock 1 1 500000 500000)   ; explicit sec + usec
```

### UDP recvfrom with sender address

```scheme
(let-values ([(data host service) (socket-recvfrom/address sock 1024)])
  ...)
```

### Structured exceptions

All socket errors are raised as `socket-error` records:

```scheme
(guard (e [(socket-error? e)
           (display (socket-error-who e))
           (display (socket-error-errno e))
           (display (socket-error-message e))])
  (make-client-socket "bad.host" "80"))
```

### Run tests

```bash
bash .akku/env
bash tests/run.sh
```

The runner performs automated Echo Server/Client tests, a comprehensive unit test suite (bytevector, UDP loopback, connection errors, AF_UNIX, timeouts), and best-effort multicast tests.

#### Manual tests

Open two shells. In the first shell run a producer instance:
```sh
scheme --script tests/multicast.ss p4
```
And then in the second shell, run the consumer instance:
```sh
scheme --script tests/multicast.ss c4
```

#### Server/Client

Open two shells. In the first shell run:
```sh
scheme --script tests/server.ss
```

And then in the second shell, run the client:

```sh
scheme --script tests/client.ss
```

### Import this package in another project

This repository is released on AKKU. If you want to use it in another project:

```bash
# in your project root
akku install ufo-socket
mkdir -p socket

bash .akku/env
cd .akku/src/ufo-socket/
make

# make compiled files reachable
mv socket/*.o ../../../socket/
mv socket/*.so ../../../socket/

cd ../../..
bash .akku/env
```

## API Changes

### Breaking changes

- **`getnameinfo`** previously returned a `cons` pair `(host . service)`. It now returns `(values host service)`.
  ```scheme
  ;; old
  (let ([result (getnameinfo addr)])
    (car result)   ; host
    (cdr result))  ; service
  ;; new
  (let-values ([(host service) (getnameinfo addr)])
    ...)
  ```

### Semantic changes

- **`socket-accept`**: on non-blocking sockets, returns `#f` when no connection is pending (EAGAIN/EWOULDBLOCK/EINTR) instead of raising an exception.
- **`socket-recv`**: on non-blocking sockets, returns `#f` on EAGAIN/EWOULDBLOCK/EINTR instead of raising an exception. Returns `0` for EOF.
- **`socket-send`**: on non-blocking sockets, returns `#f` on EAGAIN/EWOULDBLOCK/EINTR instead of raising an exception.
- **`socket-shutdown`** and **`socket-peerinfo`**: now check errno and raise `socket-error` on failure.

### Backward-compatible improvements

- **`socket-send`** now supports non-zero `start` offsets and an optional `flags` argument.
- **`socket-recv!`** now supports `start`/`count` arguments for receiving into a sub-range of a bytevector.
- **`make-server-socket`** accepts optional `reuse-addr?` and `backlog` arguments at the end.
- **`connect-server-socket`** and **`connect-client-socket`** accept an optional `reuse-addr?` argument.
- **`make-client-socket`** accepts an optional `timeout` argument (float seconds) for connection timeout.
- **`socket-send-all`** now reports the real errno on failure instead of hardcoding `*eagain*`, and auto-retries on `EINTR` in blocking mode.
- **`connect-socket`** now tracks the real `errno` across the address-family fallback loop so error messages are accurate.

### New APIs

| Procedure | Description |
|---|---|
| `socket-recv!` | Zero-allocation recv into a caller-provided bytevector |
| `socket-recvfrom/address` | UDP `recvfrom` that returns `(values data host service)` |
| `socket-set-timeout!` | Sets `SO_RCVTIMEO` / `SO_SNDTIMEO` in seconds |
| `socket-set-nonblocking!` | Enable/disable `O_NONBLOCK` via `fcntl` |
| `socket-nonblocking?` | Query whether `O_NONBLOCK` is set |
| `socket-send-all` | Loop `socket-send` until the entire bytevector is sent (TCP). Returns total bytes sent. |
| `make-unix-client-socket` | Create an `AF_UNIX` client socket |
| `make-unix-server-socket` | Create an `AF_UNIX` listening socket |
| `mcast-drop-membership` | Leave a multicast group |
| `getaddrinfo*` | Resolve host/service to a list of addrinfo records |
| `socket-error?` | Predicate for the new structured exception type |
| `socket-error-who` / `-errno` / `-message` | Accessors for `socket-error` |
| `socket-error-errno-is?` | Generic errno comparison predicate |
| `socket-connection-refused-error?` | `ECONNREFUSED` predicate |
| `socket-timed-out-error?` | `ETIMEDOUT` predicate |
| `socket-already-connected-error?` | `EISCONN` predicate |
| `socket-connection-reset-error?` | `ECONNRESET` predicate |
| `socket-connection-aborted-error?` | `ECONNABORTED` predicate |
| `socket-network-unreachable-error?` | `ENETUNREACH` predicate |
| `socket-host-unreachable-error?` | `EHOSTUNREACH` predicate |

### New constants

- `*eagain*` `*ewouldblock*` `*eintr*` — for non-blocking error handling
- `*einprogress*` `*econnrefused*` `*etimedout*` `*eisconn*`
  `*econnreset*` `*econnaborted*` `*enetunreach*` `*ehostunreach*` — connection error constants
- `*so-rcvtimeo*` `*so-sndtimeo*` — for timeout control
- `*so-rcvbuf*` `*so-sndbuf*` — buffer size options
- `*tcp-nodelay*` — disable Nagle algorithm (IPPROTO_TCP level)
- `*af-unix*` — Unix domain socket address family
- `*ip-add-membership*` `*ip-drop-membership*` — multicast options
