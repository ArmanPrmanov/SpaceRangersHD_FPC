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
// The network thread waits on a host's listener and every client at once.
#define FD_SETSIZE 256
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET sr_socket;
#define SR_INVALID INVALID_SOCKET
#define sr_close_socket closesocket
static int last_socket_error(void) { return WSAGetLastError(); }
static int would_block(int e) { return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS; }
#else
#include <arpa/inet.h>
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

// Waits until one of the sockets can be read (or has failed), up to the timeout; 1 when one
// can, 0 on timeout. The network thread waits on its listener and every connection at once.
int sr_net_wait_many(const int64_t *handles, int count, int timeout_ms) {
  if (count <= 0)
    return 0;
#ifdef _WIN32
  fd_set set;
  FD_ZERO(&set);
  for (int i = 0; i < count && i < FD_SETSIZE; i++)
    FD_SET((sr_socket)handles[i], &set);
  fd_set error_set = set;
  struct timeval timeout = {timeout_ms / 1000, (timeout_ms % 1000) * 1000};
  int ready = select(0, &set, NULL, &error_set, timeout_ms < 0 ? NULL : &timeout);
  return ready > 0 ? 1 : 0;
#else
  struct pollfd entries[256];
  if (count > 256)
    count = 256;
  for (int i = 0; i < count; i++) {
    entries[i].fd = (int)handles[i];
    entries[i].events = POLLIN;
    entries[i].revents = 0;
  }
  return poll(entries, (nfds_t)count, timeout_ms) > 0 ? 1 : 0;
#endif
}

void sr_net_close(int64_t handle) {
  if (handle >= 0)
    sr_close_socket((sr_socket)handle);
}

static void append_address(char *out, int capacity, const struct in_addr *address) {
  char text[INET_ADDRSTRLEN];
  if (inet_ntop(AF_INET, (void *)address, text, sizeof text) == NULL)
    return;
  // Loopback is no use to another machine; a duplicate says nothing new.
  if (strncmp(text, "127.", 4) == 0 || strstr(out, text) != NULL)
    return;
  size_t used = strlen(out);
  if (used + strlen(text) + 2 >= (size_t)capacity)
    return;
  if (used > 0)
    strcat(out, ",");
  strcat(out, text);
}

// The machine's IPv4 addresses that other machines may reach it by, comma-separated, for the
// host's menu (ROADMAP.md, Phase 5). The host name's addresses, else the address of the
// interface a route to the internet would take (a UDP connect sends nothing). Returns their
// number; out may be empty.
int sr_net_local_addresses(char *out, int capacity) {
  if (capacity <= 0)
    return 0;
  out[0] = 0;
  char name[256];
  if (gethostname(name, sizeof name) == 0) {
    name[sizeof name - 1] = 0;
    struct addrinfo hints, *found = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(name, NULL, &hints, &found) == 0) {
      for (struct addrinfo *entry = found; entry != NULL; entry = entry->ai_next)
        append_address(out, capacity, &((struct sockaddr_in *)entry->ai_addr)->sin_addr);
      freeaddrinfo(found);
    }
  }
  if (out[0] == 0) {
    sr_socket s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s != SR_INVALID) {
      struct sockaddr_in address;
      memset(&address, 0, sizeof address);
      address.sin_family = AF_INET;
      address.sin_port = htons(53);
      address.sin_addr.s_addr = htonl(0x08080808);
      if (connect(s, (struct sockaddr *)&address, sizeof address) == 0) {
        socklen_t size = sizeof address;
        if (getsockname(s, (struct sockaddr *)&address, &size) == 0)
          append_address(out, capacity, &address.sin_addr);
      }
      sr_close_socket(s);
    }
  }
  int count = out[0] == 0 ? 0 : 1;
  for (const char *p = out; *p != 0; p++)
    if (*p == ',')
      count++;
  return count;
}

// XXH64 (xxHash, 64-bit) of one block with a seed. The data hash of a game install chains
// it over fixed-size chunks of each file; it runs at memory speed, where a byte loop in
// Pascal would take seconds over the ~1.6 GB of packages.
#define SR_P1 0x9E3779B185EBCA87ULL
#define SR_P2 0xC2B2AE3D27D4EB4FULL
#define SR_P3 0x165667B19E3779F9ULL
#define SR_P4 0x85EBCA77C2B2AE63ULL
#define SR_P5 0x27D4EB2F165667C5ULL

static uint64_t rotl64(uint64_t x, int r) { return (x << r) | (x >> (64 - r)); }

static uint64_t read64(const uint8_t *p) {
  uint64_t v;
  memcpy(&v, p, 8);
  return v;
}

static uint32_t read32(const uint8_t *p) {
  uint32_t v;
  memcpy(&v, p, 4);
  return v;
}

static uint64_t xxh_round(uint64_t acc, uint64_t input) {
  acc += input * SR_P2;
  acc = rotl64(acc, 31);
  return acc * SR_P1;
}

static uint64_t xxh_merge(uint64_t acc, uint64_t value) {
  acc ^= xxh_round(0, value);
  return acc * SR_P1 + SR_P4;
}

uint64_t sr_hash64(const void *data, int64_t size, uint64_t seed) {
  const uint8_t *p = (const uint8_t *)data;
  const uint8_t *end = p + size;
  uint64_t h;
  if (size >= 32) {
    uint64_t v1 = seed + SR_P1 + SR_P2, v2 = seed + SR_P2, v3 = seed, v4 = seed - SR_P1;
    const uint8_t *limit = end - 32;
    do {
      v1 = xxh_round(v1, read64(p));
      v2 = xxh_round(v2, read64(p + 8));
      v3 = xxh_round(v3, read64(p + 16));
      v4 = xxh_round(v4, read64(p + 24));
      p += 32;
    } while (p <= limit);
    h = rotl64(v1, 1) + rotl64(v2, 7) + rotl64(v3, 12) + rotl64(v4, 18);
    h = xxh_merge(h, v1);
    h = xxh_merge(h, v2);
    h = xxh_merge(h, v3);
    h = xxh_merge(h, v4);
  } else
    h = seed + SR_P5;
  h += (uint64_t)size;
  while (p + 8 <= end) {
    h ^= xxh_round(0, read64(p));
    h = rotl64(h, 27) * SR_P1 + SR_P4;
    p += 8;
  }
  if (p + 4 <= end) {
    h ^= (uint64_t)read32(p) * SR_P1;
    h = rotl64(h, 23) * SR_P2 + SR_P3;
    p += 4;
  }
  while (p < end) {
    h ^= (*p) * SR_P5;
    h = rotl64(h, 11) * SR_P1;
    p++;
  }
  h ^= h >> 33;
  h *= SR_P2;
  h ^= h >> 29;
  h *= SR_P3;
  h ^= h >> 32;
  return h;
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
