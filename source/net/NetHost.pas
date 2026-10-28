{$EXCESSPRECISION OFF}
unit NetHost;

// CHANGE: ENHANCEMENT - The host of a networked game (ROADMAP.md, Phase 5; docs/network.md).
// Only the host runs the day. It takes joins and disconnects at quiet points, queues each
// peer's commands and applies the queues in Session.Humans order once every peer is ready,
// sends the film of each star to the clients in it, and after the day a state to every
// client, as a delta against the state that client acknowledged. Everything here runs on the
// UI thread, except StarDay and RemoteTalk, which the turn thread calls.
// CHANGE: ENHANCEMENT - The text quests' pages (docs/progress/2026-10-19-text-quests-plan.md,
// Phase D): the host keeps the latest page of every human (QuestPages) and sends each page to
// every joined client but the player's, its own human's too; a new or returning client gets the
// open quests' latest pages, and a player that leaves mid-quest gets an abandoned end page.
interface
uses
  Classes,
  SysUtils,
  SyncObjs,
  EC_Buf,
  aCommands,
  aHuman,
  NetTransport,
  NetThread,
  NetProtocol,
  QuestPage;
type
  THostPeerState = (hpHello, hpPendingJoin, hpJoined);

  // CHANGE: ENHANCEMENT - A command a peer sent, with the number the client gave it
  // (CommandResult names it).
  TQueuedCommand = record
    Sequence: Cardinal;
    Command: TPlayerCommand;
  end;
  TQueuedCommands = array of TQueuedCommand;

  THostPeer = class
    PeerId: Integer;
    State: THostPeerState;
    Hello: THelloMessage;
    // The human the peer plays, once joined.
    HumanId: Integer;
    // CHANGE: ENHANCEMENT - A first join: NewHuman went to the peer, and the character it chose
    // on the new-game screen has come (docs/network.md, Joining).
    CharacterAsked: Boolean;
    HasCharacter: Boolean;
    Character: TJoinCharacter;
    // Its commands, in arrival order, not yet applied.
    Queue: TQueuedCommands;
    // The last state it acknowledged (0: none), and that state while the host has it.
    AckedSerial: Integer;
    Base: TNetState;
    // The connection closed or the peer said Bye; handled at the next quiet point.
    Leaving: Boolean;
    // CHANGE: ENHANCEMENT - The turn thread reads the peer's inbox while its human answers a
    // dialogue (RemoteTalk); the pump leaves it alone. Set under TNetHost.FTalkLock.
    InTalk: Boolean;
    // Messages the turn thread took during a talk and left for the pump (TNetMessage), in
    // arrival order; the pump handles them before the inbox.
    Deferred: TList;
    // CHANGE: ENHANCEMENT - Its Hello was checked for a takeover (TNetHost.TakeOver).
    TakeOverChecked: Boolean;
    destructor Destroy; override;
    function EndTurnIndex: Integer;
    // CHANGE: ENHANCEMENT - The index of the first StopContinuing in the queue; -1 when none.
    function StopIndex: Integer;
    // CHANGE: ENHANCEMENT - The index of the first trade in the queue with no EndTurn before
    // it, which the host applies as it arrives (docs/network.md, Trades); -1 when none.
    function TradeIndex: Integer;
  end;

  TNetHost = class;
  // CHANGE: ENHANCEMENT - Peers of the network thread, by id.
  TPeerIds = array of Integer;
  // CHANGE: ENHANCEMENT - For the tests: told before (Done False) and after (Done True) the host
  // applies a peer's trade as it arrives; Queued is the trade, Applied whether it was.
  TNetTradeHook = procedure(
      Host: TNetHost;
      HumanId: Integer;
      const Queued: TQueuedCommand;
      Done, Applied: Boolean
  );

  TNetHost = class
  private
    FThread: TNetThread;
    FName: WideString;
    FPeers: TList;
    // The states some client may still use as a base, oldest first.
    FStates: TList;
    FSerial: Integer;
    // Films the turn thread encoded (TNetHostFilm), under FFilmLock.
    FFilms: TList;
    FFilmLock: TCriticalSection;
    FSentFilmRawBytes: Int64;
    FDayUnderWay: Boolean;
    FLastStatus: TBufEC;
    FLastTakeMs: Integer;
    // The jobs of join states, freed once sent.
    FJoinJobs: TList;
    // The player-star job has run a day (DayCompletedHook); the pump sends its films.
    FDayRan: Boolean;
    // Guards THostPeer.InTalk against the pump's reads of that peer's inbox.
    FTalkLock: TCriticalSection;
    // The turn thread is in RemoteTalk; Shutdown ends it (FStopping) and waits for it.
    FTalking: Boolean;
    FStopping: Boolean;
    // CHANGE: ENHANCEMENT - The human whose remote dialogue the turn thread waits for (0: none);
    // Status carries it.
    FTalkHumanId: Integer;
    // CHANGE: ENHANCEMENT - The pump may apply trades now (MayApplyTrades, at a quiet point);
    // the queues are being applied at the barrier (ApplyQueues), which relays nothing.
    FTradesAllowed: Boolean;
    FApplyingQueues: Boolean;
    // CHANGE: ENHANCEMENT - The reconnection token of each human welcomed in this hosting
    // session (docs/network.md, Joining), by human id.
    FTokenHumans: array of Integer;
    FTokens: array of QWord;
    // CHANGE: ENHANCEMENT - The EndTurns taken out of the queues by the peers' CancelEndTurn, and
    // the continuing travels it stopped before the day.
    FCancelledEndTurns: Integer;
    FStoppedTravels: Integer;
    // CHANGE: ENHANCEMENT - The latest text-quest page of each human.
    FQuestPages: TQuestPageStore;
    // Sends Page to every joined peer but the one of its human (and Skip); how many got it.
    function SendQuestPage(const Page: TWatchedQuestPage; Skip: THostPeer): Integer;
    function FindPeer(PeerId: Integer): THostPeer;
    // The human's token; with Issue, one is issued (NewToken) when it has none yet, at its
    // first Welcome in this session. 0: none.
    function HumanToken(HumanId: Integer; Issue: Boolean): QWord;
    // CHANGE: ENHANCEMENT - A Hello whose name is a connected remote human's and whose token is
    // that human's: the old peer is removed at once and leaves at the next quiet point, where
    // the new one rejoins. Whether it was.
    function TakeOver(Peer: THostPeer): Boolean;
    function ReceiveUnlessInTalk(
        Peer: THostPeer;
        out Kind: TNetMessageKind;
        Payload: TBufEC
    ): Boolean;
    procedure HandleMessage(Peer: THostPeer; Kind: TNetMessageKind; Payload: TBufEC);
    procedure Refuse(Peer: THostPeer; const Reason: WideString);
    procedure DisconnectHuman(Human: THuman; Peer: THostPeer);
    procedure ProcessLeaving;
    procedure ProcessJoins;
    procedure AskCharacters;
    function FindNamedHuman(const Name: WideString): THuman;
    function JoinReady(Peer: THostPeer): Boolean;
    procedure SendStatus(Force: Boolean);
    function TakeState: TNetState;
    function LagsBehind(Peer: THostPeer; Human: THuman): Boolean;
    // CHANGE: ENHANCEMENT - Tells the peer that its command Sequence raised E here, and why
    // (CommandResult); logs it. Thread-safe: the turn thread calls it in a remote dialogue.
    procedure CommandFailed(Peer: THostPeer; Sequence: Cardinal; const Command: TPlayerCommand; E: Exception);
    // CHANGE: BUGFIX - Refuses a command only the host's human may give (IsHostOnlyCommand),
    // which a peer sent: it is not queued or run, and the peer is told (CommandFailed).
    procedure RefuseHostOnlyCommand(Peer: THostPeer; Sequence: Cardinal; const Command: TPlayerCommand);
    // CHANGE: ENHANCEMENT - Tells the peer that its trade Sequence was applied (CommandResult).
    // Thread-safe, as CommandFailed.
    procedure CommandApplied(Peer: THostPeer; Sequence: Cardinal; const Command: TPlayerCommand);
    // CHANGE: ENHANCEMENT - Applies the peer's queue up to and including its trade at Index,
    // through SubmitCommand, and answers the trade (docs/network.md, Trades).
    procedure ApplyTrade(Peer: THostPeer; Index: Integer);
    // The trades that wait in the queues, in Session.Humans order; with OrderedTrades, a
    // human's only once every human before it is ready.
    procedure ApplyWaitingTrades;
    // CHANGE: ENHANCEMENT - A peer takes back its end turn (CancelEndTurn, docs/network.md,
    // Waiting): before the day starts, its EndTurn for this day leaves its queue, so it is not
    // ready any more, and the peer gets CommandResult (applied); the commands before and after
    // the EndTurn stay queued. Once the day has begun (or has run) it is refused (rrTooLate).
    // It is never queued or run here, so the command log does not record it, nor the EndTurn.
    // CHANGE: ENHANCEMENT - An end turn that took off (a Takeoff queued before it, or the human's
    // ranger taking off here) is taken back with the takeoff: the cancel takes the EndTurn's place
    // in the queue and runs after the Takeoff (aPlayerActions.ExecuteCancelEndTurn), as on the
    // client.
    procedure CancelEndTurn(Peer: THostPeer; Sequence: Cardinal; const Command: TPlayerCommand);
    // CHANGE: ENHANCEMENT - The day waits for the human: it holds the day and its peer has no
    // EndTurn queued (the host's own: it holds the day), or it continues its travel and its peer
    // lags behind. WaitingFor and Status (HoldsDay) say this.
    function DayWaitsFor(Human: THuman): Boolean;
  public
    // Joins wait while this is set; the headless host sets it until every client is there,
    // so that the humans join in the same order every run (by name).
    HoldJoins: Boolean;
    // CHANGE: ENHANCEMENT - Whether the host may change the game under its screen now, so that
    // the pump applies a peer's trade as it arrives (docs/network.md, Trades); nil: never, and
    // the trades wait for the barrier. Asked at a quiet point only.
    MayApplyTrades: function: Boolean;
    // A human's trades wait until every human before it in Session.Humans is ready, and arrival
    // order does not count: the headless host's days are then the same however the commands
    // arrived (docs/network.md, Tests).
    OrderedTrades: Boolean;
    // For the tests (docs/network.md, Tests): around each trade applied as it arrives; where a
    // new human joins (a TPlanet; nil: FindJoinPlanet's); a new human that joined.
    TradeHook: TNetTradeHook;
    JoinPlanetHook: function(Race: Integer): TObject;
    JoinedHook: procedure(Human: THuman);
    // Listens on Port (0 picks one). The humans other than the local one start disconnected
    // until their players rejoin.
    constructor Create(Port: Integer; const HostName: WideString);
    destructor Destroy; override;
    // Moves messages into the peers' queues; at a quiet point also takes joins and
    // disconnects. The UI calls it every frame; the headless runner while it waits.
    procedure Pump;
    // No turn job runs and no day is under way (BeginDay .. SendState).
    function Quiet: Boolean;
    // A day has begun (BeginDay) and its state has not been sent yet.
    property DayUnderWay: Boolean read FDayUnderWay;
    function PendingJoinCount: Integer;
    // CHANGE: ENHANCEMENT - The pending joins that can be taken now: a rejoin, or a first join
    // whose character has come.
    function ReadyJoinCount: Integer;
    function JoinedCount: Integer;
    // Every joined peer is ready: its queue holds an EndTurn, or its human does not hold
    // the day. CHANGE: ENHANCEMENT - A peer whose human does not hold the day (it continues its
    // travel) must also have applied the state before the last one: the host runs at most one
    // day ahead of a client (docs/network.md, Continuing travel).
    function PeersReady: Boolean;
    // The humans the day waits for, for a waiting screen or a log.
    function WaitingFor: AnsiString;
    // Applies the queues, human by human in Session.Humans order, each up to and including
    // its EndTurn, through SubmitCommand (so the command log records them). A queue without
    // an EndTurn waits for the next day. CHANGE: ENHANCEMENT - Except a StopContinuing of a
    // human who continues its travel: it is applied, with what comes before it, so that the
    // player's break holds the next day (docs/network.md, Continuing travel).
    procedure ApplyQueues;
    // The commands of the human's peer waiting in its queue, in arrival order (a copy).
    function QueuedCommands(HumanId: Integer): TQueuedCommands;
    // CHANGE: ENHANCEMENT - Sends a trade the host applied (any human's, the host's own too) to
    // the clients whose humans are at the same planet or station as its actor, except the
    // actor's; a trade in space and the trades the barrier applies go to nobody
    // (docs/network.md, Trades).
    procedure RelayTrade(const Command: TPlayerCommand);
    // The day starts: no join or disconnect until the state after it is sent.
    procedure BeginDay;
    // Sends the films the player-star job encoded to the clients in their stars; returns the
    // compressed bytes of the distinct films.
    function SendFilms: Integer;
    // The uncompressed bytes of the distinct films sent so far.
    property SentFilmRawBytes: Int64 read FSentFilmRawBytes;
    // Takes the state (a quiet point after the day) and queues it for every joined peer;
    // the day is over. The caller frees the job once it is Done.
    function SendState(MeasureWhole: Boolean): TNetStateJob;
    // Whether every joined peer has acknowledged the state numbered Serial.
    function AllAcked(Serial: Integer): Boolean;
    // Says Bye to every peer and waits up to TimeoutMs for the bytes to leave.
    procedure Shutdown(TimeoutMs: Integer);
    // CHANGE: ENHANCEMENT - The host stops hosting (the in-game menu): every joined peer's human
    // is disconnected as a leaver's is (docs/network.md, Disconnects), in Session.Humans order,
    // and the peers' queued commands are dropped. At a quiet point on the UI thread, before
    // Shutdown says Bye.
    procedure DisconnectHumans;
    // CHANGE: ENHANCEMENT - For the tests (docs/network.md, Tests): the network thread stops
    // reading, writing and pinging every peer's connection (TNetThread.FreezePeer), so that the
    // clients see only silence. Returns the peers it froze, for RemovePeer later.
    function FreezePeers: TPeerIds;
    // On the turn thread: asks Human, whose talk fields are set, through its
    // client (docs/network.md, Remote dialogue). Sends TalkRequest, then reads only that
    // peer's inbox: each Command of the human runs at once through SubmitCommand, recorded as
    // the UI's commands in a talk are, and TalkDone ends the talk. False when the human has no
    // peer, the peer leaves, or no TalkDone comes within RemoteTalkTimeoutMs.
    function RemoteTalk(Human: THuman): Boolean;
    // The human whose answer to a dialogue the running day waits for (RemoteTalk); 0 when
    // none. Set on the turn thread; the host's own wait reads it.
    property TalkHumanId: Integer read FTalkHumanId;
    property Thread: TNetThread read FThread;
    property LastSerial: Integer read FSerial;
    // How long taking the last state took (checkpoint and hash).
    property LastTakeMs: Integer read FLastTakeMs;
    // CHANGE: ENHANCEMENT - How many EndTurns the peers took back (CancelEndTurn), for the tests.
    property CancelledEndTurns: Integer read FCancelledEndTurns;
    property StoppedTravels: Integer read FStoppedTravels;
    // CHANGE: ENHANCEMENT - A page of the host's own human's text quest (QuestPage.QuestPageHook):
    // kept and sent to every joined client. Pages are presentation: nothing here is a command.
    procedure PublishQuestPage(const Page: TWatchedQuestPage);
    // The latest text-quest page of each human, the host's own included (the watch window's).
    property QuestPages: TQuestPageStore read FQuestPages;
  end;

