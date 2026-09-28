// Networking for multiplayer (ROADMAP.md, Phase 5): TCP sockets and zstd compression.
// The Pascal side (source/net) frames messages and never sees a socket type; handles are
// 64-bit integers, and -1 means none. Every socket is non-blocking once connected.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <zstd.h>

// The largest window a patch may span (1 GB); a state is far smaller.
#define SR_WINDOWLOG_MAX 30

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET sr_socket;
#define SR_INVALID INVALID_SOCKET
#define sr_close_socket closesocket
static int last_socket_error(void) { return WSAGetLastError(); }
static int would_block(int e) { return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS; }
#else
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int sr_socket;
#define SR_INVALID (-1)
#define sr_close_socket close
static int last_socket_error(void) { return errno; }
static int would_block(int e) { return e == EWOULDBLOCK || e == EAGAIN || e == EINPROGRESS; }
#endif

static char net_error_text[256];

static void set_error(const char *what, int code) {
  snprintf(net_error_text, sizeof net_error_text, "%s failed (%d)", what, code);
}

const char *sr_net_error(void) { return net_error_text; }

int sr_net_init(void) {
#ifdef _WIN32
  static int started;
  if (!started) {
    WSADATA data;
    int code = WSAStartup(MAKEWORD(2, 2), &data);
    if (code != 0) {
      set_error("WSAStartup", code);
      return 0;
    }
    started = 1;
  }
#else
  // A peer that closes mid-send must not kill the process.
  signal(SIGPIPE, SIG_IGN);
#endif
  return 1;
}

static int set_nonblocking(sr_socket s) {
#ifdef _WIN32
  u_long on = 1;
  return ioctlsocket(s, FIONBIO, &on) == 0;
#else
  int flags = fcntl(s, F_GETFL, 0);
  return flags >= 0 && fcntl(s, F_SETFL, flags | O_NONBLOCK) == 0;
#endif
}

static void set_nodelay(sr_socket s) {
  int on = 1;
  setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&on, sizeof on);
}

// Listens on every interface (IPv4). Port 0 picks a free port; sr_net_local_port tells it.
int64_t sr_net_listen(int port) {
  sr_socket s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == SR_INVALID) {
    set_error("socket", last_socket_error());
    return -1;
  }
  int on = 1;
#ifndef _WIN32
  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char *)&on, sizeof on);
#else
  (void)on;
#endif
  struct sockaddr_in address;
  memset(&address, 0, sizeof address);
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_ANY);
  address.sin_port = htons((uint16_t)port);
  if (bind(s, (struct sockaddr *)&address, sizeof address) != 0) {
    set_error("bind", last_socket_error());
    sr_close_socket(s);
    return -1;
  }
  if (listen(s, 16) != 0 || !set_nonblocking(s)) {
    set_error("listen", last_socket_error());
    sr_close_socket(s);
    return -1;
  }
  return (int64_t)s;
}

int sr_net_local_port(int64_t handle) {
  struct sockaddr_in address;
  socklen_t size = sizeof address;
  if (getsockname((sr_socket)handle, (struct sockaddr *)&address, &size) != 0)
    return -1;
  return ntohs(address.sin_port);
}

// A pending connection, or -1 when there is none.
int64_t sr_net_accept(int64_t listener) {
  sr_socket s = accept((sr_socket)listener, NULL, NULL);
  if (s == SR_INVALID)
    return -1;
  if (!set_nonblocking(s)) {
    sr_close_socket(s);
    return -1;
  }
  set_nodelay(s);
  return (int64_t)s;
}

static int wait_socket(sr_socket s, int for_write, int timeout_ms) {
#ifdef _WIN32
  fd_set set;
  FD_ZERO(&set);
  FD_SET(s, &set);
  fd_set error_set;
  FD_ZERO(&error_set);
  FD_SET(s, &error_set);
  struct timeval timeout = {timeout_ms / 1000, (timeout_ms % 1000) * 1000};
  int ready = select(0, for_write ? NULL : &set, for_write ? &set : NULL, &error_set,
                     timeout_ms < 0 ? NULL : &timeout);
  if (ready > 0 && FD_ISSET(s, &error_set))
    return -1;
  return ready;
#else
  struct pollfd entry = {s, for_write ? POLLOUT : POLLIN, 0};
  int ready = poll(&entry, 1, timeout_ms);
  if (ready > 0 && (entry.revents & (POLLERR | POLLNVAL)))
    return -1;
  return ready;
#endif
}

// Connects to host:port within the timeout; host is a name or an address.
int64_t sr_net_connect(const char *host, int port, int timeout_ms) {
  char service[16];
  snprintf(service, sizeof service, "%d", port);
  struct addrinfo hints, *found = NULL;
  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  int code = getaddrinfo(host, service, &hints, &found);
  if (code != 0 || found == NULL) {
    set_error("getaddrinfo", code);
    return -1;
  }
  sr_socket result = SR_INVALID;
  for (struct addrinfo *entry = found; entry != NULL && result == SR_INVALID; entry = entry->ai_next) {
    sr_socket s = socket(entry->ai_family, entry->ai_socktype, entry->ai_protocol);
    if (s == SR_INVALID)
      continue;
    if (!set_nonblocking(s)) {
      sr_close_socket(s);
      continue;
    }
    if (connect(s, entry->ai_addr, (int)entry->ai_addrlen) != 0) {
      int error = last_socket_error();
      if (!would_block(error) || wait_socket(s, 1, timeout_ms) <= 0) {
        set_error("connect", error);
        sr_close_socket(s);
        continue;
      }
      int socket_error = 0;
      socklen_t size = sizeof socket_error;
      getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&socket_error, &size);
      if (socket_error != 0) {
        set_error("connect", socket_error);
        sr_close_socket(s);
        continue;
      }
    }
    set_nodelay(s);
    result = s;
  }
  freeaddrinfo(found);
  return result == SR_INVALID ? -1 : (int64_t)result;
}

