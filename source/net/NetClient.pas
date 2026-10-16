{$EXCESSPRECISION OFF}
unit NetClient;

// CHANGE: ENHANCEMENT - The client of a networked game (ROADMAP.md, Phase 5;
// docs/network.md). A client never runs a day: it says Hello, sends every command its human
// submits to the host (the command also runs here, as the prediction), and replaces its copy
// of the game with each state the host sends, at a safe point. Films arrive before the state
// of their day. Everything here runs on the UI thread. CHANGE: ENHANCEMENT - A joined client
// that loses its host reconnects by itself, in place, with its token (docs/network.md,
// Disconnects).
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
    // CHANGE: ENHANCEMENT - It is the whole state after a reconnect (docs/network.md,
    // Disconnects): the human holds the day again when the host has it so.
    Rejoin: Boolean;
  end;

  // CHANGE: ENHANCEMENT - How far a join has come, for its progress (docs/network.md, Hosting
  // and joining): connecting; said Hello, waiting for Welcome; welcomed, receiving the state;
  // a state has come. CHANGE: ENHANCEMENT - jpCharacter: the host asks a first join to choose its
  // character (NewHuman); it waits for SendCharacter.
  TNetJoinPhase = (jpConnecting, jpJoining, jpCharacter, jpReceiving, jpJoined);

  // CHANGE: ENHANCEMENT - A trade that waits to run here (docs/network.md, Trades): another
  // human's that the host relayed, or this client's own that the host applied after the client
  // stopped waiting for it (Own).
  TNetRelayedCommand = record
    HumanId: Integer;
    Own: Boolean;
    Command: TPlayerCommand;
  end;
  // A trade sent and not answered yet.
  TNetSentTrade = record
    Sequence: Cardinal;
    Command: TPlayerCommand;
  end;

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
    // CHANGE: ENHANCEMENT - The reconnection token: the one given to Create, then the last
    // Welcome's; Hello carries it (docs/network.md, Joining).
    FToken: QWord;
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
    // CHANGE: ENHANCEMENT - The trade SendTrade waits for (0: none), and its answer once it has
    // come; the trades it stopped waiting for, whose answer has not come; the trades to run here
    // at a safe point (ApplyRelayed).
    FAwaitedSequence: Cardinal;
    FAwaitedDone: Boolean;
    FAwaitedResult: TCommandResultMessage;
    FLateTrades: array of TNetSentTrade;
    FRelayed: array of TNetRelayedCommand;
    FNoAnswerShown: Boolean;
    // CHANGE: ENHANCEMENT - Reconnection (docs/network.md, Disconnects): a client that has had
    // a state and loses its host (the connection closed or went silent; not the host's Bye, not
    // a refusal) connects again to the same address, as the same name with its token, for
    // NetReconnectMs at most. When it started, when the next try may start, how many tries,
    // why the connection was lost and why the last try failed.
    FReconnecting: Boolean;
    FReconnectStart: QWord;
    FReconnectNextTry: QWord;
    FReconnectTries: Integer;
    FLossReason: AnsiString;
    FReconnectError: AnsiString;
    // Welcomed again, and the whole state after it not applied yet: commands are dropped,
    // since the host's copy no longer has those before the loss. The pending state is that one.
    FResyncing: Boolean;
    FPendingRejoin: Boolean;
    procedure HandleMessage(Kind: TNetMessageKind; Payload: TBufEC);
    procedure ShowRefusal(const Refusal: TCommandResultMessage);
    procedure TakeLateTrade(const CommandResult: TCommandResultMessage);
    procedure GiveUp(const Text: AnsiString);
    procedure SayHello;
    procedure TakeConnection;
    // CHANGE: ENHANCEMENT - The reconnection's steps: the connection closed; the loss starts
    // a reconnect; one step of it from the pump; its end without the human back (Bye on a
    // connection that is up, then GiveUp); what the old connection left goes.
    procedure ConnectionLost(const Text: AnsiString);
    procedure BeginReconnect(const Text: AnsiString);
    procedure ReconnectStep;
    procedure StopReconnect(const Text: AnsiString);
    procedure DropConnectionState;
    // Whether a message other than Hello may go to the host now: welcomed on this connection
    // and not between a loss and the state after the reconnect.
    function MaySend: Boolean;
  public
    // Connects and says Hello; Connected is False when it could not (Error says why). Without
    // Wait the connect runs on a thread of its own: Pump says Hello once it has connected,
    // and Connected stays True meanwhile (JoinPhase is jpConnecting). CHANGE: ENHANCEMENT -
    // Token is the reconnection token Hello carries (0: none): with the one an earlier client
    // of the same human got (Token), the host takes that human over from its old connection.
    constructor Create(
        const Address: AnsiString;
        Port: Integer;
        const Name: WideString;
        Wait: Boolean = True;
        Token: QWord = 0
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
    // CHANGE: ENHANCEMENT - A trade this client's human submitted (aCommands.TradeSubmitHook,
    // docs/network.md, Trades): sends it and waits, pumping, for the host's answer. Returns when
    // the host applied it, so that it runs here; raises ECommandRefused when the host refused
    // it, did not answer within ClientTradeTimeoutMs (the trade is dropped here; a later answer
    // that it was applied runs it at a safe point, ApplyRelayed), or is gone. A trade the host
    // has not answered yet is waited for first.
    procedure SendTrade(const Command: TPlayerCommand);
    // CHANGE: ENHANCEMENT - At a safe point (no command runs, no screen is being built, no box
    // above the screen): runs the trades the host relayed, as their humans, and this client's
    // own that it applied late, in the order they came. One that fails is logged and dropped;
    // the next state fixes the copy. Nothing runs while a state waits to be applied: a relay
    // that came before a state is in it. Runs Limit at most; returns how many ran.
    function ApplyRelayed(Limit: Integer = MaxInt): Integer;
    // Whether relayed trades wait to run.
    function HasRelayed: Boolean;
    // Whether the last trade SendTrade refused was not answered, and its bubble says so;
    // clears it.
    function TakeNoAnswerShown: Boolean;
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
    // The host said Bye or the connection closed. CHANGE: ENHANCEMENT - A joined client's lost
    // connection is HostLeft only once the reconnect has failed or was cancelled.
    property HostLeft: Boolean read FHostLeft;
    // CHANGE: ENHANCEMENT - The connection to the host was lost and the client connects again
    // (docs/network.md, Disconnects); until the host's Welcome names the same human. Connected
    // stays True meanwhile, and commands are dropped. How long it has tried, and how long it
    // may go on (ms).
    function Reconnecting: Boolean;
    function ReconnectElapsedMs: Integer;
    function ReconnectRemainingMs: Integer;
    property ReconnectTries: Integer read FReconnectTries;
    // The player gave up waiting: the client says Bye on a connection that is up and ends as
    // HostLeft, Error saying so.
    procedure CancelReconnect;
    // The whole state after a reconnect waits to be applied: the screens apply it at the next
    // safe point, also outside a wait for the day.
    function RejoinStatePending: Boolean;
    // For the tests: the connection is lost now, as if it had closed. With KeepOld the old
    // connection stays open in the network thread, frozen, until it ends, so that the host sees
    // only silence and a takeover; without, it closes.
    procedure LoseConnection(KeepOld: Boolean);
    // CHANGE: ENHANCEMENT - The reconnection token the host gave (Welcome), or the one given to
    // Create until then; 0: none. And where and as whom this client joined, for joining again.
    property Token: QWord read FToken;
    property Address: AnsiString read FAddress;
    property Port: Integer read FPort;
    property Name: WideString read FName;
    // CHANGE: ENHANCEMENT - For the tests (docs/network.md, Tests): the network thread stops
    // reading, writing and pinging the connection but keeps it open (TNetThread.FreezePeer), so
    // the host sees only silence.
    procedure FreezeConnection;
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
  // CHANGE: ENHANCEMENT - How long a trade waits for the host's answer (SendTrade), and what
  // the wait calls besides pumping once it has lasted ClientTradeIdleMs: the screens keep the
  // window alive without handling its input (docs/network.md, Trades).
  ClientTradeTimeoutMs: Integer = 10000;
  ClientTradeIdleMs: Integer = 100;
  TradeWaitIdleHook: procedure;
  // CHANGE: ENHANCEMENT - How long a client that lost its host tries to connect again
  // (docs/network.md, Disconnects); a variable, so that the tests can shorten it.
  NetReconnectMs: Integer = 60000;
// NetworkCommandHook of a client: sends the command to the host.
procedure ClientCommandSubmitted(const Command: TPlayerCommand);
// CHANGE: ENHANCEMENT - aCommands.TradeSubmitHook of a client (TNetClient.SendTrade).
procedure ClientTradeSubmitted(const Command: TPlayerCommand);
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
  // CHANGE: ENHANCEMENT - A reconnect's try connects for this long at most, and the next try
  // starts this long after one failed.
  ReconnectConnectTimeoutMs = 5000;
  ReconnectPauseMs = 1000;

function TradeNoAnswerText: WideString;
begin
  Result := LocalizedColorText('Multiplayer.TradeNoAnswer');
  if Result = '' then
    Result := 'The host did not answer your action in time.';
end;

function RefusalText(Reason: TRefusalReason): WideString;
const
  Keys: array[TRefusalReason] of WideString = (
      'Multiplayer.RefusedOther',
      'Multiplayer.RefusedOutOfStock',
      'Multiplayer.RefusedNoMoney',
      'Multiplayer.RefusedItemGone',
      'Multiplayer.RefusedOfferGone',
      'Multiplayer.RefusedTargetGone',
      'Multiplayer.RefusedNoRoom',
      'Multiplayer.RefusedInUse'
  );
  English: array[TRefusalReason] of WideString = (
      'The host refused your last action.',
      'The host refused your purchase: not enough in stock.',
      'The host refused your action: not enough money.',
      'The host refused your action: the item is gone.',
      'The host refused your action: the offer is no longer there.',
      'The host refused your action: things changed before it arrived.',
      'The host refused your sale: the buyer has no room for it.',
      'The host refused your action: another player is using it.'
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
    Wait: Boolean;
    Token: QWord
);
begin
  inherited Create;
  FName := Name;
  FToken := Token;
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
  Hello.Token := FToken;
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
  // CHANGE: ENHANCEMENT - A refusal or a bad message ends a reconnect too.
  FReconnecting := False;
  FResyncing := False;
  if FAttempt <> nil then
  begin
    FAttempt.Abandon;
    FAttempt := nil;
  end;
end;

function TNetClient.Connected: Boolean;
begin
  // CHANGE: ENHANCEMENT - Between two tries of a reconnect there is neither a peer nor a connect.
  Result := ((FPeerId >= 0) or (FAttempt <> nil) or FReconnecting) and not FHostLeft and not FRefused;
end;

function TNetClient.MaySend: Boolean;
begin
  Result := Connected and (FPeerId >= 0) and not FReconnecting and not FResyncing;
end;

function TNetClient.Reconnecting: Boolean;
begin
  Result := FReconnecting and not FHostLeft;
end;

function TNetClient.ReconnectElapsedMs: Integer;
begin
  if not Reconnecting then
    Exit(0);
  Result := Integer(GetTickCount64 - FReconnectStart);
end;

function TNetClient.ReconnectRemainingMs: Integer;
begin
  if not Reconnecting then
    Exit(0);
  Result := NetReconnectMs - ReconnectElapsedMs;
  if Result < 0 then
    Result := 0;
end;

function TNetClient.RejoinStatePending: Boolean;
begin
  Result := FHasPending and FPendingRejoin;
end;

// What came on the old connection and belongs to it goes: films, the talk, relays, results,
// the trades the host has not answered (a trade SendTrade waits for is refused there).
procedure TNetClient.DropConnectionState;
var
  I: Integer;
begin
  for I := 0 to FFilms.Count - 1 do
    TObject(FFilms[I]).Free;
  FFilms.Clear;
  FHasTalk := False;
  FRelayed := nil;
  FLateTrades := nil;
  FResults := nil;
end;

// CHANGE: ENHANCEMENT - The connection to the host closed: a try of a reconnect failed; a
// joined client starts to reconnect; otherwise it gives up (docs/network.md, Disconnects).
procedure TNetClient.ConnectionLost(const Text: AnsiString);
begin
  if FReconnecting then
  begin
    FReconnectError := Text;
    NetLog(Format('client reconnect try=%d failed: %s', [FReconnectTries, Text]));
    FThread.RemovePeer(FPeerId);
    FPeerId := -1;
    FReconnectNextTry := GetTickCount64 + ReconnectPauseMs;
  end
  else if FStateReceived and not FRefused and (NetReconnectMs > 0) then
    BeginReconnect(Text)
  else
    GiveUp(Text);
end;

procedure TNetClient.BeginReconnect(const Text: AnsiString);
begin
  NetLog(Format('client lost the host: %s; reconnecting for %d s', [Text, (NetReconnectMs + 500) div 1000]));
  if FPeerId >= 0 then
    FThread.RemovePeer(FPeerId);
  FPeerId := -1;
  FLossReason := Text;
  FReconnectError := Text;
  FReconnecting := True;
  FResyncing := False;
  FReconnectStart := GetTickCount64;
  FReconnectNextTry := FReconnectStart;
  FReconnectTries := 0;
  DropConnectionState;
end;

// From the pump while it reconnects: a connect that has ended gets Hello, or the next try
// starts after a pause; the window's end gives up, also while Welcome has not come.
procedure TNetClient.ReconnectStep;
var
  Connection: TNetConnection;
  Error: AnsiString;
  Tick: QWord;
  Remaining: Int64;
begin
  if FHostLeft then
    Exit;
  Tick := GetTickCount64;
  Remaining := Int64(FReconnectStart) + NetReconnectMs - Int64(Tick);
  if (FAttempt <> nil) and FAttempt.Done then
  begin
    Connection := FAttempt.Take(Error);
    FAttempt.Release;
    FAttempt := nil;
    if Connection <> nil then
    begin
      FPeerId := FThread.AddConnection(Connection);
      NetLog(Format('client reconnect try=%d connected after=%d ms', [FReconnectTries, Tick - FReconnectStart]));
      SayHello;
      Exit;
    end;
    FReconnectError := 'cannot connect to ' + FAddress + ':' + IntToStr(FPort) + ': ' + Error;
    NetLog(Format('client reconnect try=%d failed: %s', [FReconnectTries, FReconnectError]));
    FReconnectNextTry := Tick + ReconnectPauseMs;
  end;
  if Remaining <= 0 then
  begin
    NetLog(Format('client reconnect failed after=%d ms tries=%d', [Tick - FReconnectStart, FReconnectTries]));
    StopReconnect(
        Format('could not reconnect within %d s: %s', [(NetReconnectMs + 500) div 1000, FReconnectError])
    );
    Exit;
  end;
  if (FAttempt = nil) and (FPeerId < 0) and (Tick >= FReconnectNextTry) then
  begin
    Inc(FReconnectTries);
    NetLog(Format('client reconnect try=%d after=%d ms', [FReconnectTries, Tick - FReconnectStart]));
    if Remaining > ReconnectConnectTimeoutMs then
      Remaining := ReconnectConnectTimeoutMs;
    FAttempt := TNetConnectAttempt.Create(FAddress, FPort, Integer(Remaining));
  end;
end;

procedure TNetClient.StopReconnect(const Text: AnsiString);
begin
  FReconnecting := False;
  FResyncing := False;
  if FAttempt <> nil then
  begin
    FAttempt.Abandon;
    FAttempt := nil;
  end;
  if (FPeerId >= 0) and not FThread.IsClosed(FPeerId) then
  begin
    FThread.Send(FPeerId, nkBye, nil, 0);
    FThread.ClosePeer(FPeerId);
    FThread.WaitIdle(1000);
  end;
  GiveUp(Text);
end;

procedure TNetClient.CancelReconnect;
begin
  if not Reconnecting then
    Exit;
  NetLog(Format('client reconnect cancelled after=%d ms tries=%d', [ReconnectElapsedMs, FReconnectTries]));
  StopReconnect('reconnecting was cancelled; ' + FLossReason);
end;

procedure TNetClient.LoseConnection(KeepOld: Boolean);
begin
  if (FPeerId < 0) or FHostLeft or FReconnecting then
    Exit;
  // The thread keeps the frozen peer until it ends.
  if KeepOld then
    FPeerId := -1;
  ConnectionLost('the connection was dropped by the test');
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
  Relayed: TNetRelayedCommand;
begin
  case Kind of
    nkWelcome:
      begin
        Welcome := DecodeWelcome(Payload);
        // CHANGE: ENHANCEMENT - A reconnect gets its human back, or ends: the host's copy of the
        // game starts again from the whole state that follows, so the bases go, and the host
        // numbers the commands of this connection from 1.
        if FReconnecting then
        begin
          if Welcome.HumanId <> FHumanId then
          begin
            StopReconnect(
                Format('could not reconnect: the host gave human %d, not %d', [Welcome.HumanId, FHumanId])
            );
            Exit;
          end;
          FReconnecting := False;
          FResyncing := True;
          FBase.Clear;
          FBaseSerial := 0;
          FPreviousBase.Clear;
          FPreviousBaseSerial := 0;
          FCommandSequence := 0;
          DropConnectionState;
          NetLog(
              Format(
                  'client reconnected human=%d after=%d ms tries=%d',
                  [Welcome.HumanId, GetTickCount64 - FReconnectStart, FReconnectTries]
              )
          );
        end;
        FHumanId := Welcome.HumanId;
        FHostName := Welcome.HostName;
        FToken := Welcome.Token;
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
        // CHANGE: ENHANCEMENT - The state holds every trade the host applied before it.
        FRelayed := nil;
        FLateTrades := nil;
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
        // CHANGE: ENHANCEMENT - The whole state after a reconnect (no base is left to be a
        // delta against).
        if FResyncing then
          FPendingRejoin := True;
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
    nkRelayCommand:
      begin
        Relayed.Own := False;
        Relayed.Command := DecodeRelayCommand(Payload, Relayed.HumanId);
        Insert(Relayed, FRelayed, Length(FRelayed));
      end;
    nkBye:
      begin
        FHostLeft := True;
        FHostSaidBye := True;
        FReconnecting := False;
        FResyncing := False;
        NetLog('the host left');
      end;
    nkNewHuman:
      // CHANGE: ENHANCEMENT - The host has lost the human: a reconnect cannot choose another.
      if FReconnecting then
        StopReconnect(Format('could not reconnect: the host has no human %d of that name', [FHumanId]))
      else if not FWelcomed then
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
        // CHANGE: ENHANCEMENT - The answer to the trade SendTrade waits for, or to one it
        // stopped waiting for: applied there, it runs here at the next safe point.
        if (FAwaitedSequence <> 0) and (CommandResult.Sequence = FAwaitedSequence) then
        begin
          FAwaitedResult := CommandResult;
          FAwaitedDone := True;
        end
        else
          TakeLateTrade(CommandResult);
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

procedure TNetClient.TakeLateTrade(const CommandResult: TCommandResultMessage);
var
  I: Integer;
  Relayed: TNetRelayedCommand;
begin
  for I := 0 to High(FLateTrades) do
    if FLateTrades[I].Sequence = CommandResult.Sequence then
    begin
      if CommandResult.Ok then
      begin
        Relayed.HumanId := FHumanId;
        Relayed.Own := True;
        Relayed.Command := FLateTrades[I].Command;
        Insert(Relayed, FRelayed, Length(FRelayed));
      end;
      Delete(FLateTrades, I, 1);
      Exit;
    end;
end;

procedure TNetClient.SendTrade(const Command: TPlayerCommand);
var
  Start, Deadline: QWord;
  Sent: TNetSentTrade;
  Answer: TCommandResultMessage;

  procedure WaitTick;
  begin
    if Assigned(TradeWaitIdleHook) and (GetTickCount64 >= Start + QWord(ClientTradeIdleMs)) then
      TradeWaitIdleHook;
    NetInboxEvent.WaitFor(2);
    Pump;
  end;

  // CHANGE: ENHANCEMENT - Refused here as one the host did not answer: its bubble says so.
  procedure Unanswered(Sequence: Cardinal; const Why: AnsiString);
  begin
    NetLog(
        Format(
            'trade unanswered seq=%d kind=%s ms=%d%s',
            [Sequence, CommandKindName(Command.Kind), GetTickCount64 - Start, Why]
        )
    );
    if (Galaxy <> nil) and (LocalHuman <> nil) and (LocalHuman.Id = FHumanId) then
    begin
      LocalHuman.AddOrUpdateBubble(0, Galaxy.CurrentTurn, TradeNoAnswerText, '');
      FNoAnswerShown := True;
    end;
    raise ECommandRefused.CreateReason(
        rrOther,
        CommandKindName(Command.Kind) + ': the host did not answer'
    );
  end;

begin
  FNoAnswerShown := False;
  if not Connected or (FHumanId < 0) then
    raise ECommandRefused.CreateReason(rrOther, CommandKindName(Command.Kind) + ': no host');
  Start := GetTickCount64;
  Deadline := Start + QWord(ClientTradeTimeoutMs);
  // One trade at a time: one the host has not answered yet could still be applied there.
  while (Length(FLateTrades) > 0) and Connected and (GetTickCount64 < Deadline) do
    WaitTick;
  if Length(FLateTrades) > 0 then
    raise ECommandRefused.CreateReason(
        rrOther,
        CommandKindName(Command.Kind) + ': the host has not answered the last trade'
    );
  // CHANGE: ENHANCEMENT - Between a loss and the state after the reconnect nothing goes
  // (docs/network.md, Disconnects).
  if FReconnecting or FResyncing then
    Unanswered(0, ' (reconnecting)');
  if not Connected then
    raise ECommandRefused.CreateReason(rrOther, CommandKindName(Command.Kind) + ': the host is gone');
  SendCommand(Command);
  Sent.Sequence := FCommandSequence;
  Sent.Command := Command;
  FAwaitedSequence := Sent.Sequence;
  FAwaitedDone := False;
  try
    Pump;
    while not FAwaitedDone do
    begin
      if not Connected then
        raise ECommandRefused.CreateReason(rrOther, CommandKindName(Command.Kind) + ': the host is gone');
      // CHANGE: ENHANCEMENT - The connection was lost meanwhile: the answer will not come on
      // the new one, so the trade is not kept for it.
      if FReconnecting or FResyncing then
        Unanswered(Sent.Sequence, ' (the connection was lost)');
      if GetTickCount64 >= Deadline then
      begin
        Insert(Sent, FLateTrades, Length(FLateTrades));
        Unanswered(Sent.Sequence, '');
      end;
      WaitTick;
    end;
  finally
    FAwaitedSequence := 0;
  end;
  Answer := FAwaitedResult;
  NetLog(
      Format(
          'trade answered seq=%d kind=%s ok=%d reason=%s ms=%d',
          [Answer.Sequence, CommandKindName(Answer.Kind), Ord(Answer.Ok), RefusalReasonName(Answer.Reason),
              GetTickCount64 - Start]
      )
  );
  if not Answer.Ok then
    raise ECommandRefused.CreateReason(Answer.Reason, UTF8Encode(Answer.Text));
end;

function TNetClient.TakeNoAnswerShown: Boolean;
begin
  Result := FNoAnswerShown;
  FNoAnswerShown := False;
end;

function TNetClient.HasRelayed: Boolean;
begin
  Result := Length(FRelayed) > 0;
end;

function TNetClient.ApplyRelayed(Limit: Integer): Integer;
var
  Relayed: TNetRelayedCommand;
  Ok: Boolean;
begin
  Result := 0;
  if (FAwaitedSequence <> 0) or FHasPending or CommandRunning or (Galaxy = nil) then
    Exit;
  while (Length(FRelayed) > 0) and (Result < Limit) do
  begin
    Relayed := FRelayed[0];
    Delete(FRelayed, 0, 1);
    Ok := True;
    try
      ExecuteRelayedCommand(Relayed.Command);
    except
      on E: Exception do
      begin
        Ok := False;
        NetLog(
            Format(
                'relayed command failed human=%d kind=%s dropped: %s',
                [Relayed.HumanId, CommandKindName(Relayed.Command.Kind), E.Message]
            )
        );
      end;
    end;
    Inc(Result);
    NetLog(
        Format(
            'relayed command ran human=%d kind=%s own=%d ok=%d',
            [Relayed.HumanId, CommandKindName(Relayed.Command.Kind), Ord(Relayed.Own), Ord(Ok)]
        )
    );
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
  // CHANGE: ENHANCEMENT - A reconnect makes its own connections (docs/network.md, Disconnects).
  if FReconnecting then
    ReconnectStep
  else
    TakeConnection;
  if FPeerId < 0 then
    Exit;
  Payload := TBufEC.Create;
  try
    while (FPeerId >= 0) and FThread.Receive(FPeerId, Kind, Payload) do
      try
        HandleMessage(Kind, Payload);
      except
        on E: Exception do
          GiveUp(Format('bad %s from the host: %s', [MessageKindName(Kind), E.Message]));
      end;
  finally
    Payload.Free;
  end;
  // CHANGE: ENHANCEMENT - What the old connection still held has been read; a joined client
  // reconnects instead of giving up.
  if not FHostLeft and (FPeerId >= 0) and FThread.IsClosed(FPeerId) then
    ConnectionLost('the connection closed: ' + FThread.PeerError(FPeerId));
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
  Result.Rejoin := FPendingRejoin;
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
  // CHANGE: ENHANCEMENT - The state after a reconnect ends the resync: commands go again. A
  // state applied while reconnecting (it came before the loss) is not acknowledged on the new
  // connection.
  if FPendingRejoin then
  begin
    FPendingRejoin := False;
    FResyncing := False;
  end;
  if not MaySend then
    Exit;
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
  // CHANGE: ENHANCEMENT - Lost with the connection: the state after the reconnect replaces
  // what it predicted (docs/network.md, Disconnects).
  if not MaySend then
  begin
    NetLog(Format('command dropped while reconnecting kind=%s', [CommandKindName(Command.Kind)]));
    Exit;
  end;
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
  if not MaySend then
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

procedure TNetClient.FreezeConnection;
begin
  if FPeerId >= 0 then
    FThread.FreezePeer(FPeerId);
end;

procedure TNetClient.Leave(TimeoutMs: Integer);
begin
  // CHANGE: ENHANCEMENT - Also in the middle of a reconnect.
  FReconnecting := False;
  FResyncing := False;
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
  // CHANGE: ENHANCEMENT - A talk of the lost connection is not answered on the new one.
  if MaySend then
    FThread.Send(FPeerId, nkTalkDone, nil, 0);
end;

procedure ClientCommandSubmitted(const Command: TPlayerCommand);
begin
  if ActiveClient <> nil then
    ActiveClient.SendCommand(Command);
end;

procedure ClientTradeSubmitted(const Command: TPlayerCommand);
begin
  if ActiveClient = nil then
    raise ECommandRefused.CreateReason(rrOther, CommandKindName(Command.Kind) + ': no host');
  ActiveClient.SendTrade(Command);
end;

end.