var
  // The running host, for the turn-thread hook.
  ActiveHost: TNetHost;
  // How long a remote dialogue waits for the client's TalkDone.
  RemoteTalkTimeoutMs: Integer = 10 * 60 * 1000;
// StarDayHook of a host: encodes the film of a star that holds a joined peer's human.
procedure HostStarDay(Star, Film: TObject; Recorded: Boolean);
// DayCompletedHook of a host: the films of the day are ready to send.
procedure HostDayCompleted;
// aHuman.RemoteTalkHook of a host (TNetHost.RemoteTalk).
function HostRemoteTalk(Human: THuman): Boolean;
// CHANGE: ENHANCEMENT - aCommands.NetworkCommandHook of a host: relays a trade (RelayTrade).
procedure HostCommandSubmitted(const Command: TPlayerCommand);
implementation
uses
  aEFilm,
  aGalaxy,
  aHoldActions,
  aObjectRefs,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aQuestActions,
  aSession,
  aSaveLoad,
  aShopStock,
  GR_Main,
  NetDelta,
  SimEvents,
  SimulationThread,
  ThreadCalc;

const
  // States kept besides the ones a peer holds as its base, for acknowledgements in flight.
  KeptStates = 4;

type
  TNetHostFilm = class
    Day: Integer;
    StarId: Integer;
    // The film compressed (CompressState), and its size before.
    Bytes: TBufEC;
    RawSize: Integer;
    HumanIds: array of Integer;
    destructor Destroy; override;
  end;

destructor TNetHostFilm.Destroy;
begin
  Bytes.Free;
  inherited;
end;

destructor THostPeer.Destroy;
var
  I: Integer;
begin
  if Base <> nil then
    Base.Release;
  if Deferred <> nil then
    for I := 0 to Deferred.Count - 1 do
      TObject(Deferred[I]).Free;
  Deferred.Free;
  inherited;
end;

function THostPeer.StopIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(Queue) do
    if Queue[I].Command.Kind = ckStopContinuing then
      Exit(I);
  Result := -1;
end;

function THostPeer.TradeIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(Queue) do
    if Queue[I].Command.Kind = ckEndTurn then
      Exit(-1)
    else if IsTradeCommand(Queue[I].Command.Kind) then
      Exit(I);
  Result := -1;
end;

function THostPeer.EndTurnIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(Queue) do
    if Queue[I].Command.Kind = ckEndTurn then
      Exit(I);
  Result := -1;
end;

constructor TNetHost.Create(Port: Integer; const HostName: WideString);
var
  I: Integer;
