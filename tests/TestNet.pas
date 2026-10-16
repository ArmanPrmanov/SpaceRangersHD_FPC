unit TestNet;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunNetTests;
implementation
uses
  SysUtils,
  EC_Buf,
  GR_Main,
  aCommands,
  NetNative,
  NetTransport,
  NetDelta,
  NetProtocol,
  NetThread,
  NetClient,
  NetPlay,
  TestSupport;

// A state-like buffer: repetitive records with varying fields.
procedure FillState(Buffer: TBufEC; Count, Seed: Integer; InsertAt: Integer = -1);
var
  I: Integer;
begin
  Buffer.Clear;
  RandSeed := Seed;
  for I := 0 to Count - 1 do
  begin
    Buffer.AddInt32(I);
    Buffer.AddInt32(Random(1000));
    Buffer.AddWideStringZ('Ship' + IntToStr(I mod 97));
    Buffer.AddDouble(I * 0.5);
    if I = InsertAt then
      Buffer.AddWideStringZ('inserted');
  end;
end;

function SameBytes(Left, Right: TBufEC): Boolean;
begin
  Result := (Left.DataSize = Right.DataSize)
      and ((Left.DataSize = 0) or CompareMem(Left.Data, Right.Data, Left.DataSize));
end;

procedure RunDeltaTests;
var
  Old, New, Compressed, Whole, Restored: TBufEC;
  I: Integer;
begin
  Old := TBufEC.Create;
  New := TBufEC.Create;
  Compressed := TBufEC.Create;
  Whole := TBufEC.Create;
  Restored := TBufEC.Create;
  try
    FillState(Old, 100000, 1);
    // A few changed fields, and an inserted record that shifts everything after it.
    FillState(New, 100000, 1, 50000);
    for I := 0 to 20 do
      New.SetInt32At(I * 20000 + 4, 424242);
    CompressState(New, nil, Whole);
    ExpandState(Whole.Data, Whole.DataSize, nil, Restored);
    Check(SameBytes(New, Restored), 'a whole state expands to itself');
    CompressState(New, Old, Compressed);
    ExpandState(Compressed.Data, Compressed.DataSize, Old, Restored);
    Check(SameBytes(New, Restored), 'a delta expands to the new state');
    Check(Compressed.DataSize * 20 < Whole.DataSize, 'a delta of a few changes is small');
    Restored.Clear;
    try
      ExpandState(Compressed.Data, Compressed.DataSize, nil, Restored);
      Check(False, 'a delta without its reference is refused');
    except
      on E: Exception do
        Check(True, 'a delta without its reference is refused');
    end;
  finally
    Old.Free;
    New.Free;
    Compressed.Free;
    Whole.Free;
    Restored.Free;
  end;
end;

procedure RunTransportTests;
var
  Listener: TNetListener;
  Client, Server: TNetConnection;
  Payload, Big: TBufEC;
  Kind: TNetMessageKind;
  Deadline: QWord;
  Received: Integer;
  Kinds: array[0..2] of Integer;
  BigSame: Boolean;
begin
  Listener := TNetListener.Create(0);
  Client := nil;
  Server := nil;
  Payload := TBufEC.Create;
  Big := TBufEC.Create;
  try
    Check(Listener.Port > 0, 'the listener picks a port');
    Client := TNetConnection.Connect('127.0.0.1', Listener.Port, 5000);
    Check(Client <> nil, 'a client connects to the listener');
    if Client = nil then
      Exit;
    Deadline := GetTickCount64 + 5000;
    while (Server = nil) and (GetTickCount64 < Deadline) do
    begin
      Server := Listener.Accept;
      if Server = nil then
        Sleep(1);
    end;
    Check(Server <> nil, 'the listener accepts the client');
    if Server = nil then
      Exit;
    FillState(Big, 300000, 7);
    Payload.AddWideStringZ('hello');
    Client.Send(1, Payload);
    Client.Send(2, nil, 0);
    Client.Send(3, Big);
    Received := 0;
    BigSame := False;
    Deadline := GetTickCount64 + 10000;
    while (Received < 3) and (GetTickCount64 < Deadline) do
    begin
      Client.Poll;
      Server.Wait(10);
      while Server.Receive(Kind, Payload) do
      begin
        Kinds[Received] := Kind;
        if Kind = 1 then
          CheckText('hello', Payload.ReadWideString, 'a message keeps its payload');
        if Kind = 2 then
          CheckInt(0, Payload.DataSize, 'an empty message stays empty');
        if Kind = 3 then
          BigSame := SameBytes(Big, Payload);
        Inc(Received);
      end;
    end;
    CheckInt(3, Received, 'every message arrives');
    Check((Kinds[0] = 1) and (Kinds[1] = 2) and (Kinds[2] = 3), 'messages arrive in order');
    Check(BigSame, 'a large message arrives whole');
    Check(Client.BytesSent = Server.BytesReceived, 'byte counts agree');
    Client.Close;
    Deadline := GetTickCount64 + 5000;
    while not Server.Closed and (GetTickCount64 < Deadline) do
      Server.Wait(10);
    Check(Server.Closed, 'a closed peer closes the connection');
    Check(TNetConnection.Connect('127.0.0.1', 1, 500) = nil, 'connecting to a closed port fails');
  finally
    Client.Free;
    Server.Free;
    Listener.Free;
    Payload.Free;
    Big.Free;
  end;
