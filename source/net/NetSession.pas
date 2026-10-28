{$EXCESSPRECISION OFF}
unit NetSession;

// CHANGE: ENHANCEMENT - What the rest of the game calls for multiplayer (ROADMAP.md, Phase 5;
// docs/network.md): whether this machine hosts or joins, the pump, and the game-layer hooks
// the session sets. Without a session every hook stays nil and the game is as before.
interface
uses
  NetHost,
  NetClient,
  QuestPage;
type
  TNetRole = (nrNone, nrHost, nrClient);

function NetRole: TNetRole;
function CurrentHost: TNetHost;
function CurrentClient: TNetClient;
// Hosts the running game on Port (0 picks a free one; CurrentHost.Thread.ListenPort says
// which). Sets the host's hooks: the film of each star after its day, the day's end, and the
// dialogues the day asks a remote human (aHuman.RemoteTalkHook).
function StartHosting(Port: Integer; const HostName: WideString): TNetHost;
// Joins the game at Address:Port as Name. Sets the client's hooks: every command the local
// human submits goes to the host. CurrentClient.Connected is False when it could not connect.
// CHANGE: ENHANCEMENT - Without Wait the connect runs on a thread of its own, and the pump
// finishes it (TNetClient.JoinPhase), so that a join can show its progress and be cancelled.
function JoinGame(
    const Address: AnsiString;
    Port: Integer;
    const Name: WideString;
    Wait: Boolean = True
): TNetClient;
// Leaves the session (Bye to the peers), clears the hooks and frees the host or client.
procedure StopNetwork;
// Takes what arrived. The UI calls it every frame and at safe points; the headless runner
// while it waits.
procedure NetPump;
// CHANGE: ENHANCEMENT - The latest text-quest page of each human, as this machine has it (the
// host's or the client's TQuestPageStore): for the watch window (docs/progress/
// 2026-10-19-text-quests-plan.md, Watching). nil without a session.
function QuestPages: TQuestPageStore;
implementation
uses
  aCommands,
  aHuman,
  ThreadCalc;

var
  Host: TNetHost;
  Client: TNetClient;

function NetRole: TNetRole;
begin
  if Host <> nil then
    Result := nrHost
  else if Client <> nil then
    Result := nrClient
  else
    Result := nrNone;
end;

function CurrentHost: TNetHost;
begin
  Result := Host;
end;

function CurrentClient: TNetClient;
begin
  Result := Client;
end;

// QuestPageHook of a session: the local human's page goes to the host's clients, or to the host.
procedure SessionQuestPage(const Page: TWatchedQuestPage);
begin
  if Host <> nil then
    Host.PublishQuestPage(Page)
  else if Client <> nil then
    Client.SendQuestPage(Page);
end;

function QuestPages: TQuestPageStore;
begin
  if Host <> nil then
    Result := Host.QuestPages
  else if Client <> nil then
    Result := Client.QuestPages
  else
    Result := nil;
end;

function StartHosting(Port: Integer; const HostName: WideString): TNetHost;
begin
  StopNetwork;
  Host := TNetHost.Create(Port, HostName);
  StarDayHook := @HostStarDay;
  DayCompletedHook := @HostDayCompleted;
  RemoteTalkHook := @HostRemoteTalk;
  // CHANGE: ENHANCEMENT - A client's black hole battle holds the day (docs/network.md).
  RemoteArcadeHook := @HostRemoteArcade;
  // CHANGE: ENHANCEMENT - The host relays the trades it applies (docs/network.md, Trades).
  NetworkCommandHook := @HostCommandSubmitted;
  // CHANGE: ENHANCEMENT - Its own human's text-quest pages go to the clients.
  QuestPageHook := @SessionQuestPage;
  Result := Host;
end;

function JoinGame(
    const Address: AnsiString;
    Port: Integer;
    const Name: WideString;
    Wait: Boolean
): TNetClient;
begin
  StopNetwork;
  Client := TNetClient.Create(Address, Port, Name, Wait);
  NetworkCommandHook := @ClientCommandSubmitted;
  // CHANGE: ENHANCEMENT - A trade waits for the host's answer instead of being predicted.
  TradeSubmitHook := @ClientTradeSubmitted;
  // CHANGE: ENHANCEMENT - Its human's text-quest pages go to the host.
  QuestPageHook := @SessionQuestPage;
  Result := Client;
end;

procedure StopNetwork;
const
  ByeTimeoutMs = 5000;
begin
  StarDayHook := nil;
  DayCompletedHook := nil;
  RemoteTalkHook := nil;
  RemoteArcadeHook := nil;
  NetworkCommandHook := nil;
  TradeSubmitHook := nil;
  QuestPageHook := nil;
  if Host <> nil then
  begin
    Host.Shutdown(ByeTimeoutMs);
    Host.Free;
    Host := nil;
  end;
  if Client <> nil then
  begin
    if Client.Connected then
      Client.Leave(ByeTimeoutMs);
    Client.Free;
    Client := nil;
  end;
end;

procedure NetPump;
begin
  if Host <> nil then
    Host.Pump
  else if Client <> nil then
    Client.Pump;
end;

end.