begin
  inherited Create;
  FName := HostName;
  FPeers := TList.Create;
  FStates := TList.Create;
  FFilms := TList.Create;
  FFilmLock := TCriticalSection.Create;
  FLastStatus := TBufEC.Create;
  FJoinJobs := TList.Create;
  FTalkLock := TCriticalSection.Create;
  FQuestPages := TQuestPageStore.Create;
  FThread := TNetThread.Create(Port);
  NewHumansConnected := False;
  for I := 0 to Session.Humans.Count - 1 do
    if Session.Humans[I] <> LocalHuman then
      Session.Humans[I].Connected := False;
  ActiveHost := Self;
  NetLog(Format('host listens on port %d', [FThread.ListenPort]));
end;

destructor TNetHost.Destroy;
var
  I: Integer;
begin
  if ActiveHost = Self then
    ActiveHost := nil;
  FThread.Free;
  for I := 0 to FJoinJobs.Count - 1 do
    TObject(FJoinJobs[I]).Free;
  FJoinJobs.Free;
  for I := 0 to FPeers.Count - 1 do
    TObject(FPeers[I]).Free;
  FPeers.Free;
  for I := 0 to FStates.Count - 1 do
    TNetState(FStates[I]).Release;
  FStates.Free;
  for I := 0 to FFilms.Count - 1 do
    TObject(FFilms[I]).Free;
  FFilms.Free;
  FFilmLock.Free;
  FTalkLock.Free;
  FLastStatus.Free;
  FQuestPages.Free;
  NewHumansConnected := True;
  for I := 0 to Session.Humans.Count - 1 do
    Session.Humans[I].Connected := True;
  inherited;
end;

function TNetHost.FindPeer(PeerId: Integer): THostPeer;
var
  I: Integer;
begin
  for I := 0 to FPeers.Count - 1 do
    if THostPeer(FPeers[I]).PeerId = PeerId then
      Exit(THostPeer(FPeers[I]));
  Result := nil;
end;

// The joined peer that plays the human, or nil.
function PeerOfHuman(Peers: TList; HumanId: Integer): THostPeer;
var
  I: Integer;
begin
  for I := 0 to Peers.Count - 1 do
  begin
    Result := THostPeer(Peers[I]);
    if (Result.State = hpJoined) and (Result.HumanId = HumanId) then
      Exit;
  end;
  Result := nil;
end;

// CHANGE: BUGFIX - Whether only the host's human may give the command: the session flags are
// the host's (docs/humans.md, Session flags; docs/network.md, Commands). A peer's is refused.
function IsHostOnlyCommand(const Command: TPlayerCommand): Boolean;
begin
  // CHANGE: ENHANCEMENT - A relay's form (aCommands.IsRelayOnlyCommand) comes only from a host.
  Result := (Command.Kind = ckSetSessionFlag) or IsRelayOnlyCommand(Command.Kind);
end;

procedure TNetHost.Refuse(Peer: THostPeer; const Reason: WideString);
var
  Payload: TBufEC;
begin
  NetLog('refused ' + UTF8Encode(Peer.Hello.Name) + ': ' + UTF8Encode(Reason));
  Payload := TBufEC.Create;
  try
    EncodeRefuse(Reason, Payload);
    FThread.Send(Peer.PeerId, nkRefuse, Payload);
  finally
    Payload.Free;
  end;
  FThread.ClosePeer(Peer.PeerId);
  // Not joined, so nothing to disconnect; it goes at the next quiet point.
  Peer.State := hpHello;
  Peer.Leaving := True;
end;

procedure TNetHost.HandleMessage(Peer: THostPeer; Kind: TNetMessageKind; Payload: TBufEC);
var
  Command: TPlayerCommand;
  Sequence: Cardinal;
  Chat: TChatMessage;
  Serial, I: Integer;
  Other: THostPeer;
  Character: TCharacterMessage;
  Page: TWatchedQuestPage;
begin
  if Peer.Leaving then
    Exit;
  case Kind of
    nkHello:
      if Peer.State = hpHello then
      begin
        Peer.Hello := DecodeHello(Payload);
        if Peer.Hello.Protocol <> ProtocolVersion then
          Refuse(
              Peer,
              WideString(Format('protocol %d, the host speaks %d', [Peer.Hello.Protocol, ProtocolVersion]))
          )
        else if Peer.Hello.DataHash <> DataHash then
          Refuse(Peer, 'the game data differs from the host''s')
        else if Peer.Hello.Name = '' then
          Refuse(Peer, 'no name')
        else if Peer.Hello.Spectator then
          Refuse(Peer, 'spectators are not supported')
        else
          Peer.State := hpPendingJoin;
      end;
    nkCommand:
      if Peer.State = hpJoined then
      begin
        Command := DecodeCommandMessage(Payload, Sequence);
        if Integer(Command.Actor) <> Peer.HumanId then
          NetLog(
              Format(
                  'refused %s from human %d: it names human %d',
                  [CommandKindName(Command.Kind), Peer.HumanId, Command.Actor]
              )
          )
        else if IsHostOnlyCommand(Command) then
          RefuseHostOnlyCommand(Peer, Sequence, Command)
        // CHANGE: ENHANCEMENT - Not queued: it takes the queued EndTurn back.
        else if Command.Kind = ckCancelEndTurn then
          CancelEndTurn(Peer, Sequence, Command)
        else
        begin
          I := Length(Peer.Queue);
          SetLength(Peer.Queue, I + 1);
          Peer.Queue[I].Sequence := Sequence;
          Peer.Queue[I].Command := Command;
          // CHANGE: ENHANCEMENT - A trade applies as it arrives, with what the peer sent before
          // it, so arrival order decides between humans (docs/network.md, Trades).
          if FTradesAllowed and not OrderedTrades and (Peer.TradeIndex = I) then
            ApplyTrade(Peer, I);
        end;
      end;
    nkAck:
      if Peer.State = hpJoined then
      begin
        Serial := DecodeAck(Payload);
        Peer.AckedSerial := Serial;
        if Peer.Base <> nil then
          Peer.Base.Release;
        Peer.Base := nil;
        for I := 0 to FStates.Count - 1 do
          if TNetState(FStates[I]).Serial = Serial then
            Peer.Base := TNetState(FStates[I]).AddRef;
      end;
    nkChat:
      if Peer.State = hpJoined then
      begin
        Chat := DecodeChat(Payload);
        Chat.SenderId := Peer.HumanId;
        Payload.Clear;
        EncodeChat(Chat, Payload);
        for I := 0 to FPeers.Count - 1 do
        begin
          Other := THostPeer(FPeers[I]);
          if (Other <> Peer) and (Other.State = hpJoined) and not Other.Leaving then
            FThread.Send(Other.PeerId, nkChat, Payload);
        end;
      end;
    nkCharacter:
      if (Peer.State = hpPendingJoin) and Peer.CharacterAsked and not Peer.HasCharacter then
      begin
        Character := DecodeCharacter(Payload);
        if Character.Name = '' then
          Refuse(Peer, 'no name')
        else
        begin
          Peer.Hello.Name := Character.Name;
          Peer.Character := Character.Character;
          Peer.HasCharacter := True;
        end;
      end;
    // CHANGE: ENHANCEMENT - A page of the peer's human's text quest: kept and passed on, as it
    // is, to everyone else; it names the peer's human whatever it says.
    nkQuestPage:
      if Peer.State = hpJoined then
      begin
        Page := DecodeWatchedQuestPage(Payload);
        Page.HumanId := Peer.HumanId;
        FQuestPages.Put(Page);
        NetLogQuestPage('relayed', Page, SendQuestPage(Page, Peer));
      end;
    nkBye:
      Peer.Leaving := True;
  end;
end;

function TNetHost.SendQuestPage(const Page: TWatchedQuestPage; Skip: THostPeer): Integer;
var
  I: Integer;
  Peer: THostPeer;
  Payload: TBufEC;
begin
  Result := 0;
  Payload := nil;
  try
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := THostPeer(FPeers[I]);
      if (Peer = Skip) or (Peer.State <> hpJoined) or Peer.Leaving or (Peer.HumanId = Page.HumanId) then
        Continue;
      if Payload = nil then
      begin
        Payload := TBufEC.Create;
        EncodeWatchedQuestPage(Page, Payload);
      end;
      FThread.Send(Peer.PeerId, nkQuestPage, Payload);
      Inc(Result);
    end;
  finally
    Payload.Free;
  end;
end;

procedure TNetHost.PublishQuestPage(const Page: TWatchedQuestPage);
begin
  FQuestPages.Put(Page);
  NetLogQuestPage('sent', Page, SendQuestPage(Page, nil));
end;

procedure TNetHost.Pump;
var
  Id, I: Integer;
  Peer: THostPeer;
  Kind: TNetMessageKind;
  Payload: TBufEC;
