{$EXCESSPRECISION OFF}
unit NetTransport;

// CHANGE: ENHANCEMENT - Message transport for multiplayer (ROADMAP.md, Phase 5). A
// connection carries length-prefixed messages over TCP: a 4-byte little-endian length, then
// a kind byte and the payload. Sockets are non-blocking; Poll moves whatever bytes the
// network takes or gives, so the UI thread can call it every frame without waiting.
interface
uses
  EC_Buf;
type
  TNetMessageKind = type Byte;

  TNetConnection = class
  private
    FHandle: Int64;
    FOutgoing: TBufEC;
    FSentOffset: Integer;
    FIncoming: TBufEC;
    FClosed: Boolean;
    FError: AnsiString;
    FBytesSent, FBytesReceived: Int64;
    procedure Fail(const Text: AnsiString);
    procedure Compact;
  public
    // Takes ownership of a connected socket.
    constructor Create(Handle: Int64);
    destructor Destroy; override;
    // Connects within the timeout; nil when it fails (LastConnectError says why).
    class function Connect(const Host: AnsiString; Port, TimeoutMs: Integer): TNetConnection;
    procedure Send(Kind: TNetMessageKind; Payload: TBufEC); overload;
    procedure Send(Kind: TNetMessageKind; Payload: Pointer; Size: Integer); overload;
    // Sends and receives what the socket takes without blocking.
    procedure Poll;
    // Takes the next whole message; Payload gets its bytes, positioned at the start.
    function Receive(out Kind: TNetMessageKind; Payload: TBufEC): Boolean;
    // Waits up to TimeoutMs for bytes to arrive, then polls.
    procedure Wait(TimeoutMs: Integer);
    // Sends everything queued, waiting up to TimeoutMs.
    function FlushAll(TimeoutMs: Integer): Boolean;
    procedure Close;
    // CHANGE: ENHANCEMENT - Closes the connection with Text as its Error (unless it has one), as
    // a failed socket call does: the network thread's silence timeout.
    procedure Abort(const Text: AnsiString);
    function PendingSendBytes: Integer;
    // CHANGE: ENHANCEMENT - The message being received: the bytes of it that are here and its
    // whole size with the length prefix (0 and 0 when none has started), for a join's progress.
    procedure IncomingProgress(out Have, Size: Integer);
    property Closed: Boolean read FClosed;
    // The socket, for waiting on several at once (sr_net_wait_many); -1 once closed.
    property Handle: Int64 read FHandle;
    property Error: AnsiString read FError;
    property BytesSent: Int64 read FBytesSent;
    property BytesReceived: Int64 read FBytesReceived;
  end;

  TNetListener = class
  private
    FHandle: Int64;
    FPort: Integer;
  public
    // Listens on every interface; port 0 picks a free one. Raises when it cannot.
    constructor Create(Port: Integer);
    destructor Destroy; override;
    // A new connection, or nil.
    function Accept: TNetConnection;
    property Port: Integer read FPort;
    property Handle: Int64 read FHandle;
  end;

const
  // A message larger than this is a protocol error, not a state.
  MaximumMessageSize = 512 * 1024 * 1024;

var
  LastConnectError: AnsiString;

procedure InitializeNetwork;
function NetworkErrorText: AnsiString;
// The machine's IPv4 addresses other machines may reach it by, comma-separated; '' when none
// is known.
function LocalAddressText: AnsiString;
implementation
uses
  SysUtils,
  NetNative;

var
  NetworkStarted: Boolean;

procedure InitializeNetwork;
begin
  if NetworkStarted then
    Exit;
  if sr_net_init = 0 then
    raise Exception.Create('Cannot start networking: ' + NetworkErrorText);
  NetworkStarted := True;
end;

function NetworkErrorText: AnsiString;
begin
  Result := AnsiString(sr_net_error);
end;

function LocalAddressText: AnsiString;
var
  Buffer: array[0..511] of AnsiChar;
begin
  InitializeNetwork;
  sr_net_local_addresses(@Buffer[0], Length(Buffer));
  Result := AnsiString(PAnsiChar(@Buffer[0]));
end;

constructor TNetConnection.Create(Handle: Int64);
begin
  inherited Create;
  FHandle := Handle;
  FOutgoing := TBufEC.Create;
  FIncoming := TBufEC.Create;
end;

destructor TNetConnection.Destroy;
begin
  Close;
  FOutgoing.Free;
  FIncoming.Free;
  inherited;
end;

class function TNetConnection.Connect(const Host: AnsiString; Port, TimeoutMs: Integer): TNetConnection;
var
  Handle: Int64;
begin
  InitializeNetwork;
  Result := nil;
  Handle := sr_net_connect(PAnsiChar(Host), Port, TimeoutMs);
  if Handle < 0 then
  begin
    LastConnectError := NetworkErrorText;
    Exit;
  end;
  Result := TNetConnection.Create(Handle);
end;

procedure TNetConnection.Fail(const Text: AnsiString);
begin
  if FError = '' then
    FError := Text;
  Close;
end;

procedure TNetConnection.Abort(const Text: AnsiString);
begin
  Fail(Text);
end;

procedure TNetConnection.Close;
begin
  if FHandle >= 0 then
    sr_net_close(FHandle);
  FHandle := -1;
  FClosed := True;
end;

procedure TNetConnection.Send(Kind: TNetMessageKind; Payload: TBufEC);
begin
  if Payload = nil then
    Send(Kind, nil, 0)
  else
    Send(Kind, Payload.Data, Payload.DataSize);
