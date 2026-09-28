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
procedure sr_net_close(Handle: Int64); cdecl; external 'gamenative';
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