begin
  // CHANGE: ENHANCEMENT - At a quiet point where the host's screen allows it, a peer's trade
  // applies as it arrives (docs/network.md, Trades).
  FTradesAllowed := Quiet and Assigned(MayApplyTrades) and MayApplyTrades();
  // The turn thread reads the peer list (HostStarDay) while a job runs; new peers wait for it.
  while not IsTurnCalculationRunning and FThread.TakeNewPeer(Id) do
  begin
    Peer := THostPeer.Create;
    Peer.PeerId := Id;
    Peer.HumanId := -1;
    Peer.Deferred := TList.Create;
    FPeers.Add(Peer);
  end;
  Payload := TBufEC.Create;
  try
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := THostPeer(FPeers[I]);
      while not Peer.Leaving and ReceiveUnlessInTalk(Peer, Kind, Payload) do
        try
          HandleMessage(Peer, Kind, Payload);
        except
          on E: Exception do
          begin
            NetLog(Format('bad %s from peer %d: %s', [MessageKindName(Kind), Peer.PeerId, E.Message]));
            FThread.ClosePeer(Peer.PeerId);
            Peer.Leaving := True;
          end;
        end;
      if not Peer.Leaving and FThread.IsClosed(Peer.PeerId) then
      begin
        // CHANGE: ENHANCEMENT - Why, for the log: closed by the other side, a failed socket, or
        // silence (NetThread.NetSilenceTimeoutMs).
        NetLog(
            Format(
                'connection of peer %d (%s) lost: %s',
                [Peer.PeerId, UTF8Encode(Peer.Hello.Name), FThread.PeerError(Peer.PeerId)]
            )
        );
        Peer.Leaving := True;
      end;
    end;
  finally
    Payload.Free;
  end;
  // CHANGE: ENHANCEMENT - A Hello that brings a connected human's token takes that human over
  // (docs/network.md, Joining). Not while a job runs: it may free a ranger whose name this reads.
  if not IsTurnCalculationRunning then
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := THostPeer(FPeers[I]);
      if (Peer.State = hpPendingJoin) and not Peer.Leaving and not Peer.TakeOverChecked then
      begin
        Peer.TakeOverChecked := True;
        TakeOver(Peer);
      end;
    end;
  if FTradesAllowed then
    ApplyWaitingTrades;
  FTradesAllowed := False;
  // The film goes first: it is small and needed first (docs/network.md, Films). Every film of
  // the day is in once the day has run, so it goes while the galaxy job runs.
  if FDayRan then
    SendFilms;
  for I := FJoinJobs.Count - 1 downto 0 do
    if TNetStateJob(FJoinJobs[I]).Done then
    begin
      TObject(FJoinJobs[I]).Free;
      FJoinJobs.Delete(I);
    end;
  if Quiet then
  begin
    ProcessLeaving;
    AskCharacters;
    if not HoldJoins then
      ProcessJoins;
  end;
  // A job may free a ranger whose name the status reads.
  if not IsTurnCalculationRunning then
    SendStatus(False);
end;

// The peer's next message for the pump: a message the turn thread left during a talk, then
// the inbox; none while the turn thread reads the inbox (THostPeer.InTalk). Under the lock, a
// message the pump takes was in the inbox before a TalkRequest went, so it is no answer.
function TNetHost.ReceiveUnlessInTalk(
    Peer: THostPeer;
    out Kind: TNetMessageKind;
    Payload: TBufEC
): Boolean;
var
  Message: TNetMessage;
begin
  FTalkLock.Enter;
  try
    Result := False;
    Kind := 0;
    if Peer.InTalk then
      Exit;
    if Peer.Deferred.Count > 0 then
    begin
      Message := TNetMessage(Peer.Deferred[0]);
      Peer.Deferred.Delete(0);
      try
        Kind := Message.Kind;
        Payload.Clear;
        if Message.Payload.DataSize > 0 then
          Payload.AddBytes(Message.Payload.Data, Message.Payload.DataSize);
        Payload.SetPosition(0);
      finally
        Message.Free;
      end;
      Exit(True);
    end;
    Result := FThread.Receive(Peer.PeerId, Kind, Payload);
  finally
    FTalkLock.Leave;
  end;
end;

function TNetHost.Quiet: Boolean;
begin
  Result := not FDayUnderWay and not IsTurnCalculationRunning;
end;

function TNetHost.PendingJoinCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FPeers.Count - 1 do
    if (THostPeer(FPeers[I]).State = hpPendingJoin) and not THostPeer(FPeers[I]).Leaving then
      Inc(Result);
end;

function TNetHost.FindNamedHuman(const Name: WideString): THuman;
var
  I: Integer;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Result := Session.Humans[I];
    if (Result.Player <> nil) and (Result.Player.Name = Name) then
      Exit;
  end;
  Result := nil;
end;

function TNetHost.HumanToken(HumanId: Integer; Issue: Boolean): QWord;
var
  I: Integer;
begin
  for I := 0 to High(FTokenHumans) do
    if FTokenHumans[I] = HumanId then
      Exit(FTokens[I]);
  Result := 0;
  if not Issue then
    Exit;
  Result := NewToken;
  Insert(HumanId, FTokenHumans, Length(FTokenHumans));
  Insert(Result, FTokens, Length(FTokens));
end;

function TNetHost.TakeOver(Peer: THostPeer): Boolean;
var
  Human: THuman;
  Old: THostPeer;
begin
  Result := False;
  if Peer.Hello.Token = 0 then
    Exit;
  Human := FindNamedHuman(Peer.Hello.Name);
  // A human that is not connected is an ordinary rejoin; without the token the join is refused
  // as before (ProcessJoins), so nobody throws a live player out by typing its name.
  if (Human = nil) or (Human = LocalHuman) or not Human.Connected
      or (HumanToken(Human.Id, False) <> Peer.Hello.Token) then
    Exit;
  Old := PeerOfHuman(FPeers, Human.Id);
  // One that is leaving anyway goes at the next quiet point, before the joins.
  if (Old = nil) or (Old = Peer) or Old.Leaving then
    Exit;
  NetLog(Format('human %d (%s) taken over by a new connection', [Human.Id, UTF8Encode(Peer.Hello.Name)]));
  // At once, so that nothing more goes to the old connection; the peer itself stays until
  // ProcessLeaving disconnects its human, and then the new peer rejoins (ProcessJoins).
  FThread.RemovePeer(Old.PeerId);
  Old.Leaving := True;
  Result := True;
end;

// A pending join that can be taken: its name is a human's (a rejoin, or a refusal), or it is
// a first join whose character has come.
function TNetHost.JoinReady(Peer: THostPeer): Boolean;
begin
  Result := Peer.HasCharacter or (FindNamedHuman(Peer.Hello.Name) <> nil);
end;

function TNetHost.ReadyJoinCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FPeers.Count - 1 do
    if (THostPeer(FPeers[I]).State = hpPendingJoin)
        and not THostPeer(FPeers[I]).Leaving
        and JoinReady(THostPeer(FPeers[I])) then
      Inc(Result);
end;

// A first join (a name no human has) chooses its character on the new-game screen first.
procedure TNetHost.AskCharacters;
var
  I: Integer;
  Peer: THostPeer;
begin
  for I := 0 to FPeers.Count - 1 do
  begin
    Peer := THostPeer(FPeers[I]);
    if (Peer.State = hpPendingJoin)
        and not Peer.Leaving
        and not Peer.CharacterAsked
        and (FindNamedHuman(Peer.Hello.Name) = nil) then
    begin
      Peer.CharacterAsked := True;
      FThread.Send(Peer.PeerId, nkNewHuman, nil, 0);
      NetLog(Format('peer %d (%s) chooses its character', [Peer.PeerId, UTF8Encode(Peer.Hello.Name)]));
    end;
  end;
end;

function TNetHost.JoinedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FPeers.Count - 1 do
    if (THostPeer(FPeers[I]).State = hpJoined) and not THostPeer(FPeers[I]).Leaving then
      Inc(Result);
end;

// Disconnects the peers that left, in Session.Humans order: each joined one's human stops
// holding the day and its ranger holds position (HoldPosition as that human: no order, no
// automatic control).
procedure TNetHost.DisconnectHuman(Human: THuman; Peer: THostPeer);
var
  Command: TPlayerCommand;
  Page: TWatchedQuestPage;
begin
  Peer.State := hpHello;
  Human.Connected := False;
  NetLog(Format('human %d (%s) disconnected', [Human.Id, UTF8Encode(Peer.Hello.Name)]));
  // CHANGE: ENHANCEMENT - A text quest it plays is abandoned (docs/progress/
  // 2026-10-19-text-quests-plan.md, Disconnects): its commands after BeginTextQuest go with the
  // peer's queue, so the quest never happened here, and another human may play the planet's.
  if Human.TextQuestOpen then
  begin
    NetLog(
        Format(
            'human %d (%s) abandoned its text quest planet=%d',
            [Human.Id, UTF8Encode(Peer.Hello.Name), Human.TextQuestPlanetId]
        )
    );
    Human.ReleaseTextQuest;
  end;
  // CHANGE: ENHANCEMENT - The watchers of a quest it left open get its end page (Phase D).
  if FQuestPages.Playing(Human.Id) and FQuestPages.Latest(Human.Id, Page) then
  begin
    Page := AbandonedQuestPage(Page);
    FQuestPages.Put(Page);
    NetLogQuestPage('abandoned', Page, SendQuestPage(Page, Peer));
  end;
  if (Human.Player <> nil) and not Human.Player.InHyperspace and not Human.Finished then
  begin
    Command := NewCommand(ckHoldPosition);
    Command.Actor := Cardinal(Human.Id);
    SubmitCommand(Command);
  end
  else
    // CHANGE: BUGFIX - HoldPosition frees a ship whose screen the human had open; without it,
    // nothing else would (aHuman.THuman.EditedShip).
    Human.ReleaseShipScreen;
