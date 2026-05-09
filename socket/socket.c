/*
 * C/OS layer for Chez scheme basic sockets.
 *
 * Try and keep this as minimal as possible, with most of the work done at the scheme level.
 *
 * This module should only contain variable definitions and struct accessors so
 * that scheme doesn't need to track offsets etc.
 *
 * Written by Akce 2019-2020.
 * SPDX-License-Identifier: Unlicense
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netdb.h>
#include <arpa/inet.h>	// inet_pton
#include <errno.h>
#include <fcntl.h>

#include <stdio.h>	// printf
#include <stdlib.h>	// calloc, malloc
#include <unistd.h>	// close
#include <string.h>	// strncpy

// TODO set -1 #if !defined(n).
#define C_CONST_INT(n) const int c_ ## n = n

/* Constants: required by Basic Sockets (SRFI-106). */
C_CONST_INT(AF_INET);
C_CONST_INT(AF_INET6);
C_CONST_INT(AF_UNSPEC);

C_CONST_INT(SOCK_STREAM);
C_CONST_INT(SOCK_DGRAM);

C_CONST_INT(AI_CANONNAME);
C_CONST_INT(AI_NUMERICHOST);
C_CONST_INT(AI_V4MAPPED);
C_CONST_INT(AI_ALL);
C_CONST_INT(AI_ADDRCONFIG);

C_CONST_INT(IPPROTO_IP);
C_CONST_INT(IPPROTO_TCP);
C_CONST_INT(IPPROTO_UDP);

C_CONST_INT(MSG_PEEK);
C_CONST_INT(MSG_OOB);
C_CONST_INT(MSG_WAITALL);

C_CONST_INT(SHUT_RD);
C_CONST_INT(SHUT_WR);
C_CONST_INT(SHUT_RDWR);

/* Constants: extensions to Basic Sockets (SRFI-106). */

C_CONST_INT(SOMAXCONN);
C_CONST_INT(AI_NUMERICSERV);
C_CONST_INT(AI_PASSIVE);

/* Socket level (SOL_) */
C_CONST_INT(SOL_SOCKET);

/* SOL_SOCKET socket level Options. See socket(7) */
// TODO There's still plenty undefined, only adding the more interesting ones for now.
C_CONST_INT(SO_ACCEPTCONN);	/* bool read-only */
C_CONST_INT(SO_BROADCAST);	/* bool datagram only. */
C_CONST_INT(SO_DOMAIN);		/* int read-only: eg, AF_INET6. */
C_CONST_INT(SO_DONTROUTE);	/* bool */
C_CONST_INT(SO_ERROR);		/* read-only: value cleared after read. */
C_CONST_INT(SO_KEEPALIVE);	/* bool */
C_CONST_INT(SO_LINGER);		/* linger struct. */
C_CONST_INT(SO_OOBINLINE);	/* bool */
C_CONST_INT(SO_PROTOCOL);	/* int read-only: eg, IPPROTO_TCP */
C_CONST_INT(SO_REUSEADDR);	/* bool */
C_CONST_INT(SO_TYPE);		/* int read-only: eg, SOCK_STREAM */
C_CONST_INT(SO_RCVBUF);		/* int */
C_CONST_INT(SO_SNDBUF);		/* int */
C_CONST_INT(TCP_NODELAY);		/* bool: IPPROTO_TCP level */

const int c_S_SIZEOF_SOCKADDR = sizeof(struct sockaddr_storage);

/* IPPROTO_IP socket level options. See ip(7) */

/* IP multicast. */
C_CONST_INT(IP_MULTICAST_LOOP);		/* bool */
C_CONST_INT(IP_MULTICAST_TTL);		/* int range: 1-255. */
C_CONST_INT(IP_MULTICAST_IF);		/* struct in_addr */
C_CONST_INT(IP_ADD_MEMBERSHIP);		/* struct ip_mreqn or older struct ip_mreq */
C_CONST_INT(IP_DROP_MEMBERSHIP);	/* struct ip_mreqn or older struct ip_mreq */