end;

procedure TNetConnection.Send(Kind: TNetMessageKind; Payload: Pointer; Size: Integer);
begin
  if FClosed then
    Exit;
  if (Size < 0) or (Size + 1 > MaximumMessageSize) then
    raise Exception.CreateFmt('Network message too large (%d bytes)', [Size]);
  FOutgoing.SetPosition(FOutgoing.DataSize);
  FOutgoing.AddInt32(Size + 1);
  FOutgoing.AddByte(Kind);
  if Size > 0 then
    FOutgoing.AddBytes(Payload, Size);
  Poll;
end;

function TNetConnection.PendingSendBytes: Integer;
begin
  Result := FOutgoing.DataSize - FSentOffset;
end;

procedure TNetConnection.IncomingProgress(out Have, Size: Integer);
begin
  Have := FIncoming.DataSize;
  Size := 0;
  if Have >= 4 then
    Size := 4 + FIncoming.GetInt32At(0);
  if Size < Have then
    Size := Have;
end;

// Drops the bytes already sent once they are most of the buffer.
procedure TNetConnection.Compact;
var
  Rest: Integer;
begin
  if FSentOffset = 0 then
    Exit;
  Rest := FOutgoing.DataSize - FSentOffset;
  if Rest = 0 then
  begin
    FOutgoing.Clear;
    FSentOffset := 0;
  end
  else if FSentOffset > Rest then
  begin
    Move(PByte(FOutgoing.Data)[FSentOffset], FOutgoing.Data^, Rest);
    FOutgoing.SetSize(Rest);
    FSentOffset := 0;
  end;
end;

procedure TNetConnection.Poll;
const
  ChunkSize = 64 * 1024;
var
  Count, Size: Integer;
  Chunk: array[0..ChunkSize - 1] of Byte;
begin
  if FClosed then
    Exit;
  while FSentOffset < FOutgoing.DataSize do
  begin
    Size := FOutgoing.DataSize - FSentOffset;
    if Size > ChunkSize then
      Size := ChunkSize;
    Count := sr_net_send(FHandle, @PByte(FOutgoing.Data)[FSentOffset], Size);
    if Count < 0 then
    begin
      Fail(NetworkErrorText);
      Exit;
    end;
    if Count = 0 then
      Break;
    Inc(FSentOffset, Count);
    Inc(FBytesSent, Count);
  end;
  Compact;
  repeat
    Count := sr_net_recv(FHandle, @Chunk[0], ChunkSize);
    if Count < 0 then
    begin
      Fail(NetworkErrorText);
      Exit;
    end;
    if Count > 0 then
    begin
      FIncoming.SetPosition(FIncoming.DataSize);
      FIncoming.AddBytes(@Chunk[0], Count);
      Inc(FBytesReceived, Count);
    end;
  until Count = 0;
end;

function TNetConnection.Receive(out Kind: TNetMessageKind; Payload: TBufEC): Boolean;
var
  Size, Rest: Integer;
begin
  Result := False;
  Kind := 0;
  if FIncoming.DataSize < 4 then
    Poll;
  if FIncoming.DataSize < 4 then
    Exit;
  Size := FIncoming.GetInt32At(0);
  if (Size < 1) or (Size > MaximumMessageSize) then
  begin
    Fail(AnsiString(Format('Bad network message size %d', [Size])));
    FIncoming.Clear;
    Exit;
  end;
  if FIncoming.DataSize < 4 + Size then
    Exit;
  Kind := FIncoming.GetByteAt(4);
  Payload.Clear;
  if Size > 1 then
    Payload.AddBytes(@PByte(FIncoming.Data)[5], Size - 1);
  Payload.SetPosition(0);
  Rest := FIncoming.DataSize - 4 - Size;
  if Rest > 0 then
    Move(PByte(FIncoming.Data)[4 + Size], FIncoming.Data^, Rest);
  FIncoming.SetSize(Rest);
  FIncoming.SetPosition(0);
  Result := True;
end;

procedure TNetConnection.Wait(TimeoutMs: Integer);
begin
  if FClosed then
    Exit;
  if FIncoming.DataSize >= 4 then
    if FIncoming.DataSize >= 4 + FIncoming.GetInt32At(0) then
      Exit;
  sr_net_wait(FHandle, TimeoutMs);
  Poll;
end;

function TNetConnection.FlushAll(TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  Poll;
  while not FClosed and (PendingSendBytes > 0) and (GetTickCount64 < Deadline) do
  begin
    Sleep(1);
    Poll;
  end;
  Result := not FClosed and (PendingSendBytes = 0);
end;

constructor TNetListener.Create(Port: Integer);
begin
  inherited Create;
  InitializeNetwork;
  FHandle := sr_net_listen(Port);
  if FHandle < 0 then
    raise Exception.Create('Cannot listen on port ' + IntToStr(Port) + ': ' + NetworkErrorText);
  FPort := sr_net_local_port(FHandle);
end;

destructor TNetListener.Destroy;
begin
  if FHandle >= 0 then
    sr_net_close(FHandle);
  inherited;
end;

function TNetListener.Accept: TNetConnection;
var
  Handle: Int64;
begin
  Result := nil;
  Handle := sr_net_accept(FHandle);
  if Handle >= 0 then
    Result := TNetConnection.Create(Handle);
end;

end.