end;

procedure TNetHost.ProcessLeaving;
var
  I: Integer;
  Human: THuman;
  Peer: THostPeer;
begin
  I := 0;
  while I < Session.Humans.Count do
  begin
    Human := Session.Humans[I];
    Inc(I);
    Peer := PeerOfHuman(FPeers, Human.Id);
    if (Peer = nil) or not Peer.Leaving then
      Continue;
    DisconnectHuman(Human, Peer);
  end;
  for I := FPeers.Count - 1 downto 0 do
  begin
    Peer := THostPeer(FPeers[I]);
    // A peer whose human has gone (no planet took its ranger) leaves as well.
    if Peer.Leaving then
    begin
      FThread.RemovePeer(Peer.PeerId);
      FPeers.Delete(I);
      Peer.Free;
    end;
  end;
end;

function CompareHelloNames(Left, Right: Pointer): Integer;
begin
  Result := WideCompareStr(THostPeer(Left).Hello.Name, THostPeer(Right).Hello.Name);
  if Result = 0 then
    Result := THostPeer(Left).PeerId - THostPeer(Right).PeerId;
end;

// The pending joins, by name: a disconnected human whose ranger has the name is taken back;
// otherwise a new human joins, by the JoinHuman command as the host's human. Each joined peer
// gets Welcome and the whole state after these joins.
procedure TNetHost.ProcessJoins;
var
  Pending: TList;
  I, Joined: Integer;
  Peer: THostPeer;
  Human, Found: THuman;
  Planet: TPlanet;
  Character: TJoinCharacter;
  Welcome: TWelcomeMessage;
  Payload: TBufEC;
  State: TNetState;
  Job: TNetStateJob;
  Playing: TQuestHumanIds;
  Page: TWatchedQuestPage;
  J: Integer;
begin
  Pending := TList.Create;
  Payload := TBufEC.Create;
  try
    for I := 0 to FPeers.Count - 1 do
      if (THostPeer(FPeers[I]).State = hpPendingJoin)
          and not THostPeer(FPeers[I]).Leaving
          and JoinReady(THostPeer(FPeers[I])) then
        Pending.Add(FPeers[I]);
    if Pending.Count = 0 then
      Exit;
    Pending.Sort(@CompareHelloNames);
    Joined := 0;
    for I := 0 to Pending.Count - 1 do
    begin
      Peer := THostPeer(Pending[I]);
      Found := FindNamedHuman(Peer.Hello.Name);
      if Found <> nil then
      begin
        if (Found = LocalHuman) or Found.Connected then
        begin
          Refuse(Peer, 'a human of that name plays');
          Continue;
        end;
        Human := Found;
        NetLog(Format('human %d (%s) rejoined', [Human.Id, UTF8Encode(Peer.Hello.Name)]));
      end
      else
      begin
        Character := Peer.Character;
        if (Character.Preset < 1) or (Character.Preset > 5) then
          Character.Preset := 1 + Session.Humans.Count mod 5;
        if Assigned(JoinPlanetHook) then
          Planet := TPlanet(JoinPlanetHook(Character.Race))
        else
          Planet := FindJoinPlanet(Character.Race);
        if Planet = nil then
        begin
          Refuse(Peer, 'no planet to join at');
          Continue;
        end;
        // The portraits are the race's; with no planet of the chosen race it is another one.
        if Planet.RaceId <> Character.Race then
          Character.Face := 0;
        Human := JoinHumanAt(Planet, Peer.Hello.Name, Character);
        NetLog(
            Format(
                'human %d (%s) joined at planet %d in star %d',
                [Human.Id, UTF8Encode(Peer.Hello.Name), Planet.Id, Planet.CurrentStar.Id]
            )
        );
      end;
      if (Found = nil) and Assigned(JoinedHook) then
        JoinedHook(Human);
      Human.Connected := True;
      Peer.State := hpJoined;
      Peer.HumanId := Human.Id;
      Peer.AckedSerial := 0;
      SetLength(Peer.Queue, 0);
      Payload.Clear;
      Welcome.HumanId := Human.Id;
      Welcome.HostName := FName;
      // CHANGE: ENHANCEMENT - The same token for every join of the human in this session.
      Welcome.Token := HumanToken(Human.Id, True);
      EncodeWelcome(Welcome, Payload);
      FThread.Send(Peer.PeerId, nkWelcome, Payload);
      // CHANGE: ENHANCEMENT - The latest page of each other human's open text quest, so that it
      // can be watched before its next page.
      Playing := FQuestPages.PlayingHumans(Human.Id);
      for J := 0 to High(Playing) do
        if FQuestPages.Latest(Playing[J], Page) then
        begin
          Payload.Clear;
          EncodeWatchedQuestPage(Page, Payload);
          FThread.Send(Peer.PeerId, nkQuestPage, Payload);
          NetLogQuestPage('caught-up', Page, 1);
        end;
      Inc(Joined);
    end;
    if Joined = 0 then
      Exit;
    State := TakeState;
    try
      Job := TNetStateJob.Create(State);
    finally
      State.Release;
    end;
    for I := 0 to Pending.Count - 1 do
    begin
      Peer := THostPeer(Pending[I]);
      if Peer.State = hpJoined then
        Job.AddTarget(Peer.PeerId, nil);
    end;
    FThread.QueueStateJob(Job);
    FJoinJobs.Add(Job);
    SendStatus(True);
  finally
    Pending.Free;
    Payload.Free;
  end;
end;

// On the UI thread, or on the turn thread in a remote dialogue: the pump sends no status while
// a job runs, so the two never overlap.
procedure TNetHost.SendStatus(Force: Boolean);
var
  Status: TStatusMessage;
  Payload: TBufEC;
  I: Integer;
  Human: THuman;
  Peer: THostPeer;
begin
  Status.DayRunning := FDayUnderWay;
  Status.TalkHumanId := FTalkHumanId;
  SetLength(Status.Humans, Session.Humans.Count);
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Status.Humans[I].Id := Human.Id;
    if Human.Player <> nil then
      Status.Humans[I].Name := Human.Player.Name
    else
      Status.Humans[I].Name := '';
    Status.Humans[I].Connected := Human.Connected;
    // CHANGE: ENHANCEMENT - Whether the day waits for it: a peer whose EndTurn is queued (and
    // not taken back) does not hold it, though its human has not ended the turn here yet. During
    // the day (the turn thread sends the status in a remote dialogue) as the humans stand.
    if FDayUnderWay then
      Status.Humans[I].HoldsDay := HumanHoldsDay(Human)
    else
      Status.Humans[I].HoldsDay := DayWaitsFor(Human);
    // CHANGE: ENHANCEMENT - Its text quest (docs/progress/2026-10-19-text-quests-plan.md, The
    // day): open from its BeginTextQuest, which runs here as it arrives (for the host's own
    // human, at once), to the CloseQuest the barrier applies; then the days it owes.
    Status.Humans[I].QuestDays := Human.QuestDaysOwed;
    Status.Humans[I].Activity := HumanQuestActivity(Human);
  end;
  Payload := TBufEC.Create;
  try
    EncodeStatus(Status, Payload);
    if not Force and (Payload.DataSize = FLastStatus.DataSize)
        and CompareMem(Payload.Data, FLastStatus.Data, Payload.DataSize) then
      Exit;
    FLastStatus.Clear;
    FLastStatus.AddBytes(Payload.Data, Payload.DataSize);
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := THostPeer(FPeers[I]);
      if (Peer.State = hpJoined) and not Peer.Leaving then
        FThread.Send(Peer.PeerId, nkStatus, Payload);
    end;
  finally
    Payload.Free;
  end;
end;

// CHANGE: ENHANCEMENT - The human continues its travel here, and the peer's queue holds a
// StopContinuing (the film's break, or a CancelEndTurn), which the barrier applies with the
// peer's next EndTurn: then it holds the day, which waits for that EndTurn (PeersReady). Not in
// hyperspace, where the travel cannot stop.
function StopPending(Peer: THostPeer; Human: THuman): Boolean;
begin
  Result :=
      Human.ContinueUntilArrival
          and Human.Connected
          and not Human.Finished
          and (Human.Player <> nil)
          and not Human.Player.InHyperspace
          and (Peer.StopIndex >= 0);
end;

function TNetHost.LagsBehind(Peer: THostPeer; Human: THuman): Boolean;
begin
  Result :=
      (Human <> nil)
          and Human.Connected
          and Human.ContinueUntilArrival
          and not HumanHoldsDay(Human)
          and (Peer.AckedSerial > 0)
          and (Peer.AckedSerial < FSerial - 1);
end;

function TNetHost.PeersReady: Boolean;
var
  I: Integer;
  Peer: THostPeer;
  Human: THuman;
