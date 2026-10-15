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
  aHuman,
  NetTransport,
  NetThread,
  NetProtocol;
type
  // A film the host sent: its header and the bytes TEFilm.LoadFromBuffer reads (expanded), and
  // how many bytes they were on the wire.
  TNetClientFilm = class
    Header: TFilmHeader;
    Bytes: TBufEC;
    CompressedSize: Integer;
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

  // CHANGE: ENHANCEMENT - How far a join has come, for its progress (docs/network.md, Hosting
  // and joining): connecting; said Hello, waiting for Welcome; welcomed, receiving the state;
  // a state has come. CHANGE: ENHANCEMENT - jpCharacter: the host asks a first join to choose its
  // character (NewHuman); it waits for SendCharacter.
  TNetJoinPhase = (jpConnecting, jpJoining, jpCharacter, jpReceiving, jpJoined);

  TNetClient = class
  private
    FThread: TNetThread;
    FPeerId: Integer;
    FName: WideString;
    // CHANGE: ENHANCEMENT - A connect that runs on its own thread (Create without Wait); nil
    // once it has ended.
    FAttempt: TNetConnectAttempt;
    FAddress: AnsiString;
    FPort: Integer;
    FWelcomed: Boolean;
    FStateReceived: Boolean;
    FCharacterWanted: Boolean;
    FHostSaidBye: Boolean;
    FHumanId: Integer;
    FHostName: WideString;
    FRefused: Boolean;
    FRefuseReason: WideString;
    FHostLeft: Boolean;
    // The last state applied here, uncompressed: the base of the next delta.
    FBase: TBufEC;
    FBaseSerial: Integer;
    // CHANGE: ENHANCEMENT - The state applied before it: a state the host took before this
    // client's last acknowledgement reached it is a delta against that one.
    FPreviousBase: TBufEC;
    FPreviousBaseSerial: Integer;
    // The newest state received and not applied yet.
    FPending: TBufEC;
    FPendingHeader: TStateHeader;
    FPendingReceived: Integer;
    FHasPending: Boolean;
    FFilms: TList;
    FStatus: TStatusMessage;
    FError: AnsiString;
    // CHANGE: ENHANCEMENT - The dialogue the host's day asks this client's human, not answered
    // yet (docs/network.md, Remote dialogue).
    FTalk: TTalkRequestMessage;
    FHasTalk: Boolean;
    // When the dialogue came (GetTickCount64).
    FTalkArrived: QWord;
    // CHANGE: ENHANCEMENT - The number of the last command sent (Command); the host's
    // CommandResult names commands by it.
    FCommandSequence: Cardinal;
    // The results the host sent, oldest first, until TakeCommandResult takes them (at most
    // KeptCommandResults); and the refusals shown since the last state applied, shown again
    // after the next one, which replaces the human's bubbles.
    FResults: array of TCommandResultMessage;
    FShownRefusals: array of TCommandResultMessage;
    procedure HandleMessage(Kind: TNetMessageKind; Payload: TBufEC);
    procedure ShowRefusal(const Refusal: TCommandResultMessage);
    procedure GiveUp(const Text: AnsiString);
    procedure SayHello;
    procedure TakeConnection;
  public
    // Connects and says Hello; Connected is False when it could not (Error says why). Without
    // Wait the connect runs on a thread of its own: Pump says Hello once it has connected,
    // and Connected stays True meanwhile (JoinPhase is jpConnecting).
    constructor Create(
        const Address: AnsiString;
        Port: Integer;
        const Name: WideString;
        Wait: Boolean = True
    );
    destructor Destroy; override;
    function Connected: Boolean;
    function JoinPhase: TNetJoinPhase;
    // The message being received from the host: the bytes of it that are here and its whole
    // size (0 and 0 when none has started).
    procedure ReceiveProgress(out Have, Size: Integer);
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
    // CHANGE: ENHANCEMENT - The character chosen for a first join (CharacterWanted), and the
    // name, which may differ from Hello's; the join goes on.
    procedure SendCharacter(const Name: WideString; const Character: TJoinCharacter);
    procedure SendChat(const Text: WideString);
    // Says Bye and waits up to TimeoutMs for it to leave.
    procedure Leave(TimeoutMs: Integer);
    // The films received since the last state applied; the caller takes them.
    function TakeFilm: TNetClientFilm;
    // CHANGE: ENHANCEMENT - The film of Day in the star StarId, or nil when it has not come.
    // Films of earlier days, and of Day in other stars, go; films of later days stay: the host
    // can run the next day of a human who continues its travel before this client has played
    // the last one (docs/network.md, Continuing travel).
    function TakeFilmOfDay(Day, StarId: Integer): TNetClientFilm;
    // Drops the films of the days before Day.
    procedure DropFilmsBefore(Day: Integer);
    // Whether the host's day waits for this client's human to answer a dialogue.
    function HasTalkRequest: Boolean;
    // Takes the dialogue; the caller answers it with commands and then TalkDone.
    function TakeTalkRequest(out Request: TTalkRequestMessage): Boolean;
    // CHANGE: ENHANCEMENT - How long the dialogue has waited here, in ms (0 when none).
    function TalkRequestAge: Integer;
    // Whether the dialogue may wait for the end of the film the client plays (FilmPlaying):
    // for ClientTalkHoldMs at most, so the host's day is not held for long; then it is
    // declined (docs/network.md, Remote dialogue).
    function MayHoldTalk(FilmPlaying: Boolean): Boolean;
    // The answer is complete (or the talk cannot be shown here): the host's day goes on.
    procedure SendTalkDone;
    // CHANGE: ENHANCEMENT - The oldest result of a command (CommandResult) not taken yet. A
    // refusal is also shown to this client's human as a message bubble when it comes.
    function TakeCommandResult(out Message: TCommandResultMessage): Boolean;
    // The number SendCommand gave the last command it sent (0: none yet).
    property LastCommandSequence: Cardinal read FCommandSequence;
    // The host asked for a character (NewHuman) and none has been sent yet.
    property CharacterWanted: Boolean read FCharacterWanted;
    property HumanId: Integer read FHumanId;
    property HostName: WideString read FHostName;
    property Refused: Boolean read FRefused;
    property RefuseReason: WideString read FRefuseReason;
    // The host said Bye or the connection closed.
    property HostLeft: Boolean read FHostLeft;
    // CHANGE: ENHANCEMENT - The host said Bye: it quit or stopped hosting; otherwise the
    // connection was lost (Error).
    property HostSaidBye: Boolean read FHostSaidBye;
    property Status: TStatusMessage read FStatus;
    property Error: AnsiString read FError;
  end;

