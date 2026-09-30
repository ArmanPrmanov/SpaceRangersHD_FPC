{$EXCESSPRECISION OFF}
unit NetHost;

// CHANGE: ENHANCEMENT - The host of a networked game (ROADMAP.md, Phase 5; docs/network.md).
// Only the host runs the day. It takes joins and disconnects at quiet points, queues each
// peer's commands and applies the queues in Session.Humans order once every peer is ready,
// sends the film of each star to the clients in it, and after the day a state to every
// client, as a delta against the state that client acknowledged. Everything here runs on the
// UI thread, except StarDay and RemoteTalk, which the turn thread calls.
interface
uses
  Classes,
  SyncObjs,
  EC_Buf,
  aCommands,
  aHuman,
  NetTransport,
  NetThread,
  NetProtocol;
type
  THostPeerState = (hpHello, hpPendingJoin, hpJoined);

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
    Queue: array of TPlayerCommand;
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
    destructor Destroy; override;
    function EndTurnIndex: Integer;
    // CHANGE: ENHANCEMENT - The index of the first StopContinuing in the queue; -1 when none.
    function StopIndex: Integer;
  end;

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
    function FindPeer(PeerId: Integer): THostPeer;
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
  public
    // Joins wait while this is set; the headless host sets it until every client is there,
    // so that the humans join in the same order every run (by name).
    HoldJoins: Boolean;
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
    // The day starts: no join or disconnect until the state after it is sent.
    procedure BeginDay;
    // Sends the films the player-star job encoded to the clients in their stars; returns the
    // bytes of the distinct films.
    function SendFilms: Integer;
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
implementation
uses
  SysUtils,
  aEFilm,
  aGalaxy,
  aObjectRefs,
  aPlanet,
  aPlayerActions,
  aSession,
  aSaveLoad,
  GR_Main,
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
    Bytes: TBufEC;
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
    if Queue[I].Kind = ckStopContinuing then
      Exit(I);
  Result := -1;
end;

function THostPeer.EndTurnIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(Queue) do
    if Queue[I].Kind = ckEndTurn then
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
  Chat: TChatMessage;
  Serial, I: Integer;
  Other: THostPeer;
  Character: TCharacterMessage;
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
        Command := DecodeCommandMessage(Payload);
        if Integer(Command.Actor) <> Peer.HumanId then
          NetLog(
              Format(
                  'refused %s from human %d: it names human %d',
                  [CommandKindName(Command.Kind), Peer.HumanId, Command.Actor]
              )
          )
        else
        begin
          I := Length(Peer.Queue);
          SetLength(Peer.Queue, I + 1);
          Peer.Queue[I] := Command;
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
    nkBye:
      Peer.Leaving := True;
  end;
end;

procedure TNetHost.Pump;
var
  Id, I: Integer;
  Peer: THostPeer;
  Kind: TNetMessageKind;
  Payload: TBufEC;
begin
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
      if FThread.IsClosed(Peer.PeerId) then
        Peer.Leaving := True;
    end;
  finally
    Payload.Free;
  end;
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
begin
  Peer.State := hpHello;
  Human.Connected := False;
  NetLog(Format('human %d (%s) disconnected', [Human.Id, UTF8Encode(Peer.Hello.Name)]));
  if (Human.Player <> nil) and not Human.Player.InHyperspace and not Human.Finished then
  begin
    Command := NewCommand(ckHoldPosition);
    Command.Actor := Cardinal(Human.Id);
    SubmitCommand(Command);
  end;
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
      Human.Connected := True;
      Peer.State := hpJoined;
      Peer.HumanId := Human.Id;
      Peer.AckedSerial := 0;
      SetLength(Peer.Queue, 0);
      Payload.Clear;
      Welcome.HumanId := Human.Id;
      Welcome.HostName := FName;
      EncodeWelcome(Welcome, Payload);
      FThread.Send(Peer.PeerId, nkWelcome, Payload);
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
    Status.Humans[I].HoldsDay := HumanHoldsDay(Human);
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
    if LagsBehind(Peer, Human) then
      Exit(False);
  end;
  Result := True;
end;

function TNetHost.WaitingFor: AnsiString;
var
  I: Integer;
  Human: THuman;
  Peer: THostPeer;
begin
  Result := '';
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Peer := PeerOfHuman(FPeers, Human.Id);
    if not HumanHoldsDay(Human) then
    begin
      if (Peer = nil) or not LagsBehind(Peer, Human) then
        Continue;
    end
    else if (Peer <> nil) and (Peer.EndTurnIndex >= 0) then
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
        SubmitCommand(Peer.Queue[J]);
      except
        on E: Exception do
          NetLog(
              Format(
                  '%s of human %d failed: %s',
                  [CommandKindName(Peer.Queue[J].Kind), Peer.HumanId, E.Message]
              )
          );
      end;
    if Last >= 0 then
      Delete(Peer.Queue, 0, Last + 1);
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
  TEFilm(Film).SaveToBuffer(Entry.Bytes);
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
              Command := DecodeCommandMessage(Payload);
              if Integer(Command.Actor) <> Peer.HumanId then
                NetLog(
                    Format(
                        'refused %s from human %d in a talk: it names human %d',
                        [CommandKindName(Command.Kind), Peer.HumanId, Command.Actor]
                    )
                )
              else if Command.Kind = ckEndTurn then
                // Not an answer: it waits for the next day with the rest of the queue.
                Peer.Deferred.Add(TNetMessage.Create(Kind, Payload.Data, Payload.DataSize))
              else
              begin
                Inc(Commands);
                try
                  SubmitTalkCommand(Command);
                except
                  on E: Exception do
                    NetLog(
                        Format(
                            '%s of human %d in a talk failed: %s',
                            [CommandKindName(Command.Kind), Peer.HumanId, E.Message]
                        )
                    );
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