/* getnameinfo(3) flags */
C_CONST_INT(NI_NAMEREQD);
C_CONST_INT(NI_DGRAM);
C_CONST_INT(NI_NOFQDN);
C_CONST_INT(NI_NUMERICHOST);
C_CONST_INT(NI_NUMERICSERV);
/* glibc 2.3.4+ extensions */
#if 0
/* Remove for now: these aren't included in my glibc version. */
C_CONST_INT(NI_IDN);
C_CONST_INT(NI_IDN_ALLOW_UNASSIGNED);
C_CONST_INT(NI_IDN_USE_STD3_ASCII_RULES);
#endif
/* These are sensible buffer defaults and may be glibc extensions; they should be checked via C feature flags... */
/* There's a case for hardcoding these on the scheme side so they're always available. */
C_CONST_INT(NI_MAXHOST);
C_CONST_INT(NI_MAXSERV);

/* Socket timeout options. */
C_CONST_INT(SO_RCVTIMEO);
C_CONST_INT(SO_SNDTIMEO);

/* Errno values commonly needed for non-blocking socket handling. */
C_CONST_INT(EAGAIN);
C_CONST_INT(EWOULDBLOCK);
C_CONST_INT(EINTR);

/* Thread-safe errno accessor (avoids relying on Chez internals). */
int c_errno(void) { return errno; }

/* socket_set_timeout: set receive and/or send timeout.
 * Pass negative values to leave a timeout unchanged.
 * returns: 0 on success, -1 on error (errno set).
 */
int
socket_set_timeout(int fd, long recv_sec, long recv_usec, long send_sec, long send_usec)
	{
	int rc = 0;
	if (recv_sec >= 0 || recv_usec >= 0)
		{
		struct timeval tv = { .tv_sec = recv_sec, .tv_usec = recv_usec };
		rc = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
		if (rc < 0) return rc;
		}
	if (send_sec >= 0 || send_usec >= 0)
		{
		struct timeval tv = { .tv_sec = send_sec, .tv_usec = send_usec };
		rc = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
		}
	return rc;
	}

/* AF_UNIX support. */
C_CONST_INT(AF_UNIX);
const int c_SIZEOF_SOCKADDR_UN = sizeof(struct sockaddr_un);

struct sockaddr_un*
make_sockaddr_un(const char* path)
	{
	struct sockaddr_un* addr = calloc(sizeof(*addr), 1);
	if (addr)
		{
		addr->sun_family = AF_UNIX;
		strncpy(addr->sun_path, path, sizeof(addr->sun_path) - 1);
		}
	return addr;
	}

/* socket_set_nonblocking: enable or disable O_NONBLOCK.
 * returns: 0 on success, -1 on error (errno set).
 */
int
socket_set_nonblocking(int fd, int nonblocking)
	{
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags < 0)
		return -1;
	flags = nonblocking ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK);
	return fcntl(fd, F_SETFL, flags);
	}

/* socket_get_nonblocking: query O_NONBLOCK status.
 * returns: 1 if nonblocking, 0 if blocking, -1 on error (errno set).
 */
int
socket_get_nonblocking(int fd)
	{
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags < 0)
		return -1;
	return (flags & O_NONBLOCK) ? 1 : 0;
	}

/* recv_offset / send_offset: recv/send into/from a bytevector at an offset.
 * These exist because Chez Scheme's FFI cannot express a bytevector pointer
 * plus an arbitrary offset, so without these helpers we must allocate a
 * temporary buffer and copy.
 */
ssize_t
recv_offset(int fd, void* buf, size_t offset, size_t len, int flags)
	{
	return recv(fd, (char*)buf + offset, len, flags);
	}

ssize_t
send_offset(int fd, const void* buf, size_t offset, size_t len, int flags)
	{
	return send(fd, (char*)buf + offset, len, flags);
	}

/* socket_get_linger / socket_set_linger: helpers for SO_LINGER struct.
 * SO_LINGER cannot be read/written with the simple int-based socket-get-int.
 */
int
socket_get_linger(int fd, int* enabled, int* seconds)
	{
	struct linger l;
	socklen_t len = sizeof(l);
	if (getsockopt(fd, SOL_SOCKET, SO_LINGER, &l, &len) != 0)
		return -1;
	*enabled = l.l_onoff;
	*seconds = l.l_linger;
	return 0;
	}

int
socket_set_linger(int fd, int enabled, int seconds)
	{
	struct linger l = { enabled, seconds };
	return setsockopt(fd, SOL_SOCKET, SO_LINGER, &l, sizeof(l));
	}

/* See getaddrinfo(2) for a full C client/server example. */