end;

// Every payload decodes to what was encoded, and nothing is left over.
procedure RunProtocolTests;
var
  Buffer: TBufEC;
  Hello, HelloBack: THelloMessage;
  Welcome: TWelcomeMessage;
  State: TStateHeader;
  Film: TFilmHeader;
  Status, StatusBack: TStatusMessage;
  Chat: TChatMessage;
  Talk, TalkBack: TTalkRequestMessage;
  Command, CommandBack: TPlayerCommand;
  Sequence: Cardinal;
  Outcome, OutcomeBack: TCommandResultMessage;
  Refusal: Exception;
  Human: Integer;
  Token: QWord;
begin
  Buffer := TBufEC.Create;
  try
    Hello.Protocol := ProtocolVersion;
    Hello.GameVersion := GameVersionText;
    Hello.DataHash := QWord($0123456789ABCDEF);
    Hello.Name := 'Рейнджер';
    Hello.Spectator := True;
    Hello.Token := QWord($8877665544332211);
    EncodeHello(Hello, Buffer);
    Buffer.SetPosition(0);
    HelloBack := DecodeHello(Buffer);
    Check(
        (HelloBack.Protocol = ProtocolVersion) and (HelloBack.DataHash = Hello.DataHash)
            and HelloBack.Spectator and Buffer.IsAtEnd,
        'Hello round trips'
    );
    Check(HelloBack.Token = QWord($8877665544332211), 'Hello carries the token');
    CheckText(Hello.Name, HelloBack.Name, 'Hello keeps the name');
    Buffer.Clear;
    Buffer.AddInt32(ProtocolVersion + 1);
    Buffer.AddByte(7);
    Buffer.SetPosition(0);
    CheckInt(ProtocolVersion + 1, DecodeHello(Buffer).Protocol, 'another protocol decodes its version');

    Buffer.Clear;
    Welcome.HumanId := 4711;
    Welcome.HostName := 'Host';
    Welcome.Token := QWord($F00DFACECAFEBEEF);
    EncodeWelcome(Welcome, Buffer);
    EncodeRefuse('full', Buffer);
    EncodeAck(-3, Buffer);
    Buffer.SetPosition(0);
    Welcome := DecodeWelcome(Buffer);
    Check((Welcome.HumanId = 4711) and (Welcome.HostName = 'Host'), 'Welcome round trips');
    Check(Welcome.Token = QWord($F00DFACECAFEBEEF), 'Welcome carries the token');
    CheckText('full', DecodeRefuse(Buffer), 'Refuse round trips');
    CheckInt(-3, DecodeAck(Buffer), 'Ack round trips');
    Check(Buffer.IsAtEnd, 'Welcome, Refuse and Ack leave nothing over');

    Buffer.Clear;
    State.Serial := 12;
    State.BaseSerial := 11;
    State.Day := 3040;
    State.Hash := QWord($FEDCBA9876543210);
    EncodeStateHeader(State, Buffer);
    Buffer.AddInt32(99);
    Buffer.SetPosition(0);
    State := DecodeStateHeader(Buffer);
    Check(
        (State.Serial = 12) and (State.BaseSerial = 11) and (State.Day = 3040)
            and (State.Hash = QWord($FEDCBA9876543210)),
        'a state header round trips'
    );
    CheckInt(99, Buffer.GetInt32, 'the state follows its header');

    Buffer.Clear;
    Film.Day := 3041;
    Film.StarId := 17;
    EncodeFilmHeader(Film, Buffer);
    Buffer.SetPosition(0);
    Film := DecodeFilmHeader(Buffer);
    Check((Film.Day = 3041) and (Film.StarId = 17) and Buffer.IsAtEnd, 'a film header round trips');

    Buffer.Clear;
    Status.DayRunning := True;
    SetLength(Status.Humans, 2);
    Status.Humans[0].Id := 5;
    Status.Humans[0].Name := 'A';
    Status.Humans[0].Connected := True;
    Status.Humans[0].HoldsDay := False;
    Status.Humans[1].Id := 9;
    Status.Humans[1].Name := 'B';
    Status.Humans[1].Connected := False;
    Status.Humans[1].HoldsDay := True;
    Status.TalkHumanId := 9;
    EncodeStatus(Status, Buffer);
    Buffer.SetPosition(0);
    StatusBack := DecodeStatus(Buffer);
    Check(
        StatusBack.DayRunning and (Length(StatusBack.Humans) = 2)
            and (StatusBack.Humans[1].Id = 9) and (StatusBack.Humans[1].Name = 'B')
            and not StatusBack.Humans[1].Connected and StatusBack.Humans[1].HoldsDay
            and StatusBack.Humans[0].Connected and (StatusBack.TalkHumanId = 9)
            and Buffer.IsAtEnd,
        'Status round trips'
    );

    Buffer.Clear;
    Chat.SenderId := 5;
    Chat.Text := 'привет';
    EncodeChat(Chat, Buffer);
    Buffer.SetPosition(0);
    Chat := DecodeChat(Buffer);
    Check((Chat.SenderId = 5) and (Chat.Text = 'привет') and Buffer.IsAtEnd, 'Chat round trips');

    Buffer.Clear;
    Talk.HumanId := 77;
    Talk.ShipId := 1234;
    Talk.PlanetId := 0;
    Talk.Scripted := True;
    Talk.TalkType := 2;
    Talk.Amount := 500;
    Talk.Text := 'Сдавайся';
    EncodeTalkRequest(Talk, Buffer);
    Buffer.SetPosition(0);
    TalkBack := DecodeTalkRequest(Buffer);
    Check(
        (TalkBack.HumanId = 77) and (TalkBack.ShipId = 1234) and (TalkBack.PlanetId = 0)
            and TalkBack.Scripted and (TalkBack.TalkType = 2) and (TalkBack.Amount = 500)
            and (TalkBack.Text = 'Сдавайся') and Buffer.IsAtEnd,
        'TalkRequest round trips'
    );

    Buffer.Clear;
    Command := Default(TPlayerCommand);
    Command.Kind := 43;
    Command.Actor := 1234;
    SetLength(Command.Ints, 1);
    Command.Ints[0] := 1;
    Command.Text := 'x';
    EncodeCommandMessage(4000000000, Command, Buffer);
    Buffer.SetPosition(0);
    CommandBack := DecodeCommandMessage(Buffer, Sequence);
    Check(
        (Sequence = 4000000000) and (CommandBack.Kind = 43) and (CommandBack.Actor = 1234)
            and (Length(CommandBack.Ints) = 1) and (CommandBack.Ints[0] = 1)
            and (CommandBack.Text = 'x') and Buffer.IsAtEnd,
        'Command round trips with its number'
    );

    Buffer.Clear;
    Outcome := Default(TCommandResultMessage);
    Outcome.Sequence := 17;
    Outcome.Kind := 110;
    Outcome.Ok := False;
    Outcome.Reason := rrOutOfStock;
    Outcome.Text := 'нет товара';
    EncodeCommandResult(Outcome, Buffer);
    Buffer.SetPosition(0);
    OutcomeBack := DecodeCommandResult(Buffer);
    Check(
        (OutcomeBack.Sequence = 17) and (OutcomeBack.Kind = 110) and not OutcomeBack.Ok
            and (OutcomeBack.Reason = rrOutOfStock) and (OutcomeBack.Text = 'нет товара')
            and Buffer.IsAtEnd,
        'CommandResult round trips'
    );
    // A reason a newer host knows is a refusal all the same.
    Buffer.Clear;
    EncodeCommandResult(Outcome, Buffer);
    PByte(Buffer.Data)[4 + 2 + 1] := 200;
    Buffer.SetPosition(0);
    Check(DecodeCommandResult(Buffer).Reason = rrOther, 'an unknown refusal reason is Other');
    // The reasons of the stale-copy checks travel in the same byte.
    Buffer.Clear;
    Outcome.Reason := rrInUse;
    EncodeCommandResult(Outcome, Buffer);
    Buffer.SetPosition(0);
    Check(DecodeCommandResult(Buffer).Reason = rrInUse, 'the last refusal reason round trips');
    CheckText('in-use', WideString(RefusalReasonName(rrInUse)), 'reason names');
    CheckText('offer-gone', WideString(RefusalReasonName(rrOfferGone)), 'reason names');
    CheckText('target-gone', WideString(RefusalReasonName(rrTargetGone)), 'reason names');
    CheckText('no-room', WideString(RefusalReasonName(rrNoRoom)), 'reason names');
    Refusal := ECommandRefused.CreateReason(rrNoMoney, 'x');
    Check(RefusalReasonOf(Refusal) = rrNoMoney, 'ECommandRefused carries its reason');
    Refusal.Free;
    CheckText('CommandResult', WideString(MessageKindName(nkCommandResult)), 'kind names');
    // CHANGE: ENHANCEMENT - A relayed trade names its human, then the command.
    Buffer.Clear;
    EncodeRelayCommand(1234, Command, Buffer);
    Buffer.SetPosition(0);
    CommandBack := DecodeRelayCommand(Buffer, Human);
    Check(
        (Human = 1234) and (CommandBack.Kind = 43) and (CommandBack.Actor = 1234)
            and (CommandBack.Text = 'x') and Buffer.IsAtEnd,
        'RelayCommand round trips'
    );
    CheckText('RelayCommand', WideString(MessageKindName(nkRelayCommand)), 'kind names');
    Check(not IsTradeCommand(65535) and not IsTradeCommand(0), 'an unknown kind is no trade');
    CheckText('TalkDone', WideString(MessageKindName(nkTalkDone)), 'kind names');
    CheckText('Ping', WideString(MessageKindName(nkPing)), 'kind names');
    // CHANGE: ENHANCEMENT - Tokens come from the system, never 0.
    Token := NewToken;
    Check((Token <> 0) and (NewToken <> Token), 'tokens are random and not 0');
    // XXH64 of nothing with seed 0, the published value.
    Check(sr_hash64(nil, 0, 0) = QWord($EF46DB3751D8E999), 'the data hash is XXH64');
  finally
    Buffer.Free;
  end;
end;

var
  ThreadPayload: TBufEC;

function WaitMessage(Thread: TNetThread; Peer: Integer; out Kind: TNetMessageKind): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + 10000;
  repeat
    Result := Thread.Receive(Peer, Kind, ThreadPayload);
    if Result then
      Exit;
    NetInboxEvent.WaitFor(10);
  until GetTickCount64 > Deadline;
end;

// Two clients and a host, each on a network thread, over loopback: messages in order, a
// state sent whole and then as a delta, compressed once for two peers with the same base,
// and a client that leaves.
procedure RunThreadTests;
var
  Host, Client1, Client2: TNetThread;
  Peer1, Peer2, HostPeer1, HostPeer2, Id: Integer;
  Old, New: TNetState;
  Job: TNetStateJob;
  Restored: TBufEC;
  Kind: TNetMessageKind;
  Header: TStateHeader;
  Deadline: QWord;
begin
  Host := TNetThread.Create(0);
  Client1 := TNetThread.Create(-1);
  Client2 := TNetThread.Create(-1);
  ThreadPayload := TBufEC.Create;
  Restored := TBufEC.Create;
  Old := TNetState.Create(1, 100, 11);
  New := TNetState.Create(2, 101, 22);
  try
    Check(Host.ListenPort > 0, 'the host thread listens');
    Peer1 := Client1.Connect('127.0.0.1', Host.ListenPort, 5000);
    Check(Peer1 > 0, 'the first client connects');
    HostPeer1 := -1;
    Deadline := GetTickCount64 + 5000;
    while not Host.TakeNewPeer(HostPeer1) and (GetTickCount64 < Deadline) do
      Sleep(1);
    Peer2 := Client2.Connect('127.0.0.1', Host.ListenPort, 5000);
    Check(Peer2 > 0, 'the second client connects');
    HostPeer2 := -1;
    Deadline := GetTickCount64 + 5000;
    while not Host.TakeNewPeer(HostPeer2) and (GetTickCount64 < Deadline) do
      Sleep(1);
    Check((HostPeer1 > 0) and (HostPeer2 > 0) and (HostPeer1 <> HostPeer2), 'the host sees both');
    Check(not Host.TakeNewPeer(Id), 'no other peer');
    Client1.Send(Peer1, nkHello, nil, 0);
    Client1.Send(Peer1, nkAck, nil, 0);
    Check(WaitMessage(Host, HostPeer1, Kind) and (Kind = nkHello), 'the first message arrives first');
    Check(WaitMessage(Host, HostPeer1, Kind) and (Kind = nkAck), 'the second message follows');

    FillState(Old.Bytes, 50000, 3);
    FillState(New.Bytes, 50000, 3, 25000);
    Job := TNetStateJob.Create(Old);
    Job.AddTarget(HostPeer1, nil);
    Job.AddTarget(HostPeer2, nil);
    Host.QueueStateJob(Job);
    Host.Send(HostPeer1, nkBye, nil, 0);
    Check(WaitMessage(Client1, Peer1, Kind) and (Kind = nkState), 'a state arrives');
    Header := DecodeStateHeader(ThreadPayload);
    Check(
        (Header.Serial = 1) and (Header.BaseSerial = 0) and (Header.Day = 100)
            and (Header.Hash = 11),
        'a whole state'
    );
    ExpandState(
        @PByte(ThreadPayload.Data)[ThreadPayload.Position],
        ThreadPayload.DataSize - ThreadPayload.Position,
        nil,
        Restored
    );
    Check(SameBytes(Old.Bytes, Restored), 'the whole state expands');
    Check(WaitMessage(Client1, Peer1, Kind) and (Kind = nkBye), 'a message sent after a state follows it');
    Check(Job.Done and (Job.WholeSize > 0), 'the job reports its size');
    Job.Free;
    Job := TNetStateJob.Create(New);
    Job.MeasureWhole := True;
    Job.AddTarget(HostPeer1, Old);
    Job.AddTarget(HostPeer2, Old);
    Host.QueueStateJob(Job);
    Check(WaitMessage(Client2, Peer2, Kind) and (Kind = nkState), 'the whole state reaches the second client');
    Check(WaitMessage(Client2, Peer2, Kind) and (Kind = nkState), 'a delta arrives');
    Header := DecodeStateHeader(ThreadPayload);
    Check((Header.Serial = 2) and (Header.BaseSerial = 1), 'a delta names its base');
    ExpandState(
        @PByte(ThreadPayload.Data)[ThreadPayload.Position],
        ThreadPayload.DataSize - ThreadPayload.Position,
        Old.Bytes,
        Restored
    );
    Check(SameBytes(New.Bytes, Restored), 'the delta expands against its base');
    Check(Host.WaitIdle(5000), 'the host sends everything');
    Check(Job.Done and (Job.DeltaSize > 0) and (Job.DeltaSize * 5 < Job.WholeSize), 'a delta is small');
    Job.Free;
    FreeAndNil(Client2);
    Deadline := GetTickCount64 + 5000;
    while not Host.IsClosed(HostPeer2) and (GetTickCount64 < Deadline) do
      NetInboxEvent.WaitFor(10);
    Check(Host.IsClosed(HostPeer2), 'a client that leaves closes its peer');
    Check(not Host.IsClosed(HostPeer1), 'the other peer stays');
  finally
    Old.Release;
    New.Release;
    Client2.Free;
    Client1.Free;
    Host.Free;
    FreeAndNil(ThreadPayload);
    Restored.Free;
  end;
end;

function WaitNewPeer(Thread: TNetThread): Integer;
var
  Deadline: QWord;
begin
  Result := -1;
  Deadline := GetTickCount64 + 5000;
  while not Thread.TakeNewPeer(Result) and (GetTickCount64 < Deadline) do
    Sleep(1);
end;

// CHANGE: ENHANCEMENT - Liveness (docs/network.md, Disconnects), with the ping and the timeout
// shortened: an idle pair stays open over several timeouts and no Ping reaches an inbox; a peer
// whose message comes a few bytes at a time is not timed out; a frozen peer is closed by the
// other side within the timeout, and the error says why.
procedure RunLivenessTests;
const
  PingMs = 200;
  TimeoutMs = 1000;
  SlowSize = 1000;
var
  Host, Client: TNetThread;
  Raw: TNetConnection;
  ClientPeer, HostPeer, RawPeer, I: Integer;
  SavedPing, SavedTimeout: Integer;
  Start, Elapsed, Deadline: QWord;
  Kind: TNetMessageKind;
  Sent, Received: Int64;
  Header: array[0..4] of Byte;
  Slow: array[0..SlowSize - 2] of Byte;
  Offset: Integer;
begin
  SavedPing := NetPingIntervalMs;
  SavedTimeout := NetSilenceTimeoutMs;
  NetPingIntervalMs := PingMs;
  NetSilenceTimeoutMs := TimeoutMs;
  Host := TNetThread.Create(0);
  Client := TNetThread.Create(-1);
  Raw := nil;
  ThreadPayload := TBufEC.Create;
  try
    ClientPeer := Client.Connect('127.0.0.1', Host.ListenPort, 5000);
    HostPeer := WaitNewPeer(Host);
    Check((ClientPeer > 0) and (HostPeer > 0), 'a pair for the liveness checks connects');
    Sleep(4 * TimeoutMs);
    Check(
        not Host.IsClosed(HostPeer) and not Client.IsClosed(ClientPeer),
        'an idle pair stays open over several timeouts'
    );
    Host.PeerTraffic(HostPeer, Sent, Received);
    Check((Sent > 0) and (Received > 0), 'an idle pair pings both ways');
    Check(
        not Host.Receive(HostPeer, Kind, ThreadPayload) and not Client.Receive(ClientPeer, Kind, ThreadPayload),
        'no Ping reaches an inbox'
    );
    Client.Send(ClientPeer, nkChat, nil, 0);
    Check(WaitMessage(Host, HostPeer, Kind) and (Kind = nkChat), 'a message after the pings arrives');
    Check(not Host.Receive(HostPeer, Kind, ThreadPayload), 'and nothing else');

    // A message whose bytes come slowly: its length, then a few bytes at a time, each well
    // within the timeout, for three timeouts; the raw side never pings.
    Raw := TNetConnection.Connect('127.0.0.1', Host.ListenPort, 5000);
    RawPeer := WaitNewPeer(Host);
    Check((Raw <> nil) and (RawPeer > 0), 'a raw connection connects');
    if Raw = nil then
      Exit;
    PInteger(@Header[0])^ := SlowSize;
    Header[4] := nkChat;
    for I := 0 to High(Slow) do
      Slow[I] := Byte(I);
    Check(sr_net_send(Raw.Handle, @Header[0], 5) = 5, 'the slow message''s header goes');
    Offset := 0;
    Deadline := GetTickCount64 + 3 * TimeoutMs;
    while GetTickCount64 < Deadline do
    begin
      sr_net_send(Raw.Handle, @Slow[Offset], 10);
      Inc(Offset, 10);
      Sleep(TimeoutMs div 3);
    end;
    Check(not Host.IsClosed(RawPeer), 'a peer whose message arrives slowly is not timed out');
    sr_net_send(Raw.Handle, @Slow[Offset], Length(Slow) - Offset);
    Check(
        WaitMessage(Host, RawPeer, Kind) and (Kind = nkChat) and (ThreadPayload.DataSize = Length(Slow))
            and CompareMem(ThreadPayload.Data, @Slow[0], Length(Slow)),
        'the slow message arrives whole'
    );

    // Frozen: the socket stays open and the host hears nothing more.
    Client.FreezePeer(ClientPeer);
    Start := GetTickCount64;
    while not Host.IsClosed(HostPeer) and (GetTickCount64 < Start + 3 * TimeoutMs) do
      NetInboxEvent.WaitFor(5);
    Elapsed := GetTickCount64 - Start;
    Check(Host.IsClosed(HostPeer), 'a frozen peer is closed by the other side');
    // It may have last sent a ping up to one interval before it froze.
    Check(
        (Elapsed + PingMs + 100 >= TimeoutMs) and (Elapsed < TimeoutMs + 500),
        'within the timeout (' + IntToStr(Elapsed) + ' ms)'
    );
    CheckText('no answer for 1 s', WideString(Host.PeerError(HostPeer)), 'the error says why');
    Check(not Client.IsClosed(ClientPeer), 'the frozen side keeps its socket');
    Check(Client.IsIdle, 'a frozen peer does not keep its thread busy');
  finally
    Raw.Free;
    Client.Free;
    Host.Free;
    FreeAndNil(ThreadPayload);
    NetPingIntervalMs := SavedPing;
    NetSilenceTimeoutMs := SavedTimeout;
  end;
end;

type
  // CHANGE: ENHANCEMENT - What a reconnect check waits for the client to be.
  TClientWait = (cwJoined, cwReconnecting, cwWelcomed, cwRejoinState, cwLeft);

function ClientIs(Client: TNetClient; What: TClientWait): Boolean;
begin
  case What of
    cwJoined:
      Result := Client.JoinPhase = jpJoined;
    cwReconnecting:
      Result := Client.Reconnecting;
    cwWelcomed:
      Result := not Client.Reconnecting;
    cwRejoinState:
      Result := Client.RejoinStatePending;
  else
    Result := Client.HostLeft;
  end;
end;

// Pumps Client until it is What, for TimeoutMs at most.
function PumpUntil(Client: TNetClient; What: TClientWait; TimeoutMs: Integer = 10000): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    Client.Pump;
    Result := ClientIs(Client, What);
    if Result then
      Exit;
    NetInboxEvent.WaitFor(5);
  until GetTickCount64 > Deadline;
end;

// The scripted host's side: the next peer's Hello, while Client pumps (its reconnect connects
// from the pump).
function TakeHello(Host: TNetThread; Client: TNetClient; out Peer: Integer; out Hello: THelloMessage): Boolean;
var
  Kind: TNetMessageKind;
  Deadline: QWord;