var
  // The running client, for NetworkCommandHook.
  ActiveClient: TNetClient;
  // CHANGE: ENHANCEMENT - How long a dialogue may wait for the end of the client's film.
  ClientTalkHoldMs: Integer = 60000;
// NetworkCommandHook of a client: sends the command to the host.
procedure ClientCommandSubmitted(const Command: TPlayerCommand);
// CHANGE: ENHANCEMENT - What the bubble of a refused command says (Multiplayer.Refused*, with
// an English fallback, as the waits' texts).
function RefusalText(Reason: TRefusalReason): WideString;
implementation
uses
  SysUtils,
  aConst,
  aGalaxy,
  aObjectRefs,
  aSaveLoad,
  NetDelta;

const
  ConnectTimeoutMs = 10000;
  KeptCommandResults = 64;

function RefusalText(Reason: TRefusalReason): WideString;
const
  Keys: array[TRefusalReason] of WideString = (
      'Multiplayer.RefusedOther',
      'Multiplayer.RefusedOutOfStock',
      'Multiplayer.RefusedNoMoney',
      'Multiplayer.RefusedItemGone',
      'Multiplayer.RefusedOfferGone',
      'Multiplayer.RefusedTargetGone',
      'Multiplayer.RefusedNoRoom'
  );
  English: array[TRefusalReason] of WideString = (
      'The host refused your last action.',
      'The host refused your purchase: not enough in stock.',
      'The host refused your action: not enough money.',
      'The host refused your action: the item is gone.',
      'The host refused your action: the offer is no longer there.',
      'The host refused your action: things changed before it arrived.',
      'The host refused your sale: the buyer has no room for it.'
  );
