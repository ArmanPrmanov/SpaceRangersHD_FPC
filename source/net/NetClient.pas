{$EXCESSPRECISION OFF}
unit NetClient;

// CHANGE: ENHANCEMENT - The client of a networked game (ROADMAP.md, Phase 5;
// docs/network.md). A client never runs a day: it says Hello, sends every command its human
// submits to the host (the command also runs here, as the prediction), and replaces its copy
// of the game with each state the host sends, at a safe point. Films arrive before the state
// of their day. Everything here runs on the UI thread.
interface
uses
  Classes,
  EC_Buf,
  aCommands,
  NetTransport,
  NetThread,
  NetProtocol;
type
  // A film the host sent: its header and the bytes TEFilm.LoadFromBuffer reads.
  TNetClientFilm = class
    Header: TFilmHeader;
    Bytes: TBufEC;
    destructor Destroy; override;
  end;

  // What applying a state did, for the size and time report.
  TNetApplyReport = record
    Serial: Integer;
    Day: Integer;
    // The host's hash and the one taken here after loading, before the local human changed
    // back to this client's.
    HostHash: QWord;
    Hash: QWord;
    // The uncompressed state, and what came over the network for it.
    StateBytes: Integer;
    ReceivedBytes: Integer;
    // Whether it came as a delta.
    Delta: Boolean;
    LoadMs: Integer;
  end;

  TNetClient = class
  private
    FThread: TNetThread;
    FPeerId: Integer;
    FName: WideString;
    FHumanId: Integer;
    FHostName: WideString;
    FRefused: Boolean;
    FRefuseReason: WideString;
    FHostLeft: Boolean;
    // The last state applied here, uncompressed: the base of the next delta.
    FBase: TBufEC;
    FBaseSerial: Integer;
    // The newest state received and not applied yet.
    FPending: TBufEC;
    FPendingHeader: TStateHeader;
    FPendingReceived: Integer;
    FHasPending: Boolean;
    FFilms: TList;
    FStatus: TStatusMessage;
    FError: AnsiString;
    procedure HandleMessage(Kind: TNetMessageKind; Payload: TBufEC);
    procedure GiveUp(const Text: AnsiString);
  public
    // Connects and says Hello; Connected is False when it could not (Error says why).
    constructor Create(const Address: AnsiString; Port: Integer; const Name: WideString);
    destructor Destroy; override;
    function Connected: Boolean;
    // Takes what arrived: Welcome, states (expanded, kept until ApplyState), films, status.
    procedure Pump;
    // Whether a state waits to be applied.
    function HasState: Boolean;
    // At a safe point: loads the waiting state (ReadGameCheckpoint), hashes it, makes this
    // client's human the local one again, keeps the bytes as the next base and acknowledges
    // the state. Raises when the state names no human of this client.
    function ApplyState: TNetApplyReport;
    // Sends a command this client's human submitted (NetworkCommandHook).
    procedure SendCommand(const Command: TPlayerCommand);
    procedure SendChat(const Text: WideString);
    // Says Bye and waits up to TimeoutMs for it to leave.
    procedure Leave(TimeoutMs: Integer);
    // The films received since the last state applied; the caller takes them.
    function TakeFilm: TNetClientFilm;
    property HumanId: Integer read FHumanId;
    property HostName: WideString read FHostName;
    property Refused: Boolean read FRefused;
    property RefuseReason: WideString read FRefuseReason;
    // The host said Bye or the connection closed.
    property HostLeft: Boolean read FHostLeft;
    property Status: TStatusMessage read FStatus;
    property Error: AnsiString read FError;
  end;

var
  // The running client, for NetworkCommandHook.
  ActiveClient: TNetClient;
// NetworkCommandHook of a client: sends the command to the host.
procedure ClientCommandSubmitted(const Command: TPlayerCommand);
implementation
uses
  SysUtils,
  aGalaxy,
  aHuman,
  aObjectRefs,
  aSaveLoad,
  NetDelta;

const
  ConnectTimeoutMs = 10000;

destructor TNetClientFilm.Destroy;
begin
  Bytes.Free;
  inherited;
end;

