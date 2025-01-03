# ufo-socket

This repository is basically a re-organized version of [chez-socket](https://github.com/akce/chez-socket). I just did some work making it compatible with [AKKU](https://akkuscm.org/) and [chez-exe](https://github.com/gwatt/chez-exe) and fixing bugs. Apparently, it brings several convenient features for reusing it in other softwares.

This repository requires Linux socket library.

## Prerequire
Chez Scheme, [AKKU](https://akkuscm.org/) and [chez-exe](https://github.com/gwatt/chez-exe). In addition, you should firstly compile the C dependency with command.

```bash 
make
```

## How to use?

`(import (ufo-socket))` to use [srfi-106](https://srfi.schemers.org/srfi-106/) plus local extensions. These are highly experimental and have lots of room for improvement.

These include:

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
Some socket options whose values are integers or boolean may also be retrieved and set. For boolean options, use 0 for FALSE, and 1 for TRUE.
See the *extended* source file for a list of the options that are defined.
```
[proc] socket-get-int: Get integer socket option.
```
```
[proc] socket-set-int!: Set integer socket option.
```
```
[proc] getnameinfo: Get host and service information from a socket.
```
### Run tests from source
```bash 
#in you project root
#solve scheme depdendency
akku install 
bash .akku/env
#compile c source
make 
```

#### IPv4 session
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

### Import this package in other project
This repository is released on AKKU, if you want to use it in other project, some command should be executed:

```bash 
#in you project root
akku install ufo-socket
#if you have directory with same name, just let this command go
mkdir socket

bash .akku/env
cd .akku/src/ufo-socket/
make

#following two command to make compiled files reachable
mv socket/*.o ../../../socket/
mv socket/*.so ../../../socket/

cd ../../..
#make scheme code reachable in your scheme session
bash .akku/env
```