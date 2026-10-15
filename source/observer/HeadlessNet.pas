{$EXCESSPRECISION OFF}
unit HeadlessNet;

// CHANGE: ENHANCEMENT - Networked play without a window, for tests (ROADMAP.md, Phase 5;
// docs/network.md, Tests). A host process loads a save, waits for its clients, and runs the
// days: its own human plays its turn, it waits for every client's end turn while pumping,
// applies their commands, runs the player-star job, sends the films, runs the galaxy job and
// sends the state. A client process joins, and each day plays the turn --sim-hotseat plays
// for its human, sends it, and waits for the film and the state. Both print one line per day
// with the state hash, the sizes and the load time. A client answers the dialogues the host's
// day asks its human with the talk screen's first answer.
// CHANGE: ENHANCEMENT - The LAN-session checks (docs/network.md, Tests): a client joins with
// the connect on its own thread and prints each phase of its join, can cancel it, plays each
// film of its star for a while and keeps a dialogue that comes meanwhile for the film's end;
// the host can send the films before its probe asks, and can stop hosting.
// CHANGE: ENHANCEMENT - A refused command (--sim-net-buy-race): the host buys the goods a
// client's queued purchase wants first, the purchase is refused, and the client shows why.
// CHANGE: ENHANCEMENT - Trades apply on the host as they arrive (docs/network.md, Trades): the
// host applies them while it waits for its peers, a human's only once every human before it
// is ready, so that its days are the same however the commands arrived. --sim-net-shop: the
// clients join at the host's human's planet and trade there on their first day.
interface
uses
  HeadlessSim;
function RunNetHost(const Options: TSimulationOptions): Integer;
function RunNetClient(const Options: TSimulationOptions): Integer;
// CHANGE: ENHANCEMENT - --sim-net-talk=DAY (docs/network.md, Tests): from the FromDay-th day
// the player-star job runs (counting from 1, so a host and the replay of its log agree), right
// after the day of the first filmed star that holds remote humans who can be asked (in normal
// space, not on automatic control), the first ship of that star that is no human's asks each
// of them a truce offer (TShip.ShowPlayerDialogue), once in the run. An answer that agrees
// gives the human 1 credit, so the state shows it. It prints one line per human asked. The
// host installs it after it starts hosting; a replay of the host's log installs it too, and
// asks the same.
procedure InstallNetTalkProbe(FromDay: Integer);
procedure RemoveNetTalkProbe;
implementation
uses
  SysUtils,
  EC_Buf,
  Globals,
  aCommands,
  aShopActions,
  aShopStock,
  aItem,
  aPlanet,
  SimEvents,
  GlobalsV,
  aEFilm,
  aGalaxy,
  aHuman,
  aObjectRefs,
  aPlayer,
  aPlayerActions,
  aSession,
  aShip,
  aGalaxyStruct,
  aTalkActions,
  ThreadCalc,
  WorkerErrors,
  NetThread,
  NetProtocol,
  NetHost,
  NetClient,
  NetSession;

const
  // Without progress for this long, a run fails instead of hanging the test.
  StallTimeoutMs = 120000;

procedure EmitNetEvent(const Text: AnsiString);
begin
  Emit('net ' + Text);
end;

function HashText(Value: QWord): AnsiString;
begin
  Result := IntToHex(Value, 16);
end;

function AwayCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Session.Humans.Count - 1 do
    if not Session.Humans[I].Connected then
      Inc(Result);
end;

var
  ProbeFromDay: Integer;
  // The days the player-star job has run since the probe was installed, and the last one.
  ProbeDays: Integer;
  ProbeLastTurn: Integer;
  ProbeDone: Boolean;
  ProbePrevious: TStarDayHook;
  // CHANGE: ENHANCEMENT - --sim-net-talk-after-film: the films of the day so far go before the
  // probe asks, so a client plays its film when the talk comes. The bytes they had, for the
  // host's day line.
  ProbeSendsFilms: Boolean;
  ProbeFilmBytes: Integer;

// StarDayHook of the probe, on the turn thread (InstallNetTalkProbe).
procedure NetTalkProbe(Star, Film: TObject; Recorded: Boolean);
var
  I, J: Integer;
  Human: THuman;
  Ship, Other: TShip;
  Response: Byte;
  Asked: Boolean;
begin
  if Assigned(ProbePrevious) then
    ProbePrevious(Star, Film, Recorded);
  if Galaxy.CurrentTurn <> ProbeLastTurn then
  begin
    ProbeLastTurn := Galaxy.CurrentTurn;
    Inc(ProbeDays);
  end;
  if ProbeDone or (ProbeDays < ProbeFromDay) then
    Exit;
  Asked := False;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human = LocalHuman)
        or (Human.Player = nil)
        or (Human.PlayerStar <> Star)
        or (Human.Player.CurrentStar <> Star)
        or not Human.Player.InNormalSpace
        or Human.PlayerAutomaticControl
        or not CanAskHuman(Human) then
      Continue;
    Ship := nil;
    for J := 0 to TStar(Star).Ships.Count - 1 do
    begin
      Other := TShip(TStar(Star).Ships[J]);
      if not IsHuman(Other) and Other.InNormalSpace then
      begin
        Ship := Other;
        Break;
      end;
    end;
    if Ship = nil then
      Continue;
    // The films go from the turn thread; the headless host does not pump while the job runs.
    if ProbeSendsFilms and not Asked and (ActiveHost <> nil) then
      Inc(ProbeFilmBytes, ActiveHost.SendFilms);
    Response :=
        Ship.ShowPlayerDialogue(
            Human.Player,
            tkTruceOffer,
            Ship.LookupTalkText('Talk.Truce.' + Ship.GetTypeNameKey + 'Send'),
            0
        );
    if Response <> 0 then
      Human.Player.SetMoney(Human.Player.Money + 1);
    Emit(
        Format(
            'net talk day=%d human=%d ship=%d response=%d',
            [Galaxy.CurrentTurn, Human.Id, Ship.Id, Response]
        )
    );
    Asked := True;
  end;
  if Asked then
    ProbeDone := True;
end;

procedure InstallNetTalkProbe(FromDay: Integer);
begin
  RemoveNetTalkProbe;
  ProbeFromDay := FromDay;
  ProbeDays := 0;
  ProbeLastTurn := -1;
  ProbeDone := False;
  ProbePrevious := StarDayHook;
  StarDayHook := @NetTalkProbe;
end;

procedure RemoveNetTalkProbe;
begin
  if @StarDayHook = @NetTalkProbe then
    StarDayHook := ProbePrevious;
  ProbePrevious := nil;
end;

var
  // --sim-net-buy-race: the host has bought first; the purchases of remote humans the host
  // applied (the command log records exactly these); the hook the count chains.
  RaceDone: Boolean;
  RemoteTrades: Integer;
  PreviousAfterCommand: TCommandHook;
  // CHANGE: ENHANCEMENT - The host applies trades as they arrive only while it waits for its
  // peers (RunNetHost). The race (--sim-net-buy-race) and the shop run (--sim-net-shop) are on;
  // the host's own purchase of what a client bought has been tried; the shop screen's
  // notifications (SimEvents.NotifyShopStockChanged) counted.
  TradeWindow: Boolean;
  RaceArmed: Boolean;
  ShopRun: Boolean;
  HostTriedFirst: Boolean;
  ShopNotifications: Integer;
  PreviousShopHandler: TSimEventHandler;

procedure CountRemoteTrade(const Command: TPlayerCommand);
begin
  if Assigned(PreviousAfterCommand) then
    PreviousAfterCommand(Command);
  if (Command.Kind = ckTradeGoods) and (LocalHuman <> nil) and (Integer(Command.Actor) <> LocalHuman.Id) then
    Inc(RemoteTrades);
end;

// CHANGE: ENHANCEMENT - Right before the host applies a remote human's purchase of goods as it
// arrives (the human landed), once in the run: the host buys as much of that good in the
// human's name as leaves too little for it, when the human can pay for that. The purchase is
// then refused at once, while the client waits for it.
procedure BuyFirst(HumanId: Integer; const Queued: TQueuedCommand);
var
  Wanted, Stock, Count: Integer;
  Human: THuman;
  Good: Byte;
  Command: TPlayerCommand;
begin
  Human := FindHuman(HumanId);
  Command := Queued.Command;
  if (Human = nil) or (Human.Player = nil) or (Human.Player.CurrentPlanet = nil)
      or (Command.Kind <> ckTradeGoods) or (Length(Command.Ints) < 3) or (Command.Ints[2] <> 0) then
    Exit;
  Good := Command.Ints[0];
  Wanted := Command.Ints[1];
  Stock := Human.Player.GetLocationGoodsEntry(Good).Count;
  Count := Stock - Wanted + 1;
  if (Count < 1)
      or (Int64(Count) * Human.Player.ShopGoodsPurchasePrice(Good, nil) > Human.Player.Money) then
    Exit;
  Command := NewCommand(ckTradeGoods);
  Command.Actor := Cardinal(Human.Id);
  AddRef(Command, nil);
  AddInt(Command, Good);
  AddInt(Command, Count);
  AddInt(Command, 0);
  SubmitCommand(Command);
  Emit(
      Format(
          'net host buys first human=%d good=%d count=%d stock=%d seq=%d',
          [Human.Id, Good, Count, Stock, Queued.Sequence]
      )
  );
  RaceDone := True;
end;

// --sim-net-shop: a client bought an item; the host's own human, whose grid still showed it
// when the screen sent the purchase, buys it too, as its shop screen would (SubmitTrade). The
// host's grid no longer shows it, and the purchase is refused.
procedure HostBuysSame(const Queued: TQueuedCommand);
var
  Command: TPlayerCommand;
  I, Shown: Integer;
begin
  HostTriedFirst := True;
  Command := NewCommand(ckBuyEquipment);
  AddInt(Command, Queued.Command.Ints[0]);
  AddInt(Command, Queued.Command.Ints[1]);
  try
    SubmitTrade(Command);
    Emit('net host own trade applied kind=BuyEquipment');
  except
    on E: ECommandRefused do
      Emit(Format('net host own trade refused kind=BuyEquipment reason=%s', [RefusalReasonName(E.Reason)]));
  end;
  Shown := 0;
  if LocalHuman.TemporaryShopSlots <> nil then
    for I := 0 to LocalHuman.TemporaryShopSlots.Count - 1 do
      if (TShopStockSlot(LocalHuman.TemporaryShopSlots[I]).Item <> nil)
          and (TShopStockSlot(LocalHuman.TemporaryShopSlots[I]).Item.Id = Queued.Command.Ints[1]) then
        Shown := 1;
  Emit(Format('net host shop grid shows=%d notified=%d', [Shown, ShopNotifications]));
end;

// TNetHost.TradeHook of the headless host.
procedure HostTradeHook(
    Host: TNetHost;
    HumanId: Integer;
    const Queued: TQueuedCommand;
    Done, Applied: Boolean
);
begin
  if not Done and RaceArmed and not RaceDone then
    BuyFirst(HumanId, Queued);
  if Done and Applied and ShopRun and not HostTriedFirst and (Queued.Command.Kind = ckBuyEquipment) then
    HostBuysSame(Queued);
end;

function HeadlessMayApplyTrades: Boolean;
begin
  Result := TradeWindow;
end;

procedure CountShopNotification;
begin
  Inc(ShopNotifications);
end;

// --sim-net-shop: the clients join at the host's human's planet, with money and room.
function ShopJoinPlanet(Race: Integer): TObject;
begin
  Result := LocalPlayer.CurrentPlanet;
  if Result = nil then
    Result := FindJoinPlanet(Race);
end;

// --sim-net-shop: the host's human is landed at an inhabited planet of its star with a shop;
// a new game's is docked at a station, which sells no goods, so it is moved to the planet, as
// the game docks a ship it creates (TGalaxy, TPlanet) the other way round. A test's state:
// the clients get it with their join.
function LandHostForShop: Boolean;
var
  I: Integer;
  P: TPlayer;
  Planet, Candidate: TPlanet;
begin
  P := LocalPlayer;
  Planet := P.CurrentPlanet;
  if (Planet = nil) and (P.CurrentStar <> nil) then
    for I := 0 to P.CurrentStar.Planets.Count - 1 do
    begin
      Candidate := TPlanet(P.CurrentStar.Planets[I]);
      if (Planet = nil) and (Candidate.OwnerId <= Byte(oiGaal)) and (Candidate.EquipmentShop.Count >= 4) then
        Planet := Candidate;
    end;
  Result := Planet <> nil;
  if not Result then
    Exit;
  if P.CurrentPlanet = nil then
  begin
    RestoreTemporaryShopStock(LocalHuman);
    P.DockedTo := nil;
    P.CurrentPlanet := Planet;
    P.Position := Planet.GetPosition;
  end;
  Emit(Format('net host shop planet=%d', [Planet.Id]));
end;

procedure ShopJoined(Human: THuman);
begin
  Human.Player.SetMoney(10000000);
  Inc(Human.Player.GetHull.Weight, 1000);
  Human.Player.RefreshDerivedStats(True);
  // A load computes them again from the rangers' money; so must the host for its own copy.
  Galaxy.RefreshRangerWealthStats;
end;

procedure OpenShopFor(Human: THuman);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOpenShopStock);
  AddInt(Command, ShopVisibleColumnCount);
  Command.Actor := Cardinal(Human.Id);
  SubmitCommand(Command);
end;

procedure EndTurnFor(Human: THuman);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckEndTurn);
  AddInt(Command, 0);
  Command.Actor := Cardinal(Human.Id);
  SubmitCommand(Command);
end;

procedure TradeGoodsFor(Human: THuman; Good: Byte; Count: Integer; Sell: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTradeGoods);
  AddRef(Command, nil);
  AddInt(Command, Good);
  AddInt(Command, Count);
  AddInt(Command, Ord(Sell));
  Command.Actor := Cardinal(Human.Id);
  SubmitCommand(Command);
end;

// The first two items of the planet's shop, in its order, that the shop takes back.
function PickShopItems(Planet: TPlanet; out X, Y: TItem): Boolean;
var
  I: Integer;
  Item: TItem;
begin
  X := nil;
  Y := nil;
  for I := 0 to Planet.EquipmentShop.Count - 1 do
  begin
    Item := TItem(Planet.EquipmentShop[I]);
    if not IsTradedBack(Item) then
      Continue;
    if X = nil then
      X := Item
    else
    begin
      Y := Item;
      Exit(True);
    end;
  end;
  Result := False;
end;

// The first good the planet sells.
function PickGood(P: TPlayer): Integer;
var
  Good: Byte;
begin
  for Good := 0 to 7 do
    if P.GetLocationGoodsEntry(Good).Count >= 2 then
      Exit(Good);
  Result := -1;
end;