begin
  Hello := Default(THelloMessage);
  Peer := -1;
  Result := False;
  Deadline := GetTickCount64 + 5000;
  while (Peer < 0) and not Host.TakeNewPeer(Peer) and (GetTickCount64 < Deadline) do
  begin
    if Client <> nil then
      Client.Pump;
    Sleep(1);
  end;
  while (Peer > 0) and not Result and (GetTickCount64 < Deadline) do
  begin
    // The Hello goes once the pump has seen the connect end.
    if Client <> nil then
      Client.Pump;
    Result := Host.Receive(Peer, Kind, ThreadPayload) and (Kind = nkHello);
    Sleep(1);
  end;
  if Result then
    Hello := DecodeHello(ThreadPayload);
end;

procedure SendWelcome(Host: TNetThread; Peer, HumanId: Integer; Token: QWord);
var
  Welcome: TWelcomeMessage;
  Payload: TBufEC;
begin
  Welcome.HumanId := HumanId;
  Welcome.HostName := 'Host';
  Welcome.Token := Token;
  Payload := TBufEC.Create;
  try
    EncodeWelcome(Welcome, Payload);
    Host.Send(Peer, nkWelcome, Payload);
  finally
    Payload.Free;
  end;
end;

procedure SendWholeState(Host: TNetThread; Peer, Serial: Integer);
var
  Header: TStateHeader;
  State, Compressed, Payload: TBufEC;