begin
  Result := LocalizedColorText(Keys[Reason]);
  if Result = '' then
    Result := English[Reason];
end;

destructor TNetClientFilm.Destroy;
begin
  Bytes.Free;
  inherited;
end;

constructor TNetClient.Create(
    const Address: AnsiString;
    Port: Integer;
    const Name: WideString;
    Wait: Boolean
);
begin
  inherited Create;
  FName := Name;
  FAddress := Address;
  FPort := Port;
  FHumanId := -1;
  FPeerId := -1;
  FBase := TBufEC.Create;
  FPreviousBase := TBufEC.Create;
  FPending := TBufEC.Create;
  FFilms := TList.Create;
  FThread := TNetThread.Create(-1);
  ActiveClient := Self;
  if not Wait then
  begin
    FAttempt := TNetConnectAttempt.Create(Address, Port, ConnectTimeoutMs);
    Exit;
  end;
  FPeerId := FThread.Connect(Address, Port, ConnectTimeoutMs);
  if FPeerId < 0 then
  begin
    GiveUp('cannot connect to ' + Address + ':' + IntToStr(Port) + ': ' + LastConnectError);
    Exit;
  end;
  SayHello;
end;

// The connect on its own thread has ended: the peer, and Hello; or why it failed.
procedure TNetClient.TakeConnection;
var
  Connection: TNetConnection;
  Error: AnsiString;
begin
  if (FAttempt = nil) or not FAttempt.Done then
    Exit;
  Connection := FAttempt.Take(Error);
  FAttempt.Release;
  FAttempt := nil;
  if Connection = nil then
  begin
    GiveUp('cannot connect to ' + FAddress + ':' + IntToStr(FPort) + ': ' + Error);
    Exit;
  end;
  FPeerId := FThread.AddConnection(Connection);
  SayHello;
end;

procedure TNetClient.SayHello;
var
  Hello: THelloMessage;
  Payload: TBufEC;
begin
  Hello.Protocol := ProtocolVersion;
  Hello.GameVersion := GameVersionText;
  Hello.DataHash := DataHash;
  Hello.Name := FName;
  Hello.Spectator := False;
  Payload := TBufEC.Create;
  try
    EncodeHello(Hello, Payload);
    FThread.Send(FPeerId, nkHello, Payload);
  finally
    Payload.Free;
  end;
end;

destructor TNetClient.Destroy;
var
  I: Integer;
begin
  if ActiveClient = Self then
    ActiveClient := nil;
  // A connect still running closes its connection when it ends.
  if FAttempt <> nil then
    FAttempt.Abandon;
  FAttempt := nil;
  FThread.Free;
  for I := 0 to FFilms.Count - 1 do
    TObject(FFilms[I]).Free;
  FFilms.Free;
  FBase.Free;
  FPreviousBase.Free;
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
  Result := ((FPeerId >= 0) or (FAttempt <> nil)) and not FHostLeft and not FRefused;
end;

function TNetClient.JoinPhase: TNetJoinPhase;
begin
  if FStateReceived then
    Result := jpJoined
  else if FWelcomed then
    Result := jpReceiving
  else if FCharacterWanted then
    Result := jpCharacter
  else if FPeerId >= 0 then
    Result := jpJoining
  else
    Result := jpConnecting;
end;

procedure TNetClient.ReceiveProgress(out Have, Size: Integer);
begin
  Have := 0;
  Size := 0;
  if FPeerId >= 0 then
    FThread.PeerIncoming(FPeerId, Have, Size);
