unit NetNative;
{$MODE delphi}
{$EXCESSPRECISION OFF}
// CHANGE: ENHANCEMENT - Sockets and zstd for multiplayer (ROADMAP.md, Phase 5), from
// platform/net_native.c. A handle is an Int64; -1 means none.
interface
function sr_net_init: Integer; cdecl; external 'gamenative';
function sr_net_error: PAnsiChar; cdecl; external 'gamenative';
function sr_net_listen(Port: Integer): Int64; cdecl; external 'gamenative';
function sr_net_local_port(Handle: Int64): Integer; cdecl; external 'gamenative';
function sr_net_accept(Listener: Int64): Int64; cdecl; external 'gamenative';
function sr_net_connect(Host: PAnsiChar; Port, TimeoutMs: Integer): Int64; cdecl; external 'gamenative';
function sr_net_send(Handle: Int64; Data: Pointer; Size: Integer): Integer; cdecl; external 'gamenative';
function sr_net_recv(Handle: Int64; Data: Pointer; Size: Integer): Integer; cdecl; external 'gamenative';
function sr_net_wait(Handle: Int64; TimeoutMs: Integer): Integer; cdecl; external 'gamenative';
function sr_net_wait_many(Handles: PInt64; Count, TimeoutMs: Integer): Integer; cdecl; external 'gamenative';
procedure sr_net_close(Handle: Int64); cdecl; external 'gamenative';
// The machine's IPv4 addresses, comma-separated, into Output; returns how many.
function sr_net_local_addresses(Output: PAnsiChar; Capacity: Integer): Integer; cdecl; external 'gamenative';
// CHANGE: ENHANCEMENT - Size random bytes from the operating system into Data (the reconnection
// token; never the game's generators); 0 when it gave none.
function sr_random_bytes(Data: Pointer; Size: Integer): Integer; cdecl; external 'gamenative';
// XXH64 of one block; chained over a file's chunks by passing the last result as the seed.
function sr_hash64(Data: Pointer; Size: Int64; Seed: QWord): QWord; cdecl; external 'gamenative';
function sr_zstd_bound(Size: Int64): Int64; cdecl; external 'gamenative';
function sr_zstd_content_size(Source: Pointer; Size: Int64): Int64; cdecl; external 'gamenative';
function sr_zstd_compress(
    Target: Pointer;
    Capacity: Int64;
    Source: Pointer;
    Size: Int64;
    Reference: Pointer;
    ReferenceSize: Int64;
    Level: Integer
): Int64; cdecl; external 'gamenative';
function sr_zstd_decompress(
    Target: Pointer;
    Capacity: Int64;
    Source: Pointer;
    Size: Int64;
    Reference: Pointer;
    ReferenceSize: Int64
): Int64; cdecl; external 'gamenative';
implementation
end.
