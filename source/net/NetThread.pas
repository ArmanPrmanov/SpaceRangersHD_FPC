{$EXCESSPRECISION OFF}
unit NetThread;

// CHANGE: ENHANCEMENT - The network thread for multiplayer (ROADMAP.md, Phase 5;
// docs/network.md, Threads). It owns the listener and every connection: it waits on the
// sockets a few milliseconds at a time, sends what is queued, cuts what arrives into
// messages and appends them to the peer's inbox, and compresses states. It never touches
// game state. Other threads reach a peer by its id; every inbox and outbox is under one lock.
interface
uses
  Classes,
  SyncObjs,
  EC_Buf,
  NetTransport;
type
  // A whole message: a kind and its payload.
  TNetMessage = class
    Kind: TNetMessageKind;
    Payload: TBufEC;
    // An outgoing state whose compression has not finished; the outbox waits for it, so
    // messages leave in the order they were queued.
    Pending: Boolean;
    constructor Create(AKind: TNetMessageKind; Data: Pointer; Size: Integer);
    destructor Destroy; override;
  end;

  // An uncompressed state with its number, day and hash. The host keeps the states some client may
  // use as a base, and compression jobs read them, so they are counted; the bytes never change.
  TNetState = class
  private
    FReferences: Integer;
  public
    // The host numbers its states from 1 (TStateHeader.Serial).
    Serial: Integer;
    Day: Integer;
    Hash: QWord;
    Bytes: TBufEC;
    // One reference, the creator's.
    constructor Create(ASerial, ADay: Integer; AHash: QWord);
    destructor Destroy; override;
    function AddRef: TNetState;
    procedure Release;
  end;

  TNetStateTarget = record
    PeerId: Integer;
    // The state the peer has acknowledged; nil sends the state whole.
    Base: TNetState;
    Placeholder: TNetMessage;
  end;

  // A state to send: to each target as a delta against its base, compressed on the network
  // thread once per distinct base. The creator frees it once Done.
  TNetStateJob = class
  private
    FDone: Boolean;
  public
    State: TNetState;
    Targets: array of TNetStateTarget;
    // Also compress the whole state, for the size report, when no target needs it.
    MeasureWhole: Boolean;
    // Set on the network thread before Done: the whole state's compressed size (-1 when not
    // compressed), the largest delta (-1 when none), and the time compression took.
    WholeSize: Integer;
    DeltaSize: Integer;
    CompressMs: Integer;
    // Takes a reference to AState.
    constructor Create(AState: TNetState);
    destructor Destroy; override;
    // Takes a reference to Base.
    procedure AddTarget(PeerId: Integer; Base: TNetState);
    function Done: Boolean;
  end;

  TNetThread = class(TThread)
  private
    FLock: TCriticalSection;
    FListener: TNetListener;
    FPeers: TList;
    FNewPeers: TList;
    FJobs: TList;
    FNextPeerId: Integer;
    FListenPort: Integer;
    function FindPeer(Id: Integer): TObject;
    procedure AddPeer(Connection: TNetConnection; Announce: Boolean; out Id: Integer);
    procedure AcceptPeers;
    function MovePeerBytes: Boolean;
    function RunNextJob: Boolean;
    procedure WaitForSockets(TimeoutMs: Integer);
  protected
    procedure Execute; override;
  public
    // Listens on ListenPort (0 picks a free port) unless it is negative. Raises when it cannot.
    constructor Create(ListenPort: Integer);
    destructor Destroy; override;
    // Connects on the calling thread, waiting up to TimeoutMs; the new peer's id, or -1
    // (LastConnectError says why).
    function Connect(const Host: AnsiString; Port, TimeoutMs: Integer): Integer;
    procedure Send(PeerId: Integer; Kind: TNetMessageKind; Payload: TBufEC); overload;
    procedure Send(PeerId: Integer; Kind: TNetMessageKind; Data: Pointer; Size: Integer); overload;
    // Takes the peer's next message; Payload gets its bytes, positioned at the start.
    function Receive(PeerId: Integer; out Kind: TNetMessageKind; Payload: TBufEC): Boolean;
    // A peer the listener accepted since the last call.
    function TakeNewPeer(out PeerId: Integer): Boolean;
    // Whether the peer's connection is gone (or the peer is unknown); its inbox may still
    // hold messages.
    function IsClosed(PeerId: Integer): Boolean;
    function PeerError(PeerId: Integer): AnsiString;
    procedure PeerTraffic(PeerId: Integer; out Sent, Received: Int64);
    // Closes the connection once what is queued for it is sent.
    procedure ClosePeer(PeerId: Integer);
    // Forgets the peer and closes its connection at once.
    procedure RemovePeer(PeerId: Integer);
    // Queues the job's state behind what is already queued for each target. The job must
    // stay alive until Done.
    procedure QueueStateJob(Job: TNetStateJob);
    // Whether nothing is queued to send and no job waits.
    function IsIdle: Boolean;
    function WaitIdle(TimeoutMs: Integer): Boolean;
    property ListenPort: Integer read FListenPort;
  end;