// Bytes sent (possibly 0 when the send buffer is full), or -1 when the connection is gone.
int sr_net_send(int64_t handle, const void *data, int size) {
#ifdef MSG_NOSIGNAL
  int sent = (int)send((sr_socket)handle, data, size, MSG_NOSIGNAL);
#else
  int sent = (int)send((sr_socket)handle, data, size, 0);
#endif
  if (sent >= 0)
    return sent;
  int error = last_socket_error();
  if (would_block(error))
    return 0;
  set_error("send", error);
  return -1;
}

// Bytes received, 0 when nothing is waiting, or -1 when the connection is closed or failed.
int sr_net_recv(int64_t handle, void *data, int size) {
  int received = (int)recv((sr_socket)handle, data, size, 0);
  if (received > 0)
    return received;
  if (received == 0) {
    set_error("recv: closed", 0);
    return -1;
  }
  int error = last_socket_error();
  if (would_block(error))
    return 0;
  set_error("recv", error);
  return -1;
}

// 1 when the socket can be read (or has failed), 0 on timeout. A negative timeout waits.
int sr_net_wait(int64_t handle, int timeout_ms) {
  int ready = wait_socket((sr_socket)handle, 0, timeout_ms);
  return ready != 0 ? 1 : 0;
}

void sr_net_close(int64_t handle) {
  if (handle >= 0)
    sr_close_socket((sr_socket)handle);
}

// zstd. Sizes are 64-bit; a negative result is an error, and sr_net_error says which.

int64_t sr_zstd_bound(int64_t size) { return (int64_t)ZSTD_compressBound((size_t)size); }

static int64_t zstd_result(const char *what, size_t result) {
  if (ZSTD_isError(result)) {
    snprintf(net_error_text, sizeof net_error_text, "%s: %s", what, ZSTD_getErrorName(result));
    return -1;
  }
  return (int64_t)result;
}

// The decompressed size a frame declares, or -1.
int64_t sr_zstd_content_size(const void *source, int64_t size) {
  unsigned long long content = ZSTD_getFrameContentSize(source, (size_t)size);
  if (content == ZSTD_CONTENTSIZE_UNKNOWN || content == ZSTD_CONTENTSIZE_ERROR)
    return -1;
  return (int64_t)content;
}

static unsigned window_log_for(int64_t size) {
  unsigned log = 10;
  while (log < SR_WINDOWLOG_MAX && ((int64_t)1 << log) < size)
    log++;
  return log;
}

// Compresses source; with a reference, as zstd's --patch-from does: the reference is a
// prefix the frame may copy from, so a state close to the reference compresses to its
// changes. Reference may be NULL.
int64_t sr_zstd_compress(void *target, int64_t capacity, const void *source, int64_t size,
                         const void *reference, int64_t reference_size, int level) {
  ZSTD_CCtx *context = ZSTD_createCCtx();
  if (context == NULL) {
    set_error("ZSTD_createCCtx", 0);
    return -1;
  }
  ZSTD_CCtx_setParameter(context, ZSTD_c_compressionLevel, level);
  ZSTD_CCtx_setParameter(context, ZSTD_c_checksumFlag, 1);
  if (reference != NULL && reference_size > 0) {
    int64_t span = reference_size > size ? reference_size : size;
    ZSTD_CCtx_setParameter(context, ZSTD_c_windowLog, (int)window_log_for(span));
    ZSTD_CCtx_setParameter(context, ZSTD_c_enableLongDistanceMatching, 1);
    ZSTD_CCtx_refPrefix(context, reference, (size_t)reference_size);
  }
  size_t result = ZSTD_compress2(context, target, (size_t)capacity, source, (size_t)size);
  ZSTD_freeCCtx(context);
  return zstd_result("ZSTD_compress2", result);
}

// Decompresses a frame sr_zstd_compress made, with the same reference.
int64_t sr_zstd_decompress(void *target, int64_t capacity, const void *source, int64_t size,
                           const void *reference, int64_t reference_size) {
  ZSTD_DCtx *context = ZSTD_createDCtx();
  if (context == NULL) {
    set_error("ZSTD_createDCtx", 0);
    return -1;
  }
  ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, SR_WINDOWLOG_MAX);
  if (reference != NULL && reference_size > 0)
    ZSTD_DCtx_refPrefix(context, reference, (size_t)reference_size);
  size_t result = ZSTD_decompressDCtx(context, target, (size_t)capacity, source, (size_t)size);
  ZSTD_freeDCtx(context);
  return zstd_result("ZSTD_decompressDCtx", result);
}