begin
  for I := 0 to FPeers.Count - 1 do
  begin
    Peer := THostPeer(FPeers[I]);
    if (Peer.State <> hpJoined) or Peer.Leaving then
      Continue;
    Human := FindHuman(Peer.HumanId);
    if (Human <> nil) and HumanHoldsDay(Human) and (Peer.EndTurnIndex < 0) then
      Exit(False);
    // CHANGE: ENHANCEMENT - A continuing human whose stop is queued holds the day already.
    if (Human <> nil) and StopPending(Peer, Human) and (Peer.EndTurnIndex < 0) then
      Exit(False);
    if LagsBehind(Peer, Human) then
      Exit(False);
  end;
  Result := True;
end;

function TNetHost.DayWaitsFor(Human: THuman): Boolean;
var
  Peer: THostPeer;
begin
  Peer := PeerOfHuman(FPeers, Human.Id);
  if not HumanHoldsDay(Human) then
    Result :=
        (Peer <> nil)
            and (LagsBehind(Peer, Human) or (StopPending(Peer, Human) and (Peer.EndTurnIndex < 0)))
  else
    Result := (Peer = nil) or (Peer.EndTurnIndex < 0);
end;

function TNetHost.WaitingFor: AnsiString;
var
  I: Integer;
  Human: THuman;
begin
  Result := '';
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if not DayWaitsFor(Human) then
      Continue;
    if Result <> '' then
      Result := Result + ',';
    Result := Result + IntToStr(Human.Id);
  end;
end;

procedure TNetHost.ApplyQueues;
var
  I, J, Last: Integer;
  Peer: THostPeer;
begin
  // The state after the day carries what the barrier applies: nothing is relayed.
  FApplyingQueues := True;
  try
    for I := 0 to Session.Humans.Count - 1 do
    begin
      Peer := PeerOfHuman(FPeers, Session.Humans[I].Id);
      if (Peer = nil) or Peer.Leaving then
        Continue;
      Last := Peer.EndTurnIndex;
      if (Last < 0) and Session.Humans[I].ContinueUntilArrival then
        Last := Peer.StopIndex;
      for J := 0 to Last do
        try
          SubmitCommand(Peer.Queue[J].Command);
          // CHANGE: ENHANCEMENT - A trade is answered: its client may still wait for it.
          if IsTradeCommand(Peer.Queue[J].Command.Kind) then
            CommandApplied(Peer, Peer.Queue[J].Sequence, Peer.Queue[J].Command);
        except
          on E: Exception do
            CommandFailed(Peer, Peer.Queue[J].Sequence, Peer.Queue[J].Command, E);
        end;
      if Last >= 0 then
        Delete(Peer.Queue, 0, Last + 1);
    end;
  finally
    FApplyingQueues := False;
  end;
end;

procedure TNetHost.ApplyTrade(Peer: THostPeer; Index: Integer);
var
  J: Integer;
  Trade: TQueuedCommand;
  Applied: Boolean;
begin
  Trade := Peer.Queue[Index];
  if Assigned(TradeHook) then
    TradeHook(Self, Peer.HumanId, Trade, False, False);
  Applied := False;
  for J := 0 to Index do
    try
      SubmitCommand(Peer.Queue[J].Command);
      if J = Index then
      begin
        Applied := True;
        NetLog(
            Format(
                'trade applied human=%d seq=%d kind=%s before=%d',
                [Peer.HumanId, Trade.Sequence, CommandKindName(Trade.Command.Kind), Index]
            )
        );
        CommandApplied(Peer, Trade.Sequence, Trade.Command);
      end;
    except
      on E: Exception do
        CommandFailed(Peer, Peer.Queue[J].Sequence, Peer.Queue[J].Command, E);
    end;
  Delete(Peer.Queue, 0, Index + 1);
  if Assigned(TradeHook) then
    TradeHook(Self, Peer.HumanId, Trade, True, Applied);
end;

// CHANGE: ENHANCEMENT - Whether the peer's end turn at Index took off: a Takeoff is queued before
// it, or its human's ranger takes off here (an order of its automatic control).
function TakeoffQueued(Peer: THostPeer; Index: Integer): Boolean;
var
  I: Integer;
  Human: THuman;
begin
  for I := 0 to Index - 1 do
    if Peer.Queue[I].Command.Kind = ckTakeoff then
      Exit(True);
  Human := FindHuman(Peer.HumanId);
  Result := (Human <> nil) and TakeoffMayBeTakenBack(Human.Player);
end;

procedure TNetHost.CancelEndTurn(Peer: THostPeer; Sequence: Cardinal; const Command: TPlayerCommand);
var
  Index: Integer;
  Why: AnsiString;
  Refusal: ECommandRefused;
  StopTravel, Begun, Takeoff: Boolean;
  Stop: TQueuedCommand;
begin
  // The day is checked first: in a remote dialogue the turn thread calls this.
  Index := -1;
  StopTravel := (Length(Command.Ints) > 1) and (Command.Ints[1] <> 0);
  Begun := FDayUnderWay or FApplyingQueues;
  if Begun then
    Why := 'the day has begun'
  // The end turn of a day that has run since (the peer has not applied its state yet).
  else if (Length(Command.Ints) > 0) and (Command.Ints[0] <> Galaxy.CurrentTurn) then
    Why := 'that day has run'
  else
    Why := '';
  if not Begun then
    Index := Peer.EndTurnIndex;
  // CHANGE: ENHANCEMENT - A human whose travel continues sent no EndTurn: its travel stops with
  // a StopContinuing queued as if the peer had sent it, which holds the peer's next day that has
  // not begun (THostPeer.StopPending). Not while the barrier applies the queues; the client
  // stops after the next state then.
  if (Index < 0) and StopTravel and not FApplyingQueues then
  begin
    if Peer.StopIndex < 0 then
    begin
      Stop.Sequence := Sequence;
      Stop.Command := NewCommand(ckStopContinuing);
      Stop.Command.Actor := Command.Actor;
      Insert(Stop, Peer.Queue, Length(Peer.Queue));
    end;
    if Why = '' then
      Inc(FStoppedTravels);
    NetLog(
        Format(
            'travel stop queued human=%d seq=%d accepted=%d day-begun=%d',
            [Peer.HumanId, Sequence, Ord(Why = ''), Ord(Begun)]
        )
    );
  end
  else if (Why = '') and (Index < 0) then
    Why := 'no end turn waits';
  if Why <> '' then
  begin
    Refusal := ECommandRefused.CreateReason(rrTooLate, 'CancelEndTurn: ' + Why);
    try
      CommandFailed(Peer, Sequence, Command, Refusal);
    finally
      Refusal.Free;
    end;
    Exit;
  end;
  if Index < 0 then
  begin
    NetLog(Format('travel stopped human=%d seq=%d ready=%d', [Peer.HumanId, Sequence, Ord(PeersReady)]));
    CommandApplied(Peer, Sequence, Command);
    Exit;
  end;
  // CHANGE: ENHANCEMENT - A takeoff is taken back too: the cancel runs here in the EndTurn's
  // place, after the Takeoff.
  Takeoff := TakeoffQueued(Peer, Index);
  if Takeoff then
  begin
    Peer.Queue[Index].Sequence := Sequence;
    Peer.Queue[Index].Command := Command;
  end
  else
    Delete(Peer.Queue, Index, 1);
  Inc(FCancelledEndTurns);
  NetLog(
      Format(
          'end turn cancelled human=%d seq=%d queued=%d ready=%d takeoff=%d',
          [Peer.HumanId, Sequence, Length(Peer.Queue), Ord(PeersReady), Ord(Takeoff)]
      )
  );
  CommandApplied(Peer, Sequence, Command);
end;

procedure TNetHost.ApplyWaitingTrades;
var
  I, Index: Integer;
  Human: THuman;
  Peer: THostPeer;
begin
  I := 0;
  while I < Session.Humans.Count do
  begin
    Human := Session.Humans[I];
    Inc(I);
    Peer := PeerOfHuman(FPeers, Human.Id);
    if (Peer = nil) or Peer.Leaving then
      Continue;
    repeat
      Index := Peer.TradeIndex;
      if Index >= 0 then
        ApplyTrade(Peer, Index);
    until Index < 0;
    if OrderedTrades and HumanHoldsDay(Human) and (Peer.EndTurnIndex < 0) then
      Exit;
  end;
end;

procedure TNetHost.RelayTrade(const Command: TPlayerCommand);
var
  Actor, Human: THuman;
  Location: TObject;
  Payload: TBufEC;
  I: Integer;
  Peer: THostPeer;
  Relayed: TPlayerCommand;
  Sale: AnsiString;
  Storage: Boolean;