/* addrinfo accessors. */
int addrinfo_flags(const struct addrinfo* ai) { return ai->ai_flags; }
int addrinfo_family(const struct addrinfo* ai) { return ai->ai_family; }
int addrinfo_socktype(const struct addrinfo* ai) { return ai->ai_socktype; }
int addrinfo_protocol(const struct addrinfo* ai) { return ai->ai_protocol; }
socklen_t addrinfo_addrlen(const struct addrinfo* ai) { return ai->ai_addrlen; }
struct sockaddr* addrinfo_addr(const struct addrinfo* ai) { return ai->ai_addr; }
const struct addrinfo* addrinfo_next(const struct addrinfo* ai) { return ai->ai_next; }

/* create an addrinfo struct suitable for use as hints with getaddrinfo.
 * getaddrinfo(3) specifies that only flags, family, socktype, and protocol are used as hints.
 */
struct addrinfo*
make_addrinfo_hints(int flags, int family, int socktype, int protocol)
	{
	/* calloc(3) will zero the alloc'd memory. */
	struct addrinfo* hints = calloc(sizeof(*hints), 1);
	if (hints)
		{
		hints->ai_flags = flags;
		hints->ai_family = family;
		hints->ai_socktype = socktype;
		hints->ai_protocol = protocol;
		}
	return hints;
	}

/* mcast_add_membership: Add socket to IPv4 multicast group.
 * returns:
 *   = 0 on success
 *   = -1 setsockopt error
 *   = -2 address/node string conversion failure.
 */
int
mcast4_add_membership(int fd, const char* node, int interface)
	{
	int rc = -2;
#if defined(__linux__)
	struct ip_mreqn req =
		{
		.imr_ifindex = interface,
		};
	if (inet_pton(AF_INET, node, &req.imr_multiaddr) == 1)
		{
		/* Node address converted successfully. */
		rc = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &req, sizeof(req));
		}
#else
	/* Portable fallback using ip_mreq (interface index not supported). */
	struct ip_mreq req;
	if (inet_pton(AF_INET, node, &req.imr_multiaddr) == 1)
		{
		req.imr_interface.s_addr = INADDR_ANY;
		rc = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &req, sizeof(req));
		}
#endif
	return rc;
	}

/* mcast6_add_membership: Add socket to IPv6 multicast group.
 * returns:
 *   = 0 on success
 *   = -1 setsockopt error
 *   = -2 address/node string conversion failure.
 */
int
mcast6_add_membership(int fd, const char* node, int interface)
	{
	int rc = -2;
	struct ipv6_mreq req =
		{
		.ipv6mr_interface = interface,
		};
	if (inet_pton(AF_INET6, node, &req.ipv6mr_multiaddr) == 1)
		{
		/* Node address converted successfully. */
		rc = setsockopt(fd, IPPROTO_IPV6, IPV6_ADD_MEMBERSHIP, &req, sizeof(req));
		}
	return rc;
	}

/* mcast4_drop_membership: Remove socket from IPv4 multicast group.
 * returns: same as mcast4_add_membership.
 */
int
mcast4_drop_membership(int fd, const char* node, int interface)
	{
	int rc = -2;
#if defined(__linux__)
	struct ip_mreqn req =
		{
		.imr_ifindex = interface,
		};
	if (inet_pton(AF_INET, node, &req.imr_multiaddr) == 1)
		{
		rc = setsockopt(fd, IPPROTO_IP, IP_DROP_MEMBERSHIP, &req, sizeof(req));
		}
#else
	struct ip_mreq req;
	if (inet_pton(AF_INET, node, &req.imr_multiaddr) == 1)
		{
		req.imr_interface.s_addr = INADDR_ANY;
		rc = setsockopt(fd, IPPROTO_IP, IP_DROP_MEMBERSHIP, &req, sizeof(req));
		}
#endif
	return rc;
	}

/* mcast6_drop_membership: Remove socket from IPv6 multicast group.
 * returns: same as mcast6_add_membership.
 */
int
mcast6_drop_membership(int fd, const char* node, int interface)
	{
	int rc = -2;
	struct ipv6_mreq req =
		{
		.ipv6mr_interface = interface,
		};
	if (inet_pton(AF_INET6, node, &req.ipv6mr_multiaddr) == 1)
		{
		rc = setsockopt(fd, IPPROTO_IPV6, IPV6_DROP_MEMBERSHIP, &req, sizeof(req));
		}
	return rc;
	}