end;

procedure TNetClient.HandleMessage(Kind: TNetMessageKind; Payload: TBufEC);
var
  Welcome: TWelcomeMessage;
  Header: TStateHeader;
  Film: TNetClientFilm;
  Reference: TBufEC;
  CommandResult: TCommandResultMessage;
begin
  case Kind of
    nkWelcome:
      begin
        Welcome := DecodeWelcome(Payload);
        FHumanId := Welcome.HumanId;
        FHostName := Welcome.HostName;
        FWelcomed := True;
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
        else if (FPreviousBaseSerial <> 0) and (Header.BaseSerial = FPreviousBaseSerial) then
          Reference := FPreviousBase
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
        FStateReceived := True;
      end;
    nkFilm:
      begin
        Film := TNetClientFilm.Create;
        Film.Header := DecodeFilmHeader(Payload);
        Film.Bytes := TBufEC.Create;
        try
          ExpandState(
              @PByte(Payload.Data)[Payload.Position],
              Payload.DataSize - Payload.Position,
              nil,
              Film.Bytes
          );
        except
          Film.Free;
          raise;
        end;
        Film.CompressedSize := Payload.DataSize - Payload.Position;
        FFilms.Add(Film);
      end;
    nkStatus:
      begin
        FStatus := DecodeStatus(Payload);
        // CHANGE: ENHANCEMENT - The waits say whose answer the day waits for; the log too.
        if FStatus.TalkHumanId <> 0 then
          NetLog(Format('the day waits for human %d to answer a hail', [FStatus.TalkHumanId]));
      end;
    nkChat:
      with DecodeChat(Payload) do
        NetLog(Format('chat from human %d: %s', [SenderId, UTF8Encode(Text)]));
    nkBye:
      begin
        FHostLeft := True;
        FHostSaidBye := True;
        NetLog('the host left');
      end;
    nkNewHuman:
      if not FWelcomed then
      begin
        FCharacterWanted := True;
        NetLog('the host asks for a character');
      end;
    nkTalkRequest:
      begin
        FTalk := DecodeTalkRequest(Payload);
        FHasTalk := True;
        FTalkArrived := GetTickCount64;
      end;
    nkCommandResult:
      begin
        CommandResult := DecodeCommandResult(Payload);
        if Length(FResults) >= KeptCommandResults then
          Delete(FResults, 0, 1);
        Insert(CommandResult, FResults, Length(FResults));
        if not CommandResult.Ok then
        begin
          NetLog(
              Format(
                  'command refused seq=%d kind=%s reason=%s: %s',
                  [CommandResult.Sequence, CommandKindName(CommandResult.Kind),
                      RefusalReasonName(CommandResult.Reason), UTF8Encode(CommandResult.Text)]
              )
          );
          ShowRefusal(CommandResult);
          Insert(CommandResult, FShownRefusals, Length(FShownRefusals));
        end;
      end;
  end;
end;

// The refusal as a bubble of this client's human. The next state replaces the human's bubbles,
// so ApplyState shows it again.
procedure TNetClient.ShowRefusal(const Refusal: TCommandResultMessage);
begin
  if (Galaxy = nil) or (LocalHuman = nil) or (LocalHuman.Id <> FHumanId) then
    Exit;
  LocalHuman.AddOrUpdateBubble(0, Galaxy.CurrentTurn, RefusalText(Refusal.Reason), '');
end;

function TNetClient.TakeCommandResult(out Message: TCommandResultMessage): Boolean;
begin
  Message := Default(TCommandResultMessage);
  Result := Length(FResults) > 0;
  if not Result then
    Exit;
  Message := FResults[0];
  Delete(FResults, 0, 1);
end;

procedure TNetClient.Pump;
var
  Kind: TNetMessageKind;
  Payload: TBufEC;