begin
  if FApplyingQueues or not IsTradeCommand(Command.Kind) then
    Exit;
  Actor := FindHuman(Integer(Command.Actor));
  if (Actor = nil) or (Actor.Player = nil) then
    Exit;
  // CHANGE: ENHANCEMENT - A money transfer goes to every other joined client, wherever its human
  // is (aPlayerActions.RelayedTransferOf: the amount, moved without the checks), so that the
  // recipient sees the money and the bubble before the next state.
  if Command.Kind = ckTransferMoney then
  begin
    Relayed := RelayedTransferOf(Command);
    Payload := nil;
    try
      for I := 0 to FPeers.Count - 1 do
      begin
        Peer := THostPeer(FPeers[I]);
        if (Peer.State <> hpJoined) or Peer.Leaving or (Peer.HumanId = Actor.Id) then
          Continue;
        if Payload = nil then
        begin
          Payload := TBufEC.Create;
          EncodeRelayCommand(Actor.Id, Relayed, Payload);
        end;
        FThread.Send(Peer.PeerId, nkRelayCommand, Payload);
        NetLog(
            Format(
                'relayed human=%d kind=%s to=%d recipient=%d amount=%d',
                [Actor.Id, CommandKindName(Relayed.Kind), Peer.HumanId, IntArg(Relayed, 0),
                    IntArg(Relayed, 1)]
            )
        );
      end;
    finally
      Payload.Free;
    end;
    Exit;
  end;
  // CHANGE: ENHANCEMENT - A change to the shared storage goes to the humans who reach the same
  // storage (aPlayer.PlayerStorageLocation: a planet, or the ship docked to), as its effect.
  Storage := IsStorageCommand(Command.Kind);
  if Storage then
    Location := PlayerStorageLocation(Actor.Player)
  else
    Location := HumanShopLocation(Actor);
  if Location = nil then
    Exit;
  // CHANGE: BUGFIX - A ship screen sale runs on what the actor holds, which the hold commands
  // before it (not relayed) put there, so it failed on the other clients. Its effect goes
  // instead (aHoldActions.RelayedSaleOf), or nothing when it put nothing into the location.
  Relayed := Command;
  Sale := '';
  if IsShipScreenSale(Command.Kind) then
  begin
    Relayed := RelayedSaleOf(Command, Location);
    Sale := ' sale=' + CommandKindName(Command.Kind);
    if Relayed.Kind = ckNone then
    begin
      NetLog(
          Format(
              'no relay human=%d kind=%s: the sale put nothing into the location',
              [Actor.Id, CommandKindName(Command.Kind)]
          )
      );
      Exit;
    end;
  end
  // CHANGE: ENHANCEMENT - A BeginTextQuest goes as its lock (aQuestActions.RelayedTextQuestOf):
  // the checks were the host's, and the clients' copies may not have the actor's quest, so that
  // their planet screens say who plays the planet's quest (docs/progress/
  // 2026-10-19-text-quests-plan.md, The lock).
  else if Command.Kind = ckBeginTextQuest then
    Relayed := RelayedTextQuestOf(Command)
  // CHANGE: ENHANCEMENT - A storage command runs on what the actor holds, as a sale does: the
  // pool's entries at the location go instead (aHoldActions.RelayedStorageOf).
  else if Storage then
  begin
    Relayed := RelayedStorageOf(Command);
    Sale := ' storage=' + CommandKindName(Command.Kind);
    if Relayed.Kind = ckNone then
    begin
      NetLog(
          Format(
              'no relay human=%d kind=%s: no storage to relay',
              [Actor.Id, CommandKindName(Command.Kind)]
          )
      );
      Exit;
    end;
  end;
  Payload := nil;
  try
    for I := 0 to FPeers.Count - 1 do
    begin
      Peer := THostPeer(FPeers[I]);
      if (Peer.State <> hpJoined) or Peer.Leaving or (Peer.HumanId = Actor.Id) then
        Continue;
      Human := FindHuman(Peer.HumanId);
      if (Human = nil) or (Human.Player = nil) then
        Continue;
      if Storage then
      begin
        if PlayerStorageLocation(Human.Player) <> Location then
          Continue;
      end
      else if HumanShopLocation(Human) <> Location then
        Continue;
      if Payload = nil then
      begin
        Payload := TBufEC.Create;
        EncodeRelayCommand(Actor.Id, Relayed, Payload);
      end;
      FThread.Send(Peer.PeerId, nkRelayCommand, Payload);
      NetLog(
          Format(
              'relayed human=%d kind=%s to=%d%s',
              [Actor.Id, CommandKindName(Relayed.Kind), Peer.HumanId, Sale]
          )
      );
    end;
  finally
    Payload.Free;
  end;
end;

procedure HostCommandSubmitted(const Command: TPlayerCommand);
begin
  // A remote dialogue's commands run on the turn thread, in space: nothing to relay.
  if (ActiveHost <> nil) and (GetCurrentThreadId = MainThreadID) then
    ActiveHost.RelayTrade(Command);
end;

function TNetHost.QueuedCommands(HumanId: Integer): TQueuedCommands;
var
  Peer: THostPeer;
begin
  Result := nil;
  Peer := PeerOfHuman(FPeers, HumanId);
  if Peer <> nil then
    Result := Copy(Peer.Queue);
end;

procedure TNetHost.CommandFailed(
    Peer: THostPeer;
    Sequence: Cardinal;
    const Command: TPlayerCommand;
    E: Exception
);
var
  Message: TCommandResultMessage;
  Payload: TBufEC;
begin
  Message := Default(TCommandResultMessage);
  Message.Sequence := Sequence;
  Message.Kind := Command.Kind;
  Message.Ok := False;
  Message.Reason := RefusalReasonOf(E);
  Message.Text := WideString(E.Message);
  NetLog(
      Format(
          'command failed human=%d seq=%d kind=%s reason=%s: %s',
          [Peer.HumanId, Sequence, CommandKindName(Command.Kind), RefusalReasonName(Message.Reason),
              E.Message]
      )
  );
  Payload := TBufEC.Create;
  try
    EncodeCommandResult(Message, Payload);
    FThread.Send(Peer.PeerId, nkCommandResult, Payload);
  finally
    Payload.Free;
  end;
end;

procedure TNetHost.CommandApplied(Peer: THostPeer; Sequence: Cardinal; const Command: TPlayerCommand);
var
  Message: TCommandResultMessage;
  Payload: TBufEC;
begin
  Message := Default(TCommandResultMessage);
  Message.Sequence := Sequence;
  Message.Kind := Command.Kind;
  Message.Ok := True;
  Payload := TBufEC.Create;
  try
    EncodeCommandResult(Message, Payload);
    FThread.Send(Peer.PeerId, nkCommandResult, Payload);
  finally
    Payload.Free;
  end;
end;

procedure TNetHost.RefuseHostOnlyCommand(
    Peer: THostPeer;
    Sequence: Cardinal;
    const Command: TPlayerCommand
);
var
  Refusal: ECommandRefused;
begin
  Refusal := ECommandRefused.CreateReason(
      rrOther,
      CommandKindName(Command.Kind) + ': only the host gives this command'
  );
  try
    CommandFailed(Peer, Sequence, Command, Refusal);
  finally
    Refusal.Free;
  end;
end;

procedure TNetHost.BeginDay;
begin
  FDayUnderWay := True;
  SendStatus(False);
end;

procedure HostStarDay(Star, Film: TObject; Recorded: Boolean);
var
  Host: TNetHost;
  Entry: TNetHostFilm;
  I, Count: Integer;
  Human: THuman;
  Raw: TBufEC;
begin
  Host := ActiveHost;
  if (Host = nil) or not Recorded then
    Exit;
  // Joins and disconnects wait for quiet points, so the peers do not change during the job.
  Entry := TNetHostFilm.Create;
  Count := 0;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human.PlayerStar = Star) and Human.Connected and (PeerOfHuman(Host.FPeers, Human.Id) <> nil) then
    begin
      SetLength(Entry.HumanIds, Count + 1);
      Entry.HumanIds[Count] := Human.Id;
      Inc(Count);
    end;
  end;
  if Count = 0 then
  begin
    Entry.Free;
    Exit;
  end;
  Entry.Day := Galaxy.CurrentTurn;
  Entry.StarId := TStar(Star).Id;
  Entry.Bytes := TBufEC.Create;
  // Compressed here, once, so that the pump only sends.
  Raw := TBufEC.Create;
  try
    TEFilm(Film).SaveToBuffer(Raw);
    Entry.RawSize := Raw.DataSize;
    CompressState(Raw, nil, Entry.Bytes);
  finally
    Raw.Free;
  end;
  Host.FFilmLock.Enter;
  try
    Host.FFilms.Add(Entry);
  finally
    Host.FFilmLock.Leave;
  end;
end;

procedure HostDayCompleted;
begin
  if ActiveHost <> nil then
    ActiveHost.FDayRan := True;
end;

// A command of the remote human in a talk, on the turn thread. The UI thread runs a local
// human's answer while the turn thread waits for it, and the command log records it in that
// wait; the turn thread runs the remote human's the same way, as not part of the job.
procedure SubmitTalkCommand(const Command: TPlayerCommand);
begin
  InTurnJob := False;
  RemoteTalkOpen := True;
  try
    SubmitCommand(Command);
  finally
    RemoteTalkOpen := False;
    InTurnJob := True;
  end;
end;

function TNetHost.RemoteTalk(Human: THuman): Boolean;
const
  PollMs = 5;
var
  Peer: THostPeer;
  Request: TTalkRequestMessage;
  Payload: TBufEC;
  Kind: TNetMessageKind;
  Command: TPlayerCommand;
  Sequence: Cardinal;
  Deadline: QWord;
  Commands: Integer;
  Outcome: AnsiString;
