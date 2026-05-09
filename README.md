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

### Non-blocking sockets

```
[proc] socket-accept: Accept a connection. On blocking sockets this waits until
                       a peer connects. On non-blocking sockets it returns #f
                       when no connection is pending (EAGAIN/EWOULDBLOCK/EINTR).
```

### Server socket with SO_REUSEADDR

```scheme
(make-server-socket "8080" (address-family inet) (socket-domain stream)
                    (ip-protocol tcp) #t)   ; last arg enables SO_REUSEADDR
```

The legacy parameter `create-socket-reuseaddr` still works, but passing an explicit argument is preferred.

### Run tests

```bash
bash .akku/env
bash tests/run.sh
```

The runner performs automated Echo Server/Client tests. Multicast tests are best-effort: they may be skipped on containers or VMs where multicast forwarding is not available.

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