begin
  Header.Serial := Serial;
  Header.BaseSerial := 0;
  Header.Day := 1;
  Header.Hash := 0;
  State := TBufEC.Create;
  Compressed := TBufEC.Create;
  Payload := TBufEC.Create;
  try
    FillState(State, 100, Serial);
    CompressState(State, nil, Compressed);
    EncodeStateHeader(Header, Payload);
    Payload.AddBytes(Compressed.Data, Compressed.DataSize);
    Host.Send(Peer, nkState, Payload);
  finally
    State.Free;
    Compressed.Free;
    Payload.Free;
  end;
end;

// A client joined to the scripted host as human 7 with token 42: Hello, Welcome, a whole state.
function JoinedClient(Host: TNetThread; out Peer: Integer): TNetClient;
var
  Hello: THelloMessage;
begin
  Result := TNetClient.Create('127.0.0.1', Host.ListenPort, 'Tester');
  Check(TakeHello(Host, nil, Peer, Hello) and (Hello.Token = 0), 'a client says Hello without a token');
  SendWelcome(Host, Peer, 7, 42);
  SendWholeState(Host, Peer, 1);
  Check(PumpUntil(Result, cwJoined) and (Result.HumanId = 7) and (Result.Token = 42), 'it is joined');
end;

// CHANGE: ENHANCEMENT - Reconnection (docs/network.md, Disconnects), against a scripted host on
// a network thread: a joined client whose connection closes reconnects with its name and token
// and drops commands meanwhile; Welcome as the same human ends it, and the whole state after it
// waits as the rejoin's; Welcome as another human, Cancel or the end of the window end it as
// host lost; a refusal and the host's Bye are no loss to reconnect from.
procedure RunReconnectTests;
var
  Host: TNetThread;
  Client: TNetClient;
  Peer: Integer;
  Hello: THelloMessage;
  Kind: TNetMessageKind;
  SavedWindow: Integer;
  Start, Elapsed: QWord;