begin
  Result := False;
  // Joins and disconnects wait for quiet points, so the peers do not change during the job.
  Peer := PeerOfHuman(FPeers, Human.Id);
  if (Peer = nil) or Peer.Leaving or FThread.IsClosed(Peer.PeerId) then
    Exit;
  Request.HumanId := Human.Id;
  if Human.TalkShip <> nil then
    Request.ShipId := Human.TalkShip.Id
  else
    Request.ShipId := 0;
  if Human.TalkPlanet <> nil then
    Request.PlanetId := Human.TalkPlanet.Id
  else
    Request.PlanetId := 0;
  Request.Scripted := Human.TalkScripted;
  Request.TalkType := Human.TalkType;
  Request.Amount := Human.TalkAmount;
  Request.Text := Human.TalkText;
  Commands := 0;
  Outcome := '';
  Payload := TBufEC.Create;
  FTalkLock.Enter;
  Peer.InTalk := True;
  FTalking := True;
  FTalkLock.Leave;
  try
    // CHANGE: ENHANCEMENT - Every client's wait says whose answer the day waits for; the
    // status goes before the request, so the asked client has it too.
    FTalkHumanId := Human.Id;
    SendStatus(False);
    EncodeTalkRequest(Request, Payload);
    FThread.Send(Peer.PeerId, nkTalkRequest, Payload);
    NetLog(
        Format(
            'talk with human %d: ship %d, planet %d, kind %d',
            [Human.Id, Request.ShipId, Request.PlanetId, Request.TalkType]
        )
    );
    Deadline := GetTickCount64 + QWord(RemoteTalkTimeoutMs);
    repeat
      while (Outcome = '') and FThread.Receive(Peer.PeerId, Kind, Payload) do
        case Kind of
          nkCommand:
            begin
              Command := DecodeCommandMessage(Payload, Sequence);
              if Integer(Command.Actor) <> Peer.HumanId then
                NetLog(
                    Format(
                        'refused %s from human %d in a talk: it names human %d',
                        [CommandKindName(Command.Kind), Peer.HumanId, Command.Actor]
                    )
                )
              else if IsHostOnlyCommand(Command) then
                RefuseHostOnlyCommand(Peer, Sequence, Command)
              else if Command.Kind = ckEndTurn then
                // Not an answer: it waits for the next day with the rest of the queue.
                Peer.Deferred.Add(TNetMessage.Create(Kind, Payload.Data, Payload.DataSize))
              // CHANGE: ENHANCEMENT - The day has begun: refused.
              else if Command.Kind = ckCancelEndTurn then
                CancelEndTurn(Peer, Sequence, Command)
              else
              begin
                Inc(Commands);
                try
                  SubmitTalkCommand(Command);
                  // CHANGE: ENHANCEMENT - The client waits for a trade's answer.
                  if IsTradeCommand(Command.Kind) then
                    CommandApplied(Peer, Sequence, Command);
                except
                  on E: Exception do
                    CommandFailed(Peer, Sequence, Command, E);
                end;
              end;
            end;
          nkTalkDone:
            begin
              Result := True;
              Outcome := 'answered';
            end;
          nkBye:
            begin
              Peer.Deferred.Add(TNetMessage.Create(Kind, Payload.Data, Payload.DataSize));
              Outcome := 'left';
            end;
        else
          // Acknowledgements and chat: the pump takes them after the talk.
          Peer.Deferred.Add(TNetMessage.Create(Kind, Payload.Data, Payload.DataSize));
        end;
      if Outcome <> '' then
        Break;
      if FThread.IsClosed(Peer.PeerId) then
        Outcome := 'disconnected'
      else if FStopping or ExitScreenLoop then
        Outcome := 'the host stops'
      else if GetTickCount64 > Deadline then
        Outcome := 'no answer in time'
      else
        NetInboxEvent.WaitFor(PollMs);
    until Outcome <> '';
  finally
    FTalkHumanId := 0;
    SendStatus(False);
    FTalkLock.Enter;
    Peer.InTalk := False;
    FTalking := False;
    FTalkLock.Leave;
    Payload.Free;
  end;
  NetLog(
      Format(
          'talk with human %d ended: %s, %d commands, response %d',
          [Human.Id, Outcome, Commands, Human.TalkResponse]
      )
  );
end;

function HostRemoteTalk(Human: THuman): Boolean;
begin
  Result := (ActiveHost <> nil) and ActiveHost.RemoteTalk(Human);
end;

function TNetHost.SendFilms: Integer;
var
  Films: TList;
  I, J: Integer;
  Entry: TNetHostFilm;
  Payload: TBufEC;
  Header: TFilmHeader;
  Peer: THostPeer;
begin
  Result := 0;
  FDayRan := False;
  Films := TList.Create;
  Payload := TBufEC.Create;
  try
    FFilmLock.Enter;
    try
      Films.Assign(FFilms);
      FFilms.Clear;
    finally
      FFilmLock.Leave;
    end;
    for I := 0 to Films.Count - 1 do
    begin
      Entry := TNetHostFilm(Films[I]);
      Payload.Clear;
      Header.Day := Entry.Day;
      Header.StarId := Entry.StarId;
      EncodeFilmHeader(Header, Payload);
      Payload.AddBytes(Entry.Bytes.Data, Entry.Bytes.DataSize);
      Inc(Result, Entry.Bytes.DataSize);
      Inc(FSentFilmRawBytes, Entry.RawSize);
      // Encoded once; every client in the star gets the same bytes.
      for J := 0 to High(Entry.HumanIds) do
      begin
        Peer := PeerOfHuman(FPeers, Entry.HumanIds[J]);
        if (Peer <> nil) and not Peer.Leaving then
          FThread.Send(Peer.PeerId, nkFilm, Payload);
      end;
    end;
  finally
    for I := 0 to Films.Count - 1 do
      TObject(Films[I]).Free;
    Films.Free;
    Payload.Free;
  end;
end;

function TNetHost.TakeState: TNetState;
var
  Start: QWord;
begin
  Start := GetTickCount64;
  Inc(FSerial);
  // CHANGE: ENHANCEMENT - The hash is a second serialisation, for finding desyncs only.
  if StateHashes then
    Result := TNetState.Create(
        FSerial, Galaxy.CurrentTurn, GalaxyStateHashDumped(Format('host-state-%d', [FSerial]))
    )
  else
    Result := TNetState.Create(FSerial, Galaxy.CurrentTurn, 0);
  WriteGameCheckpoint(Result.Bytes);
  FLastTakeMs := Integer(GetTickCount64 - Start);
  FStates.Add(Result.AddRef);
  while FStates.Count > KeptStates do
  begin
    TNetState(FStates[0]).Release;
    FStates.Delete(0);
  end;
end;

function TNetHost.SendState(MeasureWhole: Boolean): TNetStateJob;
var
  State: TNetState;
  I: Integer;
  Peer: THostPeer;
begin
  State := TakeState;
  try
    Result := TNetStateJob.Create(State);
  finally
    State.Release;
  end;
  Result.MeasureWhole := MeasureWhole;
  for I := 0 to FPeers.Count - 1 do
  begin
    Peer := THostPeer(FPeers[I]);
    if (Peer.State = hpJoined) and not Peer.Leaving then
      Result.AddTarget(Peer.PeerId, Peer.Base);
  end;
  FThread.QueueStateJob(Result);
  FDayUnderWay := False;
  SendStatus(False);
end;

function TNetHost.AllAcked(Serial: Integer): Boolean;
var
  I: Integer;
  Peer: THostPeer;
begin
  for I := 0 to FPeers.Count - 1 do
  begin
    Peer := THostPeer(FPeers[I]);
    if (Peer.State = hpJoined) and not Peer.Leaving and (Peer.AckedSerial < Serial) then
      Exit(False);
  end;
  Result := True;
end;

procedure TNetHost.DisconnectHumans;
var
  I: Integer;
  Human: THuman;
  Peer: THostPeer;
begin
  I := 0;
  while I < Session.Humans.Count do
  begin
    Human := Session.Humans[I];
    Inc(I);
    Peer := PeerOfHuman(FPeers, Human.Id);
    if Peer = nil then
      Continue;
    SetLength(Peer.Queue, 0);
    DisconnectHuman(Human, Peer);
  end;
end;

function TNetHost.FreezePeers: TPeerIds;
var
  I: Integer;
begin
  SetLength(Result, FPeers.Count);
  for I := 0 to FPeers.Count - 1 do
  begin
    Result[I] := THostPeer(FPeers[I]).PeerId;
    FThread.FreezePeer(Result[I]);
  end;
end;

procedure TNetHost.Shutdown(TimeoutMs: Integer);
var
  I: Integer;
  Peer: THostPeer;
  Deadline: QWord;
begin
  // A remote dialogue the turn thread waits for ends first: it reads the network thread.
  FStopping := True;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while FTalking and (GetTickCount64 < Deadline) do
    Sleep(5);
  for I := 0 to FPeers.Count - 1 do
  begin
    Peer := THostPeer(FPeers[I]);
    FThread.Send(Peer.PeerId, nkBye, nil, 0);
    FThread.ClosePeer(Peer.PeerId);
  end;
  FThread.WaitIdle(TimeoutMs);
end;

end.