var
  // Set when a message arrives or a connection closes; the pump can wait on it.
  NetInboxEvent: TEvent;
implementation
uses
  SysUtils,
  GR_Main,
  NetNative,
  NetDelta,
  NetProtocol;

type
  TNetPeer = class
    Id: Integer;
    // Only the network thread uses the connection.
    Connection: TNetConnection;
    Inbox: TList;
    Outbox: TList;
    Closed: Boolean;
    CloseRequested: Boolean;
    Removed: Boolean;
    Error: AnsiString;
    // Bytes queued in the connection that the socket has not taken yet.
    Unsent: Integer;
    BytesSent, BytesReceived: Int64;
    constructor Create;
    destructor Destroy; override;
  end;

procedure FreeMessages(List: TList);
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    TObject(List[I]).Free;
  List.Clear;
end;

constructor TNetMessage.Create(AKind: TNetMessageKind; Data: Pointer; Size: Integer);
begin
  inherited Create;
  Kind := AKind;
  Payload := TBufEC.Create;
  if Size > 0 then
    Payload.AddBytes(Data, Size);
  Payload.SetPosition(0);
end;

destructor TNetMessage.Destroy;
begin
  Payload.Free;
  inherited;
end;

constructor TNetState.Create(ASerial, ADay: Integer; AHash: QWord);
begin
  inherited Create;
  FReferences := 1;
  Serial := ASerial;
  Day := ADay;
  Hash := AHash;
  Bytes := TBufEC.Create;
end;

destructor TNetState.Destroy;
begin
  Bytes.Free;
  inherited;
end;

function TNetState.AddRef: TNetState;
begin
  InterLockedIncrement(FReferences);
  Result := Self;
end;

procedure TNetState.Release;
begin
  if InterLockedDecrement(FReferences) = 0 then
    Free;
end;

constructor TNetStateJob.Create(AState: TNetState);
begin
  inherited Create;
  State := AState.AddRef;
  WholeSize := -1;
  DeltaSize := -1;
end;

destructor TNetStateJob.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Targets) do
    if Targets[I].Base <> nil then
      Targets[I].Base.Release;
  State.Release;
  inherited;
end;

procedure TNetStateJob.AddTarget(PeerId: Integer; Base: TNetState);
var
  I: Integer;
begin
  I := Length(Targets);
  SetLength(Targets, I + 1);
  Targets[I].PeerId := PeerId;
  if Base <> nil then
    Targets[I].Base := Base.AddRef
  else
    Targets[I].Base := nil;
  Targets[I].Placeholder := nil;
end;

var
  // Guards TNetStateJob.FDone; one lock for every job is enough.
  JobLock: TCriticalSection;

function TNetStateJob.Done: Boolean;
begin
  JobLock.Enter;
  try
    Result := FDone;
  finally
    JobLock.Leave;
  end;
end;

constructor TNetPeer.Create;
begin
  inherited Create;
  Inbox := TList.Create;
  Outbox := TList.Create;
end;

destructor TNetPeer.Destroy;
begin
  Connection.Free;
  FreeMessages(Inbox);
  FreeMessages(Outbox);
  Inbox.Free;
  Outbox.Free;
  inherited;
end;

constructor TNetThread.Create(ListenPort: Integer);
begin
  inherited Create(True);
  FLock := TCriticalSection.Create;
  FPeers := TList.Create;
  FNewPeers := TList.Create;
  FJobs := TList.Create;
  FNextPeerId := 1;
  FListenPort := -1;
  InitializeNetwork;
  if ListenPort >= 0 then
  begin
    FListener := TNetListener.Create(ListenPort);
    FListenPort := FListener.Port;
  end;
  Start;
end;

destructor TNetThread.Destroy;
var
  I: Integer;
begin
  Terminate;
  WaitFor;
  for I := 0 to FPeers.Count - 1 do
    TObject(FPeers[I]).Free;
  FPeers.Free;
  FNewPeers.Free;
  FJobs.Free;
  FListener.Free;
  FLock.Free;
  inherited;
end;