constructor TNetClient.Create(const Address: AnsiString; Port: Integer; const Name: WideString);
var
  Hello: THelloMessage;
  Payload: TBufEC;
begin
  inherited Create;
  FName := Name;
  FHumanId := -1;
  FBase := TBufEC.Create;
  FPending := TBufEC.Create;
  FFilms := TList.Create;
  FThread := TNetThread.Create(-1);
  FPeerId := FThread.Connect(Address, Port, ConnectTimeoutMs);
  if FPeerId < 0 then
  begin
    GiveUp('cannot connect to ' + Address + ':' + IntToStr(Port) + ': ' + LastConnectError);
    Exit;
  end;
  Hello.Protocol := ProtocolVersion;
  Hello.GameVersion := GameVersionText;
  Hello.DataHash := DataHash;
  Hello.Name := Name;
  Hello.Spectator := False;
  Payload := TBufEC.Create;
  try
    EncodeHello(Hello, Payload);
    FThread.Send(FPeerId, nkHello, Payload);
  finally
    Payload.Free;
  end;
  ActiveClient := Self;
end;

destructor TNetClient.Destroy;
var
  I: Integer;
begin
  if ActiveClient = Self then
    ActiveClient := nil;
  FThread.Free;
  for I := 0 to FFilms.Count - 1 do
    TObject(FFilms[I]).Free;
  FFilms.Free;
  FBase.Free;
  FPending.Free;
  inherited;
end;

procedure TNetClient.GiveUp(const Text: AnsiString);
begin
  if FError = '' then
    FError := Text;
  NetLog(Text);
  FHostLeft := True;
end;

function TNetClient.Connected: Boolean;
begin
  Result := (FPeerId >= 0) and not FHostLeft and not FRefused;
end;

procedure TNetClient.HandleMessage(Kind: TNetMessageKind; Payload: TBufEC);
var
  Welcome: TWelcomeMessage;
  Header: TStateHeader;
  Film: TNetClientFilm;
  Reference: TBufEC;
begin
  case Kind of
    nkWelcome:
      begin
        Welcome := DecodeWelcome(Payload);
        FHumanId := Welcome.HumanId;
        FHostName := Welcome.HostName;
        NetLog(Format('joined as human %d', [FHumanId]));
      end;
    nkRefuse:
      begin
        FRefused := True;
        FRefuseReason := DecodeRefuse(Payload);
        GiveUp('refused: ' + UTF8Encode(FRefuseReason));
      end;
    nkState:
      begin
        Header := DecodeStateHeader(Payload);
        if Header.BaseSerial = 0 then
          Reference := nil
        else if Header.BaseSerial = FBaseSerial then
          Reference := FBase
        else
          raise Exception.CreateFmt(
              'state %d is a delta against state %d; this client has %d',
              [Header.Serial, Header.BaseSerial, FBaseSerial]
          );
        ExpandState(
            @PByte(Payload.Data)[Payload.Position],
            Payload.DataSize - Payload.Position,
            Reference,
            FPending
        );
        FPendingHeader := Header;
        FPendingReceived := Payload.DataSize;
        FHasPending := True;
      end;
    nkFilm:
      begin
        Film := TNetClientFilm.Create;
        Film.Header := DecodeFilmHeader(Payload);
        Film.Bytes := TBufEC.Create;
        if Payload.DataSize > Payload.Position then
          Film.Bytes.AddBytes(
              @PByte(Payload.Data)[Payload.Position], Payload.DataSize - Payload.Position
          );
        Film.Bytes.SetPosition(0);
        FFilms.Add(Film);
      end;
    nkStatus:
      FStatus := DecodeStatus(Payload);
    nkChat:
      with DecodeChat(Payload) do
        NetLog(Format('chat from human %d: %s', [SenderId, UTF8Encode(Text)]));
    nkBye:
      begin
        FHostLeft := True;
        NetLog('the host left');
      end;
    // TalkRequest: the remote dialogue, a later package.
  end;
end;

procedure TNetClient.Pump;
var
  Kind: TNetMessageKind;
  Payload: TBufEC;