begin
  TakeConnection;
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
  I: Integer;
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
  // human, so hash before this client's human becomes the local one again. A state the host
  // did not hash is not checked.
  if Result.HostHash <> 0 then
    Result.Hash := GalaxyStateHashDumped(Format('client-state-%d', [FPendingHeader.Serial]));
  Human := FindHuman(FHumanId);
  if (Human = nil) or (Human.Player = nil) then
    raise Exception.CreateFmt('The host''s state has no human %d', [FHumanId]);
  SetLocalHuman(Human);
  // CHANGE: ENHANCEMENT - The state came after the refusals of the day's commands.
  for I := 0 to High(FShownRefusals) do
    ShowRefusal(FShownRefusals[I]);
  FShownRefusals := nil;
  if Result.Hash <> Result.HostHash then
    NetLog(
        Format(
            'desync: state %d day %d hash %s, the host''s %s',
            [Result.Serial, Result.Day, IntToHex(Result.Hash, 16), IntToHex(Result.HostHash, 16)]
        )
    );
  Swap := FPreviousBase;
  FPreviousBase := FBase;
  FPreviousBaseSerial := FBaseSerial;
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
    Inc(FCommandSequence);
    EncodeCommandMessage(FCommandSequence, Command, Payload);
    FThread.Send(FPeerId, nkCommand, Payload);
  finally
    Payload.Free;
  end;
end;

procedure TNetClient.SendCharacter(const Name: WideString; const Character: TJoinCharacter);
var
  Message: TCharacterMessage;
  Payload: TBufEC;
begin
  if not FCharacterWanted or not Connected then
    Exit;
  FCharacterWanted := False;
  FName := Name;
  Message.Name := Name;
  Message.Character := Character;
  Payload := TBufEC.Create;
  try
    EncodeCharacter(Message, Payload);
    FThread.Send(FPeerId, nkCharacter, Payload);
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
  if FAttempt <> nil then
  begin
    FAttempt.Abandon;
    FAttempt := nil;
    FHostLeft := True;
  end;
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

function TNetClient.TakeFilmOfDay(Day, StarId: Integer): TNetClientFilm;
var
  I: Integer;
  Film: TNetClientFilm;
begin
  Result := nil;
  DropFilmsBefore(Day);
  I := 0;
  while I < FFilms.Count do
  begin
    Film := TNetClientFilm(FFilms[I]);
    if Film.Header.Day <> Day then
      Inc(I)
    else
    begin
      FFilms.Delete(I);
      if (Result = nil) and (Film.Header.StarId = StarId) then
        Result := Film
      else
        Film.Free;
    end;
  end;
end;

procedure TNetClient.DropFilmsBefore(Day: Integer);
var
  I: Integer;
begin
  for I := FFilms.Count - 1 downto 0 do
    if TNetClientFilm(FFilms[I]).Header.Day < Day then
    begin
      TObject(FFilms[I]).Free;
      FFilms.Delete(I);
    end;
end;

function TNetClient.HasTalkRequest: Boolean;
begin
  Result := FHasTalk;
end;

function TNetClient.TakeTalkRequest(out Request: TTalkRequestMessage): Boolean;
begin
  Result := FHasTalk;
  Request := FTalk;
  FHasTalk := False;
end;

function TNetClient.TalkRequestAge: Integer;
begin
  if not FHasTalk then
    Exit(0);
  Result := Integer(GetTickCount64 - FTalkArrived);
end;

function TNetClient.MayHoldTalk(FilmPlaying: Boolean): Boolean;
begin
  Result := FilmPlaying and FHasTalk and (TalkRequestAge < ClientTalkHoldMs);
end;

procedure TNetClient.SendTalkDone;
begin
  if Connected then
    FThread.Send(FPeerId, nkTalkDone, nil, 0);
end;

procedure ClientCommandSubmitted(const Command: TPlayerCommand);
begin
  if ActiveClient <> nil then
    ActiveClient.SendCommand(Command);
end;

end.