function TNetThread.FindPeer(Id: Integer): TObject;
var
  I: Integer;
begin
  for I := 0 to FPeers.Count - 1 do
    if TNetPeer(FPeers[I]).Id = Id then
      Exit(TNetPeer(FPeers[I]));
  Result := nil;
end;

procedure TNetThread.AddPeer(Connection: TNetConnection; Announce: Boolean; out Id: Integer);
var
  Peer: TNetPeer;
begin
  Peer := TNetPeer.Create;
  Peer.Connection := Connection;
  FLock.Enter;
  try
    Peer.Id := FNextPeerId;
    Inc(FNextPeerId);
    FPeers.Add(Peer);
    if Announce then
      FNewPeers.Add(Pointer(PtrInt(Peer.Id)));
    Id := Peer.Id;
  finally
    FLock.Leave;
  end;
end;

function TNetThread.Connect(const Host: AnsiString; Port, TimeoutMs: Integer): Integer;
var
  Connection: TNetConnection;
begin
  Connection := TNetConnection.Connect(Host, Port, TimeoutMs);
  if Connection = nil then
    Exit(-1);
  AddPeer(Connection, False, Result);
end;

procedure TNetThread.Send(PeerId: Integer; Kind: TNetMessageKind; Payload: TBufEC);
begin
  if Payload = nil then
    Send(PeerId, Kind, nil, 0)
  else
    Send(PeerId, Kind, Payload.Data, Payload.DataSize);
end;

procedure TNetThread.Send(PeerId: Integer; Kind: TNetMessageKind; Data: Pointer; Size: Integer);
var
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    if (Peer <> nil) and not Peer.Closed and not Peer.CloseRequested then
      Peer.Outbox.Add(TNetMessage.Create(Kind, Data, Size));
  finally
    FLock.Leave;
  end;
end;

function TNetThread.Receive(PeerId: Integer; out Kind: TNetMessageKind; Payload: TBufEC): Boolean;
var
  Peer: TNetPeer;
  Message: TNetMessage;
begin
  Result := False;
  Kind := 0;
  Message := nil;
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    if (Peer <> nil) and (Peer.Inbox.Count > 0) then
    begin
      Message := TNetMessage(Peer.Inbox[0]);
      Peer.Inbox.Delete(0);
    end;
  finally
    FLock.Leave;
  end;
  if Message = nil then
    Exit;
  Kind := Message.Kind;
  Payload.Clear;
  if Message.Payload.DataSize > 0 then
    Payload.AddBytes(Message.Payload.Data, Message.Payload.DataSize);
  Payload.SetPosition(0);
  Message.Free;
  Result := True;
end;

function TNetThread.TakeNewPeer(out PeerId: Integer): Boolean;
begin
  FLock.Enter;
  try
    Result := FNewPeers.Count > 0;
    if Result then
    begin
      PeerId := Integer(PtrInt(FNewPeers[0]));
      FNewPeers.Delete(0);
    end
    else
      PeerId := -1;
  finally
    FLock.Leave;
  end;
end;

function TNetThread.IsClosed(PeerId: Integer): Boolean;
var
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    Result := (Peer = nil) or Peer.Closed;
  finally
    FLock.Leave;
  end;
end;

function TNetThread.PeerError(PeerId: Integer): AnsiString;
var
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    if Peer = nil then
      Result := 'unknown peer'
    else
      Result := Peer.Error;
  finally
    FLock.Leave;
  end;
end;

procedure TNetThread.PeerTraffic(PeerId: Integer; out Sent, Received: Int64);
var
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    Sent := 0;
    Received := 0;
    if Peer <> nil then
    begin
      Sent := Peer.BytesSent;
      Received := Peer.BytesReceived;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNetThread.ClosePeer(PeerId: Integer);
var
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    if Peer <> nil then
      Peer.CloseRequested := True;
  finally
    FLock.Leave;
  end;
end;

procedure TNetThread.RemovePeer(PeerId: Integer);
var
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Peer := TNetPeer(FindPeer(PeerId));
    if Peer <> nil then
    begin
      Peer.Removed := True;
      Peer.Closed := True;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNetThread.QueueStateJob(Job: TNetStateJob);
var
  I: Integer;
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    for I := 0 to High(Job.Targets) do
    begin
      Peer := TNetPeer(FindPeer(Job.Targets[I].PeerId));
      if (Peer = nil) or Peer.Closed or Peer.CloseRequested then
        Continue;
      Job.Targets[I].Placeholder := TNetMessage.Create(nkState, nil, 0);
      Job.Targets[I].Placeholder.Pending := True;
      Peer.Outbox.Add(Job.Targets[I].Placeholder);
    end;
    FJobs.Add(Job);
  finally
    FLock.Leave;
  end;