begin
  if FPeerId < 0 then
    Exit;
  Payload := TBufEC.Create;
  try
    while FThread.Receive(FPeerId, Kind, Payload) do
      try
        HandleMessage(Kind, Payload);
      except
        on E: Exception do
          GiveUp(Format('bad %s from the host: %s', [MessageKindName(Kind), E.Message]));
      end;
  finally
    Payload.Free;
  end;
  if not FHostLeft and FThread.IsClosed(FPeerId) then
    GiveUp('the connection closed: ' + FThread.PeerError(FPeerId));
end;

function TNetClient.HasState: Boolean;
begin
  Result := FHasPending;
end;

function TNetClient.ApplyState: TNetApplyReport;
var
  Start: QWord;
  Human: THuman;
  Payload: TBufEC;
  Swap: TBufEC;
begin
  if not FHasPending then
    raise Exception.Create('No state to apply');
  Result := Default(TNetApplyReport);
  Result.Serial := FPendingHeader.Serial;
  Result.Day := FPendingHeader.Day;
  Result.HostHash := FPendingHeader.Hash;
  Result.StateBytes := FPending.DataSize;
  Result.ReceivedBytes := FPendingReceived;
  Result.Delta := FPendingHeader.BaseSerial <> 0;
  Start := GetTickCount64;
  // The state fills the local human's state into the THuman that is local, which is this
  // client's own until now.
  ResetHumans(Galaxy);
  FPending.SetPosition(0);
  ReadGameCheckpoint(FPending);
  Result.LoadMs := Integer(GetTickCount64 - Start);
  // The state was written with the host's human local, and the hash starts with the local
  // human, so hash before this client's human becomes the local one again.
  Result.Hash := GalaxyStateHash;
  Human := FindHuman(FHumanId);
  if (Human = nil) or (Human.Player = nil) then
    raise Exception.CreateFmt('The host''s state has no human %d', [FHumanId]);
  SetLocalHuman(Human);
  if Result.Hash <> Result.HostHash then
    NetLog(
        Format(
            'desync: state %d day %d hash %s, the host''s %s',
            [Result.Serial, Result.Day, IntToHex(Result.Hash, 16), IntToHex(Result.HostHash, 16)]
        )
    );
  Swap := FBase;
  FBase := FPending;
  FPending := Swap;
  FPending.Clear;
  FBaseSerial := FPendingHeader.Serial;
  FHasPending := False;
  Payload := TBufEC.Create;
  try
    EncodeAck(FBaseSerial, Payload);
    FThread.Send(FPeerId, nkAck, Payload);
  finally
    Payload.Free;
  end;
end;

procedure TNetClient.SendCommand(const Command: TPlayerCommand);
var
  Payload: TBufEC;
begin
  if not Connected or (FHumanId < 0) then
    Exit;
  Payload := TBufEC.Create;
  try
    EncodeCommandMessage(Command, Payload);
    FThread.Send(FPeerId, nkCommand, Payload);
  finally
    Payload.Free;
  end;
end;

procedure TNetClient.SendChat(const Text: WideString);
var
  Chat: TChatMessage;
  Payload: TBufEC;
begin
  if not Connected then
    Exit;
  Chat.SenderId := FHumanId;
  Chat.Text := Text;
  Payload := TBufEC.Create;
  try
    EncodeChat(Chat, Payload);
    FThread.Send(FPeerId, nkChat, Payload);
  finally
    Payload.Free;
  end;
end;

procedure TNetClient.Leave(TimeoutMs: Integer);
begin
  if FPeerId < 0 then
    Exit;
  FThread.Send(FPeerId, nkBye, nil, 0);
  FThread.ClosePeer(FPeerId);
  FThread.WaitIdle(TimeoutMs);
  FHostLeft := True;
end;

function TNetClient.TakeFilm: TNetClientFilm;
begin
  if FFilms.Count = 0 then
    Exit(nil);
  Result := TNetClientFilm(FFilms[0]);
  FFilms.Delete(0);
end;

procedure ClientCommandSubmitted(const Command: TPlayerCommand);
begin
  if ActiveClient <> nil then
    ActiveClient.SendCommand(Command);
end;

end.