begin
  // The client logs its steps (NetLog) into the session log, which the game opens at startup.
  AssignFile(SessionLog, IncludeTrailingPathDelimiter(GetTempDir(False)) + 'SpaceRangersNetTests.log');
  Rewrite(SessionLog);
  CloseFile(SessionLog);
  SavedWindow := NetReconnectMs;
  Host := TNetThread.Create(0);
  ThreadPayload := TBufEC.Create;
  Client := nil;
  try
    Client := JoinedClient(Host, Peer);
    Check(not Client.RejoinStatePending, 'a join''s state is no rejoin''s');
    Host.RemovePeer(Peer);
    Check(PumpUntil(Client, cwReconnecting), 'a lost connection starts a reconnect');
    Check(Client.Connected and not Client.HostLeft and (Client.Error = ''), 'the client still counts as connected');
    Check(Client.ReconnectRemainingMs > 0, 'it has time left');
    Client.SendCommand(NewCommand(43));
    CheckInt(0, Client.LastCommandSequence, 'a command while it reconnects is dropped');
    Check(TakeHello(Host, Client, Peer, Hello), 'it connects again');
    Check((Hello.Token = 42) and (Hello.Name = 'Tester'), 'with its name and token');
    SendWelcome(Host, Peer, 7, 42);
    Check(PumpUntil(Client, cwWelcomed) and not Client.HostLeft, 'Welcome as the same human ends the reconnect');
    Client.SendCommand(NewCommand(43));
    CheckInt(0, Client.LastCommandSequence, 'commands wait for the state after it');
    SendWholeState(Host, Peer, 5);
    Check(PumpUntil(Client, cwRejoinState), 'the whole state after it waits as the rejoin''s');
    Host.RemovePeer(Peer);
    Check(PumpUntil(Client, cwReconnecting), 'a second loss reconnects again');
    Check(TakeHello(Host, Client, Peer, Hello), 'and connects again');
    SendWelcome(Host, Peer, 8, 43);
    Check(PumpUntil(Client, cwLeft) and not Client.HostSaidBye, 'Welcome as another human ends it as host lost');
    Check(Pos('gave human 8', Client.Error) > 0, 'the error says why: ' + Client.Error);
    Check(WaitMessage(Host, Peer, Kind) and (Kind = nkBye), 'and the client says Bye');
    FreeAndNil(Client);

    Client := JoinedClient(Host, Peer);
    Host.Send(Peer, nkRefuse, nil, 0);
    Check(PumpUntil(Client, cwLeft) and Client.Refused, 'a refusal ends the client');
    Host.RemovePeer(Peer);
    Client.Pump;
    Check(not Client.Reconnecting and (WaitNewPeer(Host) < 0), 'and it does not connect again');
    FreeAndNil(Client);

    Client := JoinedClient(Host, Peer);
    Host.Send(Peer, nkBye, nil, 0);
    Check(PumpUntil(Client, cwLeft) and Client.HostSaidBye and not Client.Reconnecting, 'the host''s Bye is no loss');
    FreeAndNil(Client);

    Client := JoinedClient(Host, Peer);
    Host.RemovePeer(Peer);
    Check(PumpUntil(Client, cwReconnecting), 'a reconnect to cancel');
    Client.CancelReconnect;
    Check(Client.HostLeft and not Client.Reconnecting and not Client.Connected, 'Cancel ends it as host lost');
    Check(Pos('cancelled', Client.Error) > 0, 'the error says so: ' + Client.Error);
    FreeAndNil(Client);

    NetReconnectMs := 1500;
    Client := JoinedClient(Host, Peer);
    // The host is gone: nothing listens any more.
    FreeAndNil(Host);
    Check(PumpUntil(Client, cwReconnecting), 'a reconnect to a host that is gone');
    Start := GetTickCount64;
    Check(PumpUntil(Client, cwLeft), 'it gives up');
    Elapsed := GetTickCount64 - Start;
    Check(
        (Elapsed + 100 >= 1500) and (Elapsed < 1500 + 1000),
        'after the window (' + IntToStr(Elapsed) + ' ms)'
    );
    Check(Pos('could not reconnect within 2 s', Client.Error) > 0, 'the error says why: ' + Client.Error);
    Check(Client.ReconnectTries >= 1, 'after a try at least');
  finally
    NetReconnectMs := SavedWindow;
    Client.Free;
    Host.Free;
    FreeAndNil(ThreadPayload);
  end;
end;

// The menus' address parsing (NetPlay.ParseNetAddress) and the host's addresses.
procedure RunAddressTests;
var
  Host, Addresses: AnsiString;
  Port: Integer;
begin
  Check(ParseNetAddress('192.168.1.5:4000', Host, Port), 'HOST:PORT parses');
  CheckText('192.168.1.5', WideString(Host), 'the host of HOST:PORT');
  CheckInt(4000, Port, 'the port of HOST:PORT');
  Check(ParseNetAddress('  example.org ', Host, Port), 'HOST alone parses');
  CheckText('example.org', WideString(Host), 'the host is trimmed');
  CheckInt(DefaultNetPort, Port, 'HOST alone takes the default port');
  Check(not ParseNetAddress('', Host, Port), 'an empty address is refused');
  Check(not ParseNetAddress(':4000', Host, Port), 'a port without a host is refused');
  Check(not ParseNetAddress('host:', Host, Port), 'an empty port is refused');
  Check(not ParseNetAddress('host:port', Host, Port), 'a port that is no number is refused');
  Check(not ParseNetAddress('host:0', Host, Port), 'port 0 is refused for a join');
  Check(not ParseNetAddress('host:70000', Host, Port), 'a port above 65535 is refused');
  Addresses := LocalAddressText;
  Check(Pos('127.', Addresses) = 0, 'the host''s addresses leave out loopback');
end;

procedure RunNetTests;
begin
  RunDeltaTests;
  RunTransportTests;
  RunProtocolTests;
  RunThreadTests;
  RunLivenessTests;
  RunReconnectTests;
  RunAddressTests;
end;

end.