end;

function TNetThread.IsIdle: Boolean;
var
  I: Integer;
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Result := FJobs.Count = 0;
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := TNetPeer(FPeers[I]);
      if not Peer.Closed and ((Peer.Outbox.Count > 0) or (Peer.Unsent > 0)) then
        Result := False;
    end;
  finally
    FLock.Leave;
  end;
end;

function TNetThread.WaitIdle(TimeoutMs: Integer): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    Result := IsIdle;
    if Result or (GetTickCount64 >= Deadline) then
      Exit;
    Sleep(1);
  until False;
end;

procedure TNetThread.AcceptPeers;
var
  Connection: TNetConnection;
  Id: Integer;
begin
  if FListener = nil then
    Exit;
  repeat
    Connection := FListener.Accept;
    if Connection <> nil then
    begin
      AddPeer(Connection, True, Id);
      NetInboxEvent.SetEvent;
    end;
  until Connection = nil;
end;

// Moves every peer's queued messages into its connection and what arrived into its inbox.
// Returns whether bytes still wait to be sent.
function TNetThread.MovePeerBytes: Boolean;
var
  Peers, Outgoing: TList;
  I, J: Integer;
  Peer: TNetPeer;
  Message: TNetMessage;
  Kind: TNetMessageKind;
  Payload: TBufEC;
  Arrived: Boolean;
begin
  Result := False;
  Peers := TList.Create;
  Outgoing := TList.Create;
  Payload := TBufEC.Create;
  try
    FLock.Enter;
    try
      // Removed peers go now; nobody else refers to them.
      for I := FPeers.Count - 1 downto 0 do
        if TNetPeer(FPeers[I]).Removed then
        begin
          TObject(FPeers[I]).Free;
          FPeers.Delete(I);
        end;
      Peers.Assign(FPeers);
    finally
      FLock.Leave;
    end;
    for I := 0 to Peers.Count - 1 do
    begin
      Peer := TNetPeer(Peers[I]);
      Outgoing.Clear;
      FLock.Enter;
      try
        if Peer.Closed then
          Continue;
        while (Peer.Outbox.Count > 0) and not TNetMessage(Peer.Outbox[0]).Pending do
        begin
          Outgoing.Add(Peer.Outbox[0]);
          Peer.Outbox.Delete(0);
        end;
      finally
        FLock.Leave;
      end;
      for J := 0 to Outgoing.Count - 1 do
      begin
        Message := TNetMessage(Outgoing[J]);
        Peer.Connection.Send(Message.Kind, Message.Payload);
        Message.Free;
      end;
      Peer.Connection.Poll;
      Arrived := False;
      while Peer.Connection.Receive(Kind, Payload) do
      begin
        Message := TNetMessage.Create(Kind, Payload.Data, Payload.DataSize);
        FLock.Enter;
        try
          Peer.Inbox.Add(Message);
        finally
          FLock.Leave;
        end;
        Arrived := True;
      end;
      FLock.Enter;
      try
        Peer.Unsent := Peer.Connection.PendingSendBytes;
        Peer.BytesSent := Peer.Connection.BytesSent;
        Peer.BytesReceived := Peer.Connection.BytesReceived;
        if Peer.CloseRequested and (Peer.Outbox.Count = 0) and (Peer.Unsent = 0) then
          Peer.Connection.Close;
        if Peer.Connection.Closed then
        begin
          Peer.Closed := True;
          Peer.Error := Peer.Connection.Error;
          Arrived := True;
        end;
        if (Peer.Unsent > 0) or (Peer.Outbox.Count > 0) then
          Result := True;
      finally
        FLock.Leave;
      end;
      if Arrived then
        NetInboxEvent.SetEvent;
    end;
  finally
    Payload.Free;
    Outgoing.Free;
    Peers.Free;
  end;
end;