function GridShowsItem(Human: THuman; Id: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Human.TemporaryShopSlots <> nil then
    for I := 0 to Human.TemporaryShopSlots.Count - 1 do
      if (TShopStockSlot(Human.TemporaryShopSlots[I]).Item <> nil)
          and (TShopStockSlot(Human.TemporaryShopSlots[I]).Item.Id = Id) then
        Exit(True);
end;

// --sim-net-shop, a client's first day. Net1 buys the item X, buys a good and sells it back,
// buys the item Y and sells it back from the ship screen (three hold commands before the sale),
// and ends its turn. Net2 waits until the host's relays of Net1's trades have run here, one at a
// time: its grid no longer shows X, and the planet's stock of the good went down and up again;
// then it buys X, which the host refuses at once (item-gone), ends its turn, and right after
// sends a purchase of the good without waiting for it, which the host applies after the day.
function PlayShopTurn(Client: TNetClient; const Name: AnsiString): Boolean;
var
  H: THuman;
  P: TPlayer;
  Planet: TPlanet;
  X, Y: TItem;
  XId, Good, Before, Low, Count, Slot: Integer;
  Reason: AnsiString;
  Deadline: QWord;
  Command: TPlayerCommand;
begin
  Result := False;
  H := LocalHuman;
  P := H.Player;
  Planet := P.CurrentPlanet;
  if Planet = nil then
  begin
    Emit('net client shop failed: not landed');
    Exit;
  end;
  OpenShopFor(H);
  Good := PickGood(P);
  if not PickShopItems(Planet, X, Y) or (Good < 0) then
  begin
    Emit('net client shop failed: nothing to trade');
    Exit;
  end;
  XId := X.Id;
  if Name = 'Net1' then
  begin
    Reason := BuyShopItem(H, ShopSlotIndexOf(H, X), X);
    Emit(Format('net client shop bought item=%d reason=%s', [XId, Reason]));
    TradeGoodsFor(H, Good, 1, False);
    TradeGoodsFor(H, Good, 1, True);
    Emit(Format('net client shop traded good=%d', [Good]));
    Reason := BuyShopItem(H, ShopSlotIndexOf(H, Y), Y);
    SellToShop(H, Y);
    Emit(Format('net client shop sold item=%d bought=%s', [Y.Id, Reason]));
    EndTurnFor(H);
    Exit(Reason = '');
  end;
  Before := P.GetLocationGoodsEntry(Good).Count;
  Low := Before;
  Count := Before;
  Slot := ShopSlotIndexOf(H, X);
  Deadline := GetTickCount64 + StallTimeoutMs;
  repeat
    Client.Pump;
    if Client.ApplyRelayed(1) > 0 then
    begin
      Count := P.GetLocationGoodsEntry(Good).Count;
      if Count < Low then
        Low := Count;
    end
    else
      NetInboxEvent.WaitFor(5);
    if (FindShopStockItem(Planet, XId) = nil) and (Low < Before) and (Count = Before) then
      Break;
    if GetTickCount64 > Deadline then
    begin
      Emit('net client shop failed: the relays did not come');
      Exit;
    end;
  until False;
  Emit(
      Format(
          'net client shop relay grid-shows-x=%d goods-before=%d low=%d after=%d',
          [Ord(GridShowsItem(H, XId)), Before, Low, Count]
      )
  );
  Reason := BuyShopItem(H, Slot, X);
  Emit(Format('net client shop buy-gone reason=%s', [Reason]));
  EndTurnFor(H);
  Command := NewCommand(ckTradeGoods);
  AddRef(Command, nil);
  AddInt(Command, Good);
  AddInt(Command, 1);
  AddInt(Command, 0);
  Client.SendCommand(Command);
  Emit(Format('net client shop sent after end turn seq=%d', [Client.LastCommandSequence]));
  Result := Reason = RefusalReasonName(rrItemGone);
end;

// CHANGE: ENHANCEMENT - --sim-net-nested (docs/network.md, Tests): on its first day a client
// submits a command whose executor submits another one. A client sends only the outer one, and
// the host's run of it submits the inner one again, so the host runs each once.
const
  ckNetNestedOuter = 1001;
  ckNetNestedInner = 1002;
var
  NestedRegistered: Boolean;
  NestedOuterRuns: Integer;
  NestedInnerRuns: Integer;

procedure ExecuteNetNestedOuter(const Command: TPlayerCommand);
begin
  Inc(NestedOuterRuns);
  SubmitCommand(NewCommand(ckNetNestedInner));
end;

procedure ExecuteNetNestedInner(const Command: TPlayerCommand);
begin
  Inc(NestedInnerRuns);
end;

procedure RegisterNestedProbe;
begin
  NestedOuterRuns := 0;
  NestedInnerRuns := 0;
  if NestedRegistered then
    Exit;
  RegisterCommand(ckNetNestedOuter, 'NetNestedOuter', @ExecuteNetNestedOuter);
  RegisterCommand(ckNetNestedInner, 'NetNestedInner', @ExecuteNetNestedInner);
  NestedRegistered := True;
end;

function RunNetHost(const Options: TSimulationOptions): Integer;
var
  Host: TNetHost;
  Deadline: QWord;
  Day: Integer;
  Plan: AnsiString;
  Job: TNetStateJob;
  FilmBytes, StateBytes, Away: Integer;
  FilmRawStart: Int64;
begin
  Result := 0;
  LoadSave(Options.SavePath, Options.Seed);
  Emit(Format('sim save=%s seed=%d day=%d', [Options.SavePath, Options.Seed, Galaxy.CurrentTurn]));
  // The tests compare every state's hash with the host's, in release builds too.
  StateHashes := True;
  NetLogHook := @EmitNetEvent;
  try
    Host := StartHosting(Options.NetHostPort, 'Host');
    if Options.NetTalkDay > 0 then
      InstallNetTalkProbe(Options.NetTalkDay);
    ProbeSendsFilms := Options.NetTalkAfterFilm;
    RaceDone := False;
    RemoteTrades := 0;
    if Options.NetNested then
      RegisterNestedProbe;
    if Options.NetBuyRace then
    begin
      PreviousAfterCommand := AfterCommandHook;
      AfterCommandHook := @CountRemoteTrade;
    end;
    Host.OrderedTrades := True;
    Host.MayApplyTrades := @HeadlessMayApplyTrades;
    Host.TradeHook := @HostTradeHook;
    RaceArmed := Options.NetBuyRace;
    ShopRun := Options.NetShop;
    HostTriedFirst := False;
    ShopNotifications := 0;
    if Options.NetShop then
    begin
      if not LandHostForShop then
      begin
        Emit('net host failed: no planet to trade at');
        Exit(1);
      end;
      Host.JoinPlanetHook := @ShopJoinPlanet;
      Host.JoinedHook := @ShopJoined;
      PreviousShopHandler := ShopStockChangedHandler;
      ShopStockChangedHandler := @CountShopNotification;
    end;
    Emit(Format('net host port=%d clients=%d', [Host.Thread.ListenPort, Options.NetClients]));
    // Every client first, then the joins by name, so that the humans are the same each run.
    Host.HoldJoins := True;
    Deadline := GetTickCount64 + StallTimeoutMs;
    // A first join sends its character before it can be taken (TNetHost.AskCharacters).
    while Host.ReadyJoinCount < Options.NetClients do
    begin
      if GetTickCount64 > Deadline then
      begin
        Emit(Format('net host failed: %d of %d clients came', [Host.PendingJoinCount, Options.NetClients]));
        Exit(1);
      end;
      Host.Pump;
      NetInboxEvent.WaitFor(5);
    end;
    Host.HoldJoins := False;
    Host.Pump;
    CurrentScreenId := screenPlanet;
    RequestedScreenId := screenNone;
    for Day := 1 to Options.Turns do
    begin
      Plan := '';
      if not HumanHoldsDay(LocalHuman) then
        Plan := '.'
      // --sim-net-shop: the host's human opens the shop on the first day and stays.
      else if Options.NetShop and (Day = 1) then
      begin
        OpenShopFor(LocalHuman);
        EndTurnFor(LocalHuman);
        Plan := 'o';
      end
      else
        PlayHumanTurn(LocalHuman, Galaxy.CurrentTurn, 1, Plan);
      Deadline := GetTickCount64 + StallTimeoutMs;
      // The peers' trades apply as they arrive while the host waits for them.
      TradeWindow := True;
      try
        repeat
          Host.Pump;
          if Host.PeersReady then
            Break;
          if GetTickCount64 > Deadline then
          begin
            Emit(Format('net host failed: day %d waits for humans %s', [Day, Host.WaitingFor]));
            Exit(1);
          end;
          NetInboxEvent.WaitFor(5);
        until False;
      finally
        TradeWindow := False;
      end;
      Host.ApplyQueues;
      if not AllHumansEndedTurn then
      begin
        Emit(Format('net host failed: day %d cannot start after every peer was ready', [Day]));
        Exit(1);
      end;
      Host.BeginDay;
      ProbeFilmBytes := 0;
      FilmRawStart := Host.SentFilmRawBytes;
      StartPlayerStarTurnCalculation;
      WaitForTurnCalculation;
      RaisePendingWorkerError;
      FilmBytes := ProbeFilmBytes + Host.SendFilms;
      if (LocalPlayer <> nil) and not LocalPlayer.InHyperspace then
      begin
        StartGalaxyTurnCalculation;
        WaitForTurnCalculation;
        RaisePendingWorkerError;
      end;
      Job := Host.SendState(True);
      try
        StateBytes := Job.State.Bytes.DataSize;
        Deadline := GetTickCount64 + StallTimeoutMs;
        while not Job.Done do
        begin
          if GetTickCount64 > Deadline then
          begin
            Emit('net host failed: the state was not compressed');
            Exit(1);
          end;
          Host.Pump;
          NetInboxEvent.WaitFor(2);
        end;
        Emit(
            Format(
                'net host day=%d serial=%d hash=%s state=%d whole=%d delta=%d film=%d filmraw=%d take=%d compress=%d humans=%d away=%d plan=%s',
                [Galaxy.CurrentTurn, Job.State.Serial, HashText(Job.State.Hash), StateBytes,
                    Job.WholeSize, Job.DeltaSize, FilmBytes,
                    Integer(Host.SentFilmRawBytes - FilmRawStart), Host.LastTakeMs, Job.CompressMs,
                    Session.Humans.Count, AwayCount, Plan]
            )
        );
      finally
        Job.Free;
      end;
      // CHANGE: ENHANCEMENT - --sim-net-stop-at: once every client has the state, the host
      // stops hosting as the in-game menu does: the clients' humans are disconnected, then Bye.
      // The clients must notice it by themselves.
      if (Options.NetStopAt > 0) and (Day >= Options.NetStopAt) then
      begin
        Deadline := GetTickCount64 + StallTimeoutMs;
        while not Host.AllAcked(Host.LastSerial) do
        begin
          if GetTickCount64 > Deadline then
          begin
            Emit('net host failed: the clients did not take the state before the stop');
            Exit(1);
          end;
          Host.Pump;
          NetInboxEvent.WaitFor(5);
        end;
        Host.DisconnectHumans;
        // Counted before StopNetwork, which counts every human connected again.
        Away := AwayCount;
        Emit(Format('net host stopped hosting day=%d tick=%d', [Galaxy.CurrentTurn, GetTickCount64]));
        StopNetwork;
        Emit(
            Format(
                'done net host stopped days=%d humans=%d away=%d day=%d',
                [Day, Session.Humans.Count, Away, Galaxy.CurrentTurn]
            )
        );
        Exit(0);
      end;
    end;
    // The end: every client there has the last state, and as many as came at the start are
    // there (one that left may rejoin at the end).
    Deadline := GetTickCount64 + StallTimeoutMs;
    repeat
      Host.Pump;
      if (Host.JoinedCount >= Options.NetClients) and Host.AllAcked(Host.LastSerial) then
        Break;
      if GetTickCount64 > Deadline then
      begin
        Emit(Format('net host failed: %d clients at the end', [Host.JoinedCount]));
        Exit(1);
      end;
      NetInboxEvent.WaitFor(5);
    until False;
    if Options.NetBuyRace then
      Emit(Format('net host trades remote=%d host=%d', [RemoteTrades, LocalHuman.Id]));
    if Options.NetShop then
      Emit(Format('net host shop notified=%d host=%d', [ShopNotifications, LocalHuman.Id]));
    if Options.NetNested then
    begin
      Emit(Format('net host nested outer=%d inner=%d', [NestedOuterRuns, NestedInnerRuns]));
      Emit(Format('net host session flag text-quests=%d', [Ord(Session.TextQuestsDisabled)]));
    end;
    Emit(
        Format(
            'done net host days=%d humans=%d day=%d hash=%s',
            [Options.Turns, Session.Humans.Count, Galaxy.CurrentTurn, HashText(GalaxyStateHash)]
        )
    );
  finally
    if @AfterCommandHook = @CountRemoteTrade then
      AfterCommandHook := PreviousAfterCommand;
    PreviousAfterCommand := nil;
    if @ShopStockChangedHandler = @CountShopNotification then
      ShopStockChangedHandler := PreviousShopHandler;
    TradeWindow := False;
    RaceArmed := False;
    ShopRun := False;
    RemoveNetTalkProbe;
    ProbeSendsFilms := False;
    StopNetwork;
    NetLogHook := nil;
  end;
end;

// Decodes each film the host sent, as the star map would before playing it; returns the
// bytes they had on the wire and adds them to Count. OwnStar says whether one was of this client's star.
function TakeFilms(Client: TNetClient; var Count: Integer; out OwnStar: Boolean): Integer;
var
  Film: TNetClientFilm;
  Decoded: TEFilm;
begin
  Result := 0;
  OwnStar := False;
  Decoded := TEFilm.Create;
  try
    repeat
      Film := Client.TakeFilm;
      if Film = nil then
        Break;
      try
        Decoded.LoadFromBuffer(Film.Bytes);
        Inc(Result, Film.CompressedSize);
        Inc(Count);
        if (LocalHuman <> nil) and (LocalHuman.PlayerStar <> nil)
            and (Film.Header.StarId = Integer(LocalHuman.PlayerStar.Id)) then
          OwnStar := True;
      finally
        Film.Free;
      end;
    until False;
  finally
    Decoded.Free;
  end;
end;

// The dialogue the host's day asks this client's human: the talk screen's first answer to a
// scripted talk is to agree (AcceptScriptedTalk), predicted here and sent to the host; then
// TalkDone. A talk about a ship this state does not have is declined, as the screens decline
// it; the screens also need the star map of the ship's star, which a headless client does not
// have. With Leave the client leaves instead; returns whether it did. Held says that the talk
// waited for the end of the client's film.
function AnswerTalk(Client: TNetClient; Leave, Held: Boolean): Boolean;
var
  Request: TTalkRequestMessage;
  Ship: TShip;
  Answered: Boolean;
  Age: Integer;
begin
  Result := False;
  Age := Client.TalkRequestAge;
  if not Client.TakeTalkRequest(Request) then
    Exit;
  if Leave then
  begin
    Client.Leave(5000);
    Emit(Format('net client left in a talk ship=%d human=%d', [Request.ShipId, Client.HumanId]));
    Exit(True);
  end;
  Ship := nil;
  if (Galaxy <> nil) and (Request.ShipId <> 0) then
    Ship := TShip(Galaxy.IdToShip(Cardinal(Request.ShipId), False));
  Answered :=
      (Request.HumanId = Client.HumanId)
          and (Request.PlanetId = 0)
          and (Ship <> nil)
          and (LocalPlayer <> nil);
  try
    if Answered then
    begin
      LocalHuman.TalkShip := Ship;
      LocalHuman.TalkPlanet := nil;
      LocalHuman.TalkScripted := Request.Scripted;
      LocalHuman.TalkType := Request.TalkType;
      LocalHuman.TalkAmount := Request.Amount;
      LocalHuman.TalkResponse := 0;
      LocalHuman.TalkText := Request.Text;
      // As the talk screen does (fTalk): leaving runs on the host's turn thread, in its job.
      EnterTalk(Ship);
      if Request.Scripted then
        AcceptScriptedTalk;
      LeaveTalk(Ship);
      LocalHuman.TalkScripted := False;
    end;
  finally
    Client.SendTalkDone;
  end;
  Emit(
      Format(
          'net client talk ship=%d kind=%d answered=%d response=%d human=%d held=%d wait=%d',
          [Request.ShipId, Request.TalkType, Ord(Answered), LocalHuman.TalkResponse, Client.HumanId,
              Ord(Held), Age]
      )
  );
end;

const
  JoinPhaseNames: array[TNetJoinPhase] of AnsiString =
      ('connecting', 'joining', 'character', 'receiving', 'joined');

function RunNetClient(const Options: TSimulationOptions): Integer;
var
  Client: TNetClient;
  Address: AnsiString;
  Port, Colon, Days, Day, Mismatches, FilmBytes, FilmCount, LastPlayedDay, Index: Integer;
  Have, Size: Integer;
  Deadline, FilmUntil: QWord;
  Report: TNetApplyReport;
  Plan: AnsiString;
  Phase, ShownPhase: TNetJoinPhase;
  OwnFilm, FilmPlaying, TalkHeld: Boolean;
  Character: TJoinCharacter;
  Outcome: TCommandResultMessage;
  RefusalShown: WideString;
begin
  Result := 0;
  Colon := LastDelimiter(':', Options.NetJoin);
  Address := Copy(Options.NetJoin, 1, Colon - 1);
  Port := StrToInt(Copy(Options.NetJoin, Colon + 1, MaxInt));
  StateHashes := True;
  NetLogHook := @EmitNetEvent;
  Days := -1;
  Mismatches := 0;
  LastPlayedDay := -1;
  FilmBytes := 0;
  FilmCount := 0;
  FilmUntil := 0;
  TalkHeld := False;
  RefusalShown := '';
  BuyWholeStockGood := Options.NetBuyRace;
  if Options.NetNested then
    RegisterNestedProbe;
  try
    // The connect runs on its own thread, as the game's join does; each phase is printed.
    Client := JoinGame(Address, Port, WideString(Options.NetName), False);
    ShownPhase := jpJoined;
    CurrentScreenId := screenPlanet;
    RequestedScreenId := screenNone;
    Deadline := GetTickCount64 + StallTimeoutMs;
    while not Client.HostLeft do
    begin
      Client.Pump;
      Phase := Client.JoinPhase;
      if (Days < 0) and (Phase <> ShownPhase) then
      begin
        Client.ReceiveProgress(Have, Size);
        Emit(Format('net client join phase=%s have=%d size=%d', [JoinPhaseNames[Phase], Have, Size]));
        ShownPhase := Phase;
      end;
      // A first join: the tests choose a fixed character (a Peleng warrior with a radar and a
      // weapon), as the new-game screen would send it.
      if Client.CharacterWanted then
      begin
        Character := PresetCharacter(1);
        Character.Chosen := True;
        Character.Race := 1;
        Character.Face := 0;
        Character.Skills[0] := 0;
        Character.Skills[1] := 3;
        Character.Items[0] := 45;
        Character.Items[1] := 50;
        Client.SendCharacter(WideString(Options.NetName), Character);
      end;
      // A join cancelled once the host has let the client in, before the state is applied.
      if Options.NetCancelJoin and (Phase >= jpReceiving) then
      begin
        Client.ReceiveProgress(Have, Size);
        Emit(
            Format(
                'net client join cancelled phase=%s have=%d size=%d human=%d',
                [JoinPhaseNames[Phase], Have, Size, Client.HumanId]
            )
        );
        StopNetwork;
        Emit('done net client cancelled');
        Exit(0);
      end;
      // CHANGE: ENHANCEMENT - The trades the host relayed run here between two steps, as the
      // screens run them at a safe point.
      Client.ApplyRelayed;
      // A refusal shows as a bubble of this client's human (NetClient.ShowRefusal).
      while Client.TakeCommandResult(Outcome) do
        if Outcome.Ok then
        begin
          if Options.NetShop then
            Emit(
                Format(
                    'net client result seq=%d kind=%s ok=1 human=%d',
                    [Outcome.Sequence, CommandKindName(Outcome.Kind), Client.HumanId]
                )
            );
        end
        else
        begin
          RefusalShown := RefusalText(Outcome.Reason);
          Emit(
              Format(
                  'net client refused seq=%d kind=%s reason=%s bubble=%d human=%d',
                  [Outcome.Sequence, CommandKindName(Outcome.Kind), RefusalReasonName(Outcome.Reason),
                      Ord((LocalHuman <> nil) and (LocalHuman.FindBubbleByText(RefusalShown, False) <> nil)),
                      Client.HumanId]
              )
          );
        end;
      FilmBytes := FilmBytes + TakeFilms(Client, FilmCount, OwnFilm);
      if OwnFilm and (Options.NetFilmMs > 0) then
        FilmUntil := GetTickCount64 + QWord(Options.NetFilmMs);
      // A dialogue that comes while the client plays its film waits for the film's end, as
      // the star map's wait at the film's end answers it (NetPlay).
      FilmPlaying := GetTickCount64 < FilmUntil;
      if Client.HasTalkRequest and Client.MayHoldTalk(FilmPlaying) then
        TalkHeld := True
      else if Client.HasTalkRequest then
      begin
        if AnswerTalk(Client, Options.NetTalkLeave, TalkHeld) then
          Break;
        TalkHeld := False;
      end;
      if not Client.HasState or FilmPlaying then
      begin
        if GetTickCount64 > Deadline then
        begin
          Emit('net client failed: no state from the host');
          Exit(1);
        end;
        NetInboxEvent.WaitFor(5);
        Continue;
      end;
      Report := Client.ApplyState;
      Inc(Days);
      if Report.Hash <> Report.HostHash then
        Inc(Mismatches);
      Emit(
          Format(
              'net client day=%d serial=%d hash=%s match=%d human=%d state=%d received=%d delta=%d film=%d films=%d load=%d',
              [Report.Day, Report.Serial, HashText(Report.Hash), Ord(Report.Hash = Report.HostHash),
                  Client.HumanId, Report.StateBytes, Report.ReceivedBytes, Ord(Report.Delta),
                  FilmBytes, FilmCount, Report.LoadMs]
          )
      );
      FilmBytes := 0;
      FilmCount := 0;
      // The state replaced the human's bubbles; the refusal shows again.
      if RefusalShown <> '' then
      begin
        Emit(
            Format(
                'net client refusal after state bubble=%d',
                [Ord(LocalHuman.FindBubbleByText(RefusalShown, False) <> nil)]
            )
        );
        RefusalShown := '';
      end;
      if (Options.NetLeaveAt > 0) and (Days >= Options.NetLeaveAt) then
      begin
        Client.Leave(5000);
        Emit(Format('net client left day=%d human=%d', [Galaxy.CurrentTurn, Client.HumanId]));
        Break;
      end;
      // One turn a day: a state that comes again for the same day (another join) is only
      // applied.
      if HumanHoldsDay(LocalHuman) and (Galaxy.CurrentTurn <> LastPlayedDay) then
      begin
        Plan := '';
        Index := Session.Humans.IndexOf(LocalHuman) + 1;
        if Options.NetNested and (NestedOuterRuns = 0) then
        begin
          SubmitCommand(NewCommand(ckNetNestedOuter));
          Emit(Format('net client nested outer=%d inner=%d', [NestedOuterRuns, NestedInnerRuns]));
          // CHANGE: ENHANCEMENT - The session flags are the host's: it refuses a client's
          // (NetHost.IsHostOnlyCommand), and the next state undoes this prediction.
          SetSessionFlagValue(SessionFlagTextQuestsDisabled, not Session.TextQuestsDisabled);
          Emit(Format('net client session flag text-quests=%d', [Ord(Session.TextQuestsDisabled)]));
        end;
        // CHANGE: ENHANCEMENT - --sim-net-shop: the first day is the shop turn.
        if Options.NetShop and (LastPlayedDay < 0) then
        begin
          if not PlayShopTurn(Client, Options.NetName) then
          begin
            Emit('net client failed: the shop turn');
            Exit(1);
          end;
        end
        else
          PlayHumanTurn(LocalHuman, Galaxy.CurrentTurn, Index, Plan);
        LastPlayedDay := Galaxy.CurrentTurn;
      end;
      Deadline := GetTickCount64 + StallTimeoutMs;
    end;
    if Client.Refused or (Client.Error <> '') then
    begin
      Emit('net client failed: ' + Client.Error);
      Result := 1;
    end
    // CHANGE: ENHANCEMENT - The host stopped hosting or quit: noticed by the pump, not by a
    // wait for something that never comes.
    else if Client.HostSaidBye then
      Emit(Format('net client host left bye=1 tick=%d', [GetTickCount64]));
    if Mismatches > 0 then
      Result := 1;
    if Galaxy <> nil then
      Day := Galaxy.CurrentTurn
    else
      Day := 0;
    Emit(
        Format(
            'done net client days=%d human=%d mismatches=%d day=%d',
            [Days, Client.HumanId, Mismatches, Day]
        )
    );
  finally
    BuyWholeStockGood := False;
    StopNetwork;
    NetLogHook := nil;
  end;
end;

end.