// Compresses the oldest job's state once per distinct base and fills its placeholders.
function TNetThread.RunNextJob: Boolean;
var
  Job: TNetStateJob;
  I, J: Integer;
  Base: TNetState;
  Payload: TBufEC;
  Header: TStateHeader;
  Start: QWord;
  Done: array of Boolean;
  HasWhole: Boolean;
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    Result := FJobs.Count > 0;
    if not Result then
      Exit;
    Job := TNetStateJob(FJobs[0]);
  finally
    FLock.Leave;
  end;
  Start := GetTickCount64;
  SetLength(Done, Length(Job.Targets));
  HasWhole := False;
  Payload := TBufEC.Create;
  try
    for I := 0 to High(Job.Targets) do
    begin
      if Done[I] then
        Continue;
      Base := Job.Targets[I].Base;
      Payload.Clear;
      Header.Serial := Job.State.Serial;
      Header.Day := Job.State.Day;
      if Base = nil then
        Header.BaseSerial := 0
      else
        Header.BaseSerial := Base.Serial;
      Header.Hash := Job.State.Hash;
      EncodeStateHeader(Header, Payload);
      if Base = nil then
        CompressState(Job.State.Bytes, nil, Payload)
      else
        CompressState(Job.State.Bytes, Base.Bytes, Payload);
      if Base = nil then
      begin
        HasWhole := True;
        Job.WholeSize := Payload.DataSize;
      end
      else if Payload.DataSize > Job.DeltaSize then
        Job.DeltaSize := Payload.DataSize;
      // Every target with this base gets the same bytes.
      FLock.Enter;
      try
        for J := I to High(Job.Targets) do
          if not Done[J] and (Job.Targets[J].Base = Base) then
          begin
            Done[J] := True;
            Peer := TNetPeer(FindPeer(Job.Targets[J].PeerId));
            if (Peer = nil) or (Job.Targets[J].Placeholder = nil)
                or (Peer.Outbox.IndexOf(Job.Targets[J].Placeholder) < 0) then
              Continue;
            Job.Targets[J].Placeholder.Payload.Clear;
            Job.Targets[J].Placeholder.Payload.AddBytes(Payload.Data, Payload.DataSize);
            Job.Targets[J].Placeholder.Pending := False;
          end;
      finally
        FLock.Leave;
      end;
    end;
    if Job.MeasureWhole and not HasWhole then
    begin
      Payload.Clear;
      CompressState(Job.State.Bytes, nil, Payload);
      Job.WholeSize := Payload.DataSize;
    end;
  finally
    Payload.Free;
    Job.CompressMs := Integer(GetTickCount64 - Start);
    // A failed job still ends: its placeholders go unsent, and the peers close.
    FLock.Enter;
    try
      FJobs.Remove(Job);
      for I := 0 to High(Job.Targets) do
      begin
        Peer := TNetPeer(FindPeer(Job.Targets[I].PeerId));
        if (Peer <> nil) and (Job.Targets[I].Placeholder <> nil)
            and (Peer.Outbox.IndexOf(Job.Targets[I].Placeholder) >= 0)
            and Job.Targets[I].Placeholder.Pending then
        begin
          Peer.Outbox.Remove(Job.Targets[I].Placeholder);
          Job.Targets[I].Placeholder.Free;
          Peer.CloseRequested := True;
        end;
      end;
    finally
      FLock.Leave;
    end;
    JobLock.Enter;
    try
      Job.FDone := True;
    finally
      JobLock.Leave;
    end;
  end;
end;

procedure TNetThread.WaitForSockets(TimeoutMs: Integer);
var
  Handles: array of Int64;
  I, Count: Integer;
  Peer: TNetPeer;
begin
  FLock.Enter;
  try
    SetLength(Handles, FPeers.Count + 1);
    Count := 0;
    if FListener <> nil then
    begin
      Handles[Count] := FListener.Handle;
      Inc(Count);
    end;
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := TNetPeer(FPeers[I]);
      if not Peer.Closed and (Peer.Connection.Handle >= 0) then
      begin
        Handles[Count] := Peer.Connection.Handle;
        Inc(Count);
      end;
    end;
  finally
    FLock.Leave;
  end;
  if Count = 0 then
    Sleep(TimeoutMs)
  else
    sr_net_wait_many(@Handles[0], Count, TimeoutMs);
end;

procedure TNetThread.Execute;
var
  Busy: Boolean;
begin
  while not Terminated do
  begin
    try
      AcceptPeers;
      Busy := MovePeerBytes;
      if RunNextJob then
        Busy := True;
      // A peer that sends waits only briefly, so its bytes keep moving.
      if Busy then
        WaitForSockets(1)
      else
        WaitForSockets(5);
    except
      on E: Exception do
      begin
        // A failed job or socket call must not end the thread; the peers see their
        // connections close.
        AppendLogLineThreadSafe('Network thread: ' + E.ClassName + ' ' + E.Message);
        Sleep(5);
      end;
    end;
  end;
end;

initialization
  NetInboxEvent := TEvent.Create(nil, False, False, '');
  JobLock := TCriticalSection.Create;
finalization
  JobLock.Free;
  NetInboxEvent.Free;
end.
