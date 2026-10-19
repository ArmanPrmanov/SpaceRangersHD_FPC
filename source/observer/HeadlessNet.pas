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
// CHANGE: ENHANCEMENT - --sim-net-shop: Net1 goes through a government dialogue before its
// first purchase, which the host applies with the purchase while its own dialogue is open; the
// host's dialogue state must stay as it was (docs/network.md, Tests).
// CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn: a client takes its end turn back before the
// host's first day, which waits for that, and ends it again; once the second day has begun, the
// host refuses the same (docs/network.md, Tests). Then its end turns ask to continue the travel,
// and once a state says that it continues, it stops the travel before the host's next day,
// which waits for that, and plays that day.
// CHANGE: ENHANCEMENT - --sim-net-quest=DAY (docs/progress/2026-10-19-text-quests-plan.md,
// Phase C): a client plays a text quest with the headless quest player on its DAY-th turn,
// before its end turn: the planet quest a probe command gives it, or a quest by name
// (--sim-text-quest). The host lands every client at the first one's planet, so a second
// client's BeginTextQuest finds the first one's lock (in-use); with --sim-net-silent-at the
// client goes silent in the middle of its quest and abandons it after the reconnect. Both sides
// print the quest's lines, the host what its barrier applied and its wait text, a client the
// waits its host's status gives.
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
// CHANGE: ENHANCEMENT - The command of --sim-net-quest's probe, for the host, its clients and a
// replay of the host's log.
procedure RegisterNetQuestProbe;
implementation
uses
  SysUtils,
  EC_Buf,
  Globals,
  aCommands,
  aDialogActions,
  aMyFunction,
  aPlanetActions,
  aScript,
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
  NetSession,
  NetPlay,
  QuestRun,
  HeadlessQuest,
  aQuestActions,
  aRanger;

const
  // Without progress for this long, a run fails instead of hanging the test.
  StallTimeoutMs = 120000;
  // CHANGE: ENHANCEMENT - A silent client (--sim-net-silent-at) drops its frozen connection this
  // long past the host's silence timeout and reconnects: the host has let its human go by then
  // and runs a day without it, and the client is back for the days after it.
  SilentLingerMs = 500;
  // CHANGE: ENHANCEMENT - A silent host (--sim-net-host-silent-at) drops the peers it froze this
  // long past the silence timeout.
  HostSilentLingerMs = 5000;

procedure EmitNetEvent(const Text: AnsiString);
begin
  // CHANGE: ENHANCEMENT - A disconnect, a lost connection and a takeover say when, so that the
  // tests can check how soon silence is noticed (docs/network.md, Tests).
  // CHANGE: ENHANCEMENT - So do the steps of a client's reconnect.
  if (Pos(') disconnected', Text) > 0) or (Pos(') lost: ', Text) > 0) or (Pos(') taken over ', Text) > 0)
      or (Pos('client lost the host', Text) = 1) or (Pos('client reconnect', Text) = 1) then
    Emit(Format('net %s tick=%d', [Text, GetTickCount64]))
  else
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
  // --sim-net-shop: the host's own open dialogue (its message, script and injected answer),
  // how often it was checked, whether it was ever changed, and the dialogue commands of remote
  // humans the host ran meanwhile.
  HostDialogueOpen: Boolean;
  HostDialogueScript: TScript;
  HostDialogueEntry: PScriptDialogInjection;
  HostDialogueSavedScript: TScript;
  HostDialogueChecks: Integer;
  HostDialogueChanged: Boolean;
  HostDialogueRemote: Integer;

procedure CountRemoteTrade(const Command: TPlayerCommand);
begin
  if Assigned(PreviousAfterCommand) then
    PreviousAfterCommand(Command);
  if (Command.Kind = ckTradeGoods) and (LocalHuman <> nil) and (Integer(Command.Actor) <> LocalHuman.Id) then
    Inc(RemoteTrades);
  if HostDialogueOpen
      and (LocalHuman <> nil)
      and (Integer(Command.Actor) <> LocalHuman.Id)
      and ((Command.Kind = ckBeginGovernmentDialog)
          or (Command.Kind = ckScriptAuxiliaryCode)
          or (Command.Kind = ckLeaveGovernment)) then
    Inc(HostDialogueRemote);
end;

// --sim-net-shop: the host's human has a script dialogue open while its clients' commands
// apply (the screens would show it): a message, a script and an injected answer.
procedure OpenHostDialogue;
begin
  HostDialogueSavedScript := CurrentScript;
  HostDialogueScript := nil;
  if Galaxy.Scripts.Count > 0 then
    HostDialogueScript := TScript(Galaxy.Scripts[0]);
  ClearScriptDialogRules;
  New(HostDialogueEntry);
  HostDialogueEntry.Script := HostDialogueScript;
  HostDialogueEntry.DialogName := 'host';
  HostDialogueEntry.Text := '';
  HostDialogueEntry.Answer := 'host';
  HostDialogueEntry.Priority := 0;
  HostDialogueEntry.AnswerData := 0;
  HostDialogueEntry.ReplaceGreeting := False;
  HostDialogueEntry.ActionCode := '';
  HostDialogueEntry.ActionScript := nil;
  ScriptDialogInjections.Add(HostDialogueEntry);
  Session.ScriptDialogIndex := 3;
  CurrentScript := HostDialogueScript;
  HostDialogueChecks := 0;
  HostDialogueChanged := False;
  HostDialogueRemote := 0;
  HostDialogueOpen := True;
end;

procedure CheckHostDialogue;
begin
  if not HostDialogueOpen then
    Exit;
  Inc(HostDialogueChecks);
  if (ForeignDialogHuman <> nil)
      or (Session.ScriptDialogIndex <> 3)
      or (CurrentScript <> HostDialogueScript)
      or (ScriptDialogInjections = nil)
      or (ScriptDialogInjections.Count <> 1)
      or (ScriptDialogInjections[0] <> HostDialogueEntry)
      or (HostDialogueEntry.Answer <> 'host') then
    HostDialogueChanged := True;
end;

procedure CloseHostDialogue;
begin
  if not HostDialogueOpen then
    Exit;
  CheckHostDialogue;
  HostDialogueOpen := False;
  Emit(
      Format(
          'net host dialogue kept=%d checks=%d remote=%d',
          [Ord(not HostDialogueChanged), HostDialogueChecks, HostDialogueRemote]
      )
  );
  ClearScriptDialogRules;
  HostDialogueEntry := nil;
  Session.ScriptDialogIndex := -1;
  CurrentScript := HostDialogueSavedScript;
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
  if Done then
    CheckHostDialogue;
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

// The first three items of the planet's shop, in its order, that the shop takes back.
function PickShopItems(Planet: TPlanet; out X, Y, Z: TItem): Boolean;
var
  I: Integer;
  Item: TItem;
begin
  X := nil;
  Y := nil;
  Z := nil;
  for I := 0 to Planet.EquipmentShop.Count - 1 do
  begin
    Item := TItem(Planet.EquipmentShop[I]);
    if not IsTradedBack(Item) then
      Continue;
    if X = nil then
      X := Item
    else if Y = nil then
      Y := Item
    else
    begin
      Z := Item;
      Exit(True);
    end;
  end;
  Result := False;
end;

// CHANGE: ENHANCEMENT - Whether a human other than the local one has the item with that id:
// its ranger's equipment, artefacts or storage, or the item it holds on the ship screen.
function OwnedByOtherHuman(Id: Integer): Boolean;
var
  I, J: Integer;
  H: THuman;
  P: TPlayer;
begin
  Result := False;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    H := Session.Humans[I];
    P := H.Player;
    if (H = LocalHuman) or (P = nil) then
      Continue;
    if (H.SelectedHoldItem <> nil) and (Integer(H.SelectedHoldItem.Id) = Id) then
      Exit(True);
    for J := 0 to P.Inventory.Count - 1 do
      if Integer(TItem(P.Inventory[J]).Id) = Id then
        Exit(True);
    for J := 0 to P.Artefacts.Count - 1 do
      if Integer(TItem(P.Artefacts[J]).Id) = Id then
        Exit(True);
    for J := 0 to P.StorageEntries.Count - 1 do
      if (PStorageEntry(P.StorageEntries[J]).Item <> nil)
          and (Integer(PStorageEntry(P.StorageEntries[J]).Item.Id) = Id) then
        Exit(True);
  end;
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
// buys the item Z, puts it into its storage and sells it from there, and ends its turn. Net2
// waits until the host's relays of Net1's trades have run here, one at a time: its grid no
// longer shows X, the planet's stock of the good went down and up again, and Y and Z left the
// shop and came back (the sales' relays, RelayedSale), before any state; then it buys X, which the host refuses at once (item-gone), ends its turn, and right after
// sends a purchase of the good without waiting for it, which the host applies after the day.
function PlayShopTurn(Client: TNetClient; const Name: AnsiString): Boolean;
var
  H: THuman;
  P: TPlayer;
  Planet: TPlanet;
  X, Y, Z: TItem;
  XId, YId, ZId, Good, Before, Low, Count, Slot: Integer;
  YGone, ZGone: Boolean;
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
  if not PickShopItems(Planet, X, Y, Z) or (Good < 0) then
  begin
    Emit('net client shop failed: nothing to trade');
    Exit;
  end;
  XId := X.Id;
  YId := Y.Id;
  ZId := Z.Id;
  if Name = 'Net1' then
  begin
    // A government dialogue first, as the government screen runs it; the host applies it
    // with the purchase after it, while its own dialogue is open.
    EnterGovernment;
    BeginGovernmentDialog;
    RunScriptsAuxiliaryCode;
    LeaveGovernment;
    Emit('net client shop dialogue sent');
    Reason := BuyShopItem(H, ShopSlotIndexOf(H, X), X);
    Emit(Format('net client shop bought item=%d reason=%s', [XId, Reason]));
    TradeGoodsFor(H, Good, 1, False);
    TradeGoodsFor(H, Good, 1, True);
    Emit(Format('net client shop traded good=%d', [Good]));
    Reason := BuyShopItem(H, ShopSlotIndexOf(H, Y), Y);
    SellToShop(H, Y);
    Emit(Format('net client shop sold item=%d bought=%s', [YId, Reason]));
    if Reason = '' then
    begin
      Reason := BuyShopItem(H, ShopSlotIndexOf(H, Z), Z);
      if Reason = '' then
        SellFromStorage(H, Z);
      Emit(Format('net client shop sold stored item=%d bought=%s', [ZId, Reason]));
    end;
    EndTurnFor(H);
    Exit(Reason = '');
  end;
  Before := P.GetLocationGoodsEntry(Good).Count;
  Low := Before;
  Count := Before;
  Slot := ShopSlotIndexOf(H, X);
  YGone := False;
  ZGone := False;
  Deadline := GetTickCount64 + StallTimeoutMs;
  repeat
    Client.Pump;
    if Client.ApplyRelayed(1) > 0 then
    begin
      Count := P.GetLocationGoodsEntry(Good).Count;
      if Count < Low then
        Low := Count;
      YGone := YGone or (FindShopStockItem(Planet, YId) = nil);
      ZGone := ZGone or (FindShopStockItem(Planet, ZId) = nil);
    end
    else
      NetInboxEvent.WaitFor(5);
    if (FindShopStockItem(Planet, XId) = nil)
        and (Low < Before)
        and (Count = Before)
        and YGone
        and ZGone
        and (FindShopStockItem(Planet, YId) <> nil)
        and (FindShopStockItem(Planet, ZId) <> nil) then
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
  // The sales came back as their effects, before any state: the items are in the shop and the
  // grid shows them, and Net1 no longer has them here.
  Emit(
      Format(
          'net client shop sale relay y-shop=1 y-grid=%d y-owned=%d z-shop=1 z-grid=%d z-owned=%d',
          [Ord(GridShowsItem(H, YId)), Ord(OwnedByOtherHuman(YId)), Ord(GridShowsItem(H, ZId)),
              Ord(OwnedByOtherHuman(ZId))]
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

// CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn, after a client's turn: it takes the end turn
// back (CancelEndTurn) and waits for the host's answer. First: before the host's day, which waits
// for it; the host applies it, the human holds the day again here, and ends its turn again.
// Otherwise once the host's day has begun (its status says so) or run: the host refuses it.
// Whether it went as it should.
function ProbeCancelEndTurn(Client: TNetClient; First: Boolean): Boolean;
var
  Deadline: QWord;
  Sent, Accepted, Holds: Boolean;
begin
  Result := False;
  Deadline := GetTickCount64 + StallTimeoutMs;
  while not First and not Client.Status.DayRunning and not Client.HasState do
  begin
    if GetTickCount64 > Deadline then
    begin
      Emit('net client failed: the day did not begin');
      Exit;
    end;
    Client.Pump;
    NetInboxEvent.WaitFor(5);
  end;
  Sent := Client.SendCancelEndTurn(CancelEndTurnCommand);
  while Sent and not (Client.EndTurnCancel in [ncAccepted, ncRefused]) do
  begin
    if GetTickCount64 > Deadline then
    begin
      Emit('net client failed: the host did not answer the cancelled end turn');
      Exit;
    end;
    Client.Pump;
    NetInboxEvent.WaitFor(5);
  end;
  Accepted := Client.EndTurnCancel = ncAccepted;
  Holds := False;
  if Accepted then
  begin
    Client.TakeCancelledEndTurn;
    Holds := HumanHoldsDay(LocalHuman);
    EndTurnFor(LocalHuman);
  end;
  Emit(
      Format(
          'net client end turn cancel day=%d first=%d sent=%d accepted=%d holds=%d human=%d',
          [Galaxy.CurrentTurn, Ord(First), Ord(Sent), Ord(Accepted), Ord(Holds), Client.HumanId]
      )
  );
  Result := Sent and (Accepted = First) and (Holds = First);
end;

// CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn, after a state that says the client's human
// continues its travel: Cancel stops it (CancelEndTurn with StopTravel) before the host's next
// day, which waits for that; the human holds that day here then. Whether it did. A host that
// ended meanwhile (the last state) leaves it untried.
function ProbeStopTravel(Client: TNetClient): Boolean;
var
  Deadline: QWord;
  Sent, Accepted, Holds: Boolean;
begin
  Result := False;
  Deadline := GetTickCount64 + StallTimeoutMs;
  Sent := Client.SendCancelEndTurn(CancelEndTurnCommand(True));
  while Sent and not (Client.EndTurnCancel in [ncAccepted, ncRefused]) do
  begin
    if Client.HostLeft then
    begin
      Emit('net client travel cancel untried: the host left');
      Exit(True);
    end;
    if GetTickCount64 > Deadline then
    begin
      Emit('net client failed: the host did not answer the stopped travel');
      Exit;
    end;
    Client.Pump;
    NetInboxEvent.WaitFor(5);
  end;
  Accepted := Client.EndTurnCancel = ncAccepted;
  if Accepted then
    Client.TakeCancelledEndTurn;
  Holds := HumanHoldsDay(LocalHuman);
  Emit(
      Format(
          'net client travel cancel day=%d sent=%d accepted=%d holds=%d continues=%d human=%d',
          [Galaxy.CurrentTurn, Ord(Sent), Ord(Accepted), Ord(Holds), Ord(LocalHuman.ContinueUntilArrival),
              Client.HumanId]
      )
  );
  Result := Sent and Accepted and Holds;
end;

// CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn: a turn whose travel lasts: the human, in
// normal space, flies to the planet of its star farthest from it, and its end turn asks to
// continue until arrival, so the host runs the next days without it. False
// when there is no planet to fly to.
function PlayFarTravel(Human: THuman; var Plan: AnsiString): Boolean;
var
  P: TPlayer;
  I: Integer;
  Planet, Far: TPlanet;
  Distance, Best: Single;
  Command: TPlayerCommand;
begin
  Result := False;
  P := Human.Player;
  if (P = nil) or not P.InNormalSpace or (P.CurrentStar = nil) then
    Exit;
  Far := nil;
  Best := 0;
  for I := 0 to P.CurrentStar.Planets.Count - 1 do
  begin
    Planet := TPlanet(P.CurrentStar.Planets[I]);
    Distance := PointDistanceSquared(P.Position, Planet.GetPosition);
    if Distance > Best then
    begin
      Best := Distance;
      Far := Planet;
    end;
  end;
  if Far = nil then
    Exit;
  Command := NewCommand(ckOrderMove);
  AddPoint(Command, Far.GetPosition);
  AddInt(Command, mfClearPending);
  SubmitCommand(Command);
  SubmitCommand(NewCommand(ckApplyPendingOrders));
  SubmitCommand(NewCommand(ckBeginSpaceDay));
  Command := NewCommand(ckEndTurn);
  AddInt(Command, 1);
  SubmitCommand(Command);
  Plan := Plan + 'F';
  Emit(Format('net client far travel day=%d planet=%d distance=%d', [Galaxy.CurrentTurn, Far.Id, Round(Sqrt(Best))]));
  Result := True;
end;

var
  // CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn: the client's turns in normal space fly far
  // and continue (PlayFarTravel), until a continuing travel has been stopped.
  EndTurnContinues: Boolean;

// Whether a remote human continues its travel and does not hold the day.
function RemoteHumanContinues: Boolean;
var
  I: Integer;
  Human: THuman;
begin
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human <> LocalHuman) and Human.Connected and Human.ContinueUntilArrival and not HumanHoldsDay(Human)
        and (Human.Player <> nil) and not Human.Player.InHyperspace then
      Exit(True);
  end;
  Result := False;
end;


// CHANGE: ENHANCEMENT - --sim-net-quest=DAY (docs/progress/2026-10-19-text-quests-plan.md,
// Phase C). The probe command gives its human a government planet quest to the planet the
// human is landed at, whose text quest is the galaxy's first planet quest when it has none. It
// is a client's command like any other: the host runs it from the queue, before the
// BeginTextQuest that follows it, and its log records it.
const
  ckNetQuestProbe = 1003;
type
  // What a client's quest turn did: played the quest and ended the turn; left a turn to play
  // (the quest was refused); abandoned the quest after a reconnect; failed.
  TNetQuestTurn = (nqPlayed, nqTurn, nqAbandoned, nqFailed);
var
  QuestProbeRegistered: Boolean;
  // The host: the quest commands of remote humans it applied (aQuestActions, 600-609): the
  // BeginTextQuests (as they arrive), those its barrier applied (ApplyQueues, QuestBarrier set)
  // and the CloseQuests among them, and those applied anywhere else; the wait text it printed
  // last; where its first client joined; the hook the count chains.
  QuestBarrier: Boolean;
  QuestBegun: Integer;
  QuestBarrierCommands: Integer;
  QuestClosed: Integer;
  QuestEarly: Integer;
  QuestWaitShown: WideString;
  QuestJoinTarget: TObject;
  PreviousQuestAfterCommand: TCommandHook;
  // A client: the wait text it printed last (ClientStatusHook).
  ClientWaitShown: WideString;

function HoldsPlanetQuest(Human: THuman; Planet: TPlanet): Boolean;
var
  I: Integer;
  Quest: PQuest;
begin
  Result := False;
  if Human.Player = nil then
    Exit;
  for I := 0 to Human.Player.Quests.Count - 1 do
  begin
    Quest := Human.Player.Quests[I];
    if (Quest.QuestType = qtPlanetQuest) and (Quest.ObjectiveTarget = Planet) then
      Exit(True);
  end;
end;

procedure ExecuteNetQuestProbe(const Command: TPlayerCommand);
var
  Human: THuman;
  Planet: TPlanet;
  I: Integer;
begin
  Human := ActorHuman(Command);
  if (Human.Player = nil) or (Human.Player.CurrentPlanet = nil) then
    Exit;
  Planet := Human.Player.CurrentPlanet;
  if Planet.TextQuestId = -1 then
    for I := 0 to Galaxy.Planets.Count - 1 do
      if TPlanet(Galaxy.Planets[I]).TextQuestId <> -1 then
      begin
        Planet.TextQuestId := TPlanet(Galaxy.Planets[I]).TextQuestId;
        Break;
      end;
  if (Planet.TextQuestId <> -1) and not HoldsPlanetQuest(Human, Planet) then
    GiveProbePlanetQuest(Human, Planet);
end;

procedure RegisterNetQuestProbe;
begin
  if QuestProbeRegistered then
    Exit;
  RegisterCommand(ckNetQuestProbe, 'NetQuestProbe', @ExecuteNetQuestProbe);
  QuestProbeRegistered := True;
end;

// The text as one line of output.
function OneLine(const Text: WideString): AnsiString;
begin
  Result := StringReplace(UTF8Encode(Text), #13#10, ' | ', [rfReplaceAll]);
end;

// AfterCommandHook of the host (--sim-net-quest).
procedure CountQuestCommand(const Command: TPlayerCommand);
begin
  if Assigned(PreviousQuestAfterCommand) then
    PreviousQuestAfterCommand(Command);
  if (LocalHuman = nil) or (Integer(Command.Actor) = LocalHuman.Id) then
    Exit;
  if Command.Kind = ckBeginTextQuest then
    Inc(QuestBegun)
  else if (Command.Kind >= ckQuestRandomSeed) and (Command.Kind <= ckCloseQuest) then
    if QuestBarrier then
    begin
      Inc(QuestBarrierCommands);
      if Command.Kind = ckCloseQuest then
        Inc(QuestClosed);
    end
    else
      Inc(QuestEarly);
end;

// The host's wait for its peers names a remote human who plays a text quest, or says who is
// busy with a quest's days: printed when the text changes.
procedure EmitHostQuestWait(Day: Integer);
var
  I: Integer;
  Human: THuman;
  Any: Boolean;
  Text: WideString;
begin
  Any := False;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human <> LocalHuman) and (Human.TextQuestOpen or (Human.QuestDaysOwed > 0)) then
      Any := True;
  end;
  if not Any then
    Exit;
  Text := HostWaitText;
  if Text = QuestWaitShown then
    Exit;
  QuestWaitShown := Text;
  Emit(Format('net host wait day=%d text=%s', [Day, OneLine(Text)]));
end;

// JoinPlanetHook of the host: every client joins where the first one did.
function QuestJoinPlanet(Race: Integer): TObject;
begin
  if QuestJoinTarget = nil then
    QuestJoinTarget := FindJoinPlanet(Race);
  Result := QuestJoinTarget;
end;

// The activity the host's status gives the human Id (saNone when it names none).
function StatusActivityOf(Client: TNetClient; Id: Integer): TStatusActivity;
var
  I: Integer;
  Status: TStatusMessage;
begin
  Status := Client.Status;
  for I := 0 to High(Status.Humans) do
    if Status.Humans[I].Id = Id then
      Exit(Status.Humans[I].Activity);
  Result := saNone;
end;

// The first human but this client's whom the host's status says plays a text quest; 0: none.
function OtherQuestHuman(Client: TNetClient): Integer;
var
  I: Integer;
  Status: TStatusMessage;
begin
  Status := Client.Status;
  for I := 0 to High(Status.Humans) do
    if (Status.Humans[I].Id <> Client.HumanId) and (Status.Humans[I].Activity = saInTextQuest) then
      Exit(Status.Humans[I].Id);
  Result := 0;
end;

// ClientStatusHook of a client (--sim-net-quest): its wait for the day, as the host's status
// gives it, when the status says another human plays a text quest or owes days for one.
procedure ShowClientQuestWait;
var
  I: Integer;
  Client: TNetClient;
  Status: TStatusMessage;
  Any: Boolean;
  Text: WideString;
begin
  Client := ActiveClient;
  if Client = nil then
    Exit;
  Status := Client.Status;
  Any := False;
  for I := 0 to High(Status.Humans) do
    if (Status.Humans[I].Id <> Client.HumanId) and (Status.Humans[I].Activity <> saNone) then
      Any := True;
  if not Any then
    Exit;
  Text := ClientWaitText;
  if Text = ClientWaitShown then
    Exit;
  ClientWaitShown := Text;
  Emit(Format('net client wait human=%d text=%s', [Client.HumanId, OneLine(Text)]));
end;

// A client's quest turn (--sim-net-quest). With a quest by name (TextQuest) the client plays it;
// otherwise it sends the probe and plays the planet quest its visit gives (TQuestRun.Open),
// Net1 at once, another client once the host's status says another human plays one: the relay
// of that human's BeginTextQuest has come before that status, so the planet's prompt would say
// who plays (TextQuestHolder), and the host must refuse this one (in-use). Played to its end,
// the quest's day ends with EndTurn, which the host's day waits for although the human owes the
// quest's days here already (NetPlay.ClientQuestDayEnds). With NetSilentAt the client plays one
// choice, goes silent until the host must have timed it out, reconnects and abandons the quest
// once the state after the reconnect has come (TQuestRun.Abandon). Prints what it did; PlanetId
// is the planet it played at (-1: none).
function PlayNetQuest(
    Client: TNetClient;
    const Options: TSimulationOptions;
    var Plan: AnsiString;
    out PlanetId: Integer
): TNetQuestTurn;
var
  Player: THeadlessQuestPlayer;
  Planet: TPlanet;
  Holder: THuman;
  Named, Opened: Boolean;
  Outcome: TQuestRunOutcome;
  Deadline: QWord;
  HolderId, QuestId: Integer;
begin
  Result := nqFailed;
  Named := Options.TextQuest <> '';
  Planet := LocalPlayer.CurrentPlanet;
  PlanetId := -1;
  if Planet <> nil then
    PlanetId := Planet.Id;
  if not Named and (Options.NetName <> 'Net1') then
  begin
    Deadline := GetTickCount64 + StallTimeoutMs;
    while OtherQuestHuman(Client) = 0 do
    begin
      if GetTickCount64 > Deadline then
      begin
        Emit('net client failed: no other human played a text quest');
        Exit;
      end;
      Client.Pump;
      NetInboxEvent.WaitFor(5);
    end;
    Client.ApplyRelayed;
    Holder := TextQuestHolder(Planet, LocalHuman);
    HolderId := 0;
    if Holder <> nil then
      HolderId := Holder.Id;
    Emit(
        Format(
            'net client quest holder planet=%d human=%d status=%d text=%s',
            [PlanetId, HolderId, OtherQuestHuman(Client), OneLine(TextQuestTakenText(Holder))]
        )
    );
  end;
  if not Named then
    SubmitCommand(NewCommand(ckNetQuestProbe));
  QuestId := -1;
  if Planet <> nil then
    QuestId := Planet.TextQuestId;
  Player := THeadlessQuestPlayer.Create(Options.Seed);
  try
    if Named then
    begin
      Player.Start(UTF8Decode(Options.TextQuest));
      Opened := Player.Run.Quest <> nil;
    end
    else
      Opened := Player.OpenVisit;
    Emit(
        Format(
            'net client quest open day=%d human=%d planet=%d quest=%d opened=%d refused=%d',
            [Galaxy.CurrentTurn, Client.HumanId, PlanetId, QuestId, Ord(Opened), Ord(Player.Run.Refused)]
        )
    );
    if not Opened then
      Exit(nqTurn);
    // The host ran BeginTextQuest as it came, and its status says so next.
    Deadline := GetTickCount64 + StallTimeoutMs;
    while (StatusActivityOf(Client, Client.HumanId) <> saInTextQuest) and (GetTickCount64 < Deadline) do
    begin
      Client.Pump;
      NetInboxEvent.WaitFor(5);
    end;
    Emit(
        Format(
            'net client quest status human=%d activity=%d',
            [Client.HumanId, Ord(StatusActivityOf(Client, Client.HumanId))]
        )
    );
    if Options.NetSilentAt > 0 then
    begin
      Player.Step;
      Client.FreezeConnection;
      Emit(
          Format(
              'net client silent day=%d human=%d takeover=0 quest=1 steps=%d tick=%d',
              [Galaxy.CurrentTurn, Client.HumanId, Player.Steps, GetTickCount64]
          )
      );
      Deadline := GetTickCount64 + QWord(NetSilenceTimeoutMs) + SilentLingerMs;
      while GetTickCount64 < Deadline do
        Sleep(50);
      Client.LoseConnection(False);
      Deadline := GetTickCount64 + StallTimeoutMs;
      while not Client.RejoinStatePending do
      begin
        if Client.HostLeft or (GetTickCount64 > Deadline) then
        begin
          Emit('net client failed: no state after the reconnect in the quest');
          Exit;
        end;
        Client.Pump;
        NetInboxEvent.WaitFor(5);
      end;
      Player.Run.Abandon;
      Emit(
          Format(
              'net client quest abandoned human=%d planet=%d steps=%d outcome=%s',
              [Client.HumanId, PlanetId, Player.Steps, QuestOutcomeName(Player.Run.Page.Outcome)]
          )
      );
      Exit(nqAbandoned);
    end;
    Outcome := Player.Finish;
    Emit(
        Format(
            'net client quest done name=%s outcome=%s pages=%d steps=%d days=%d errors=%d respawned=%d human=%d',
            [Options.TextQuest, QuestOutcomeName(Outcome), Player.Pages, Player.Steps,
                Player.Run.DaysElapsed, Player.Errors, Ord(Player.Run.Respawned), Client.HumanId]
        )
    );
  finally
    Player.Free;
  end;
  Plan := Plan + 'q';
  Emit(
      Format(
          'net client quest owed day=%d human=%d days=%d holds=%d open=%d',
          [Galaxy.CurrentTurn, Client.HumanId, LocalHuman.QuestDaysOwed, Ord(HumanHoldsDay(LocalHuman)),
              Ord(LocalHuman.TextQuestOpen)]
      )
  );
  EndTurnFor(LocalHuman);
  Result := nqPlayed;
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
  // CHANGE: ENHANCEMENT - --sim-net-host-silent-at: the peers frozen, and until when.
  Frozen: TPeerIds;
  FrozenUntil: QWord;

  // The frozen peers that are still there (a client that reconnected took its human over and
  // the host removed its old peer) close once the silence has lasted long enough.
  procedure DropFrozenPeers;
  var
    I: Integer;
  begin
    if (Length(Frozen) = 0) or (GetTickCount64 < FrozenUntil) then
      Exit;
    for I := 0 to High(Frozen) do
      Host.Thread.RemovePeer(Frozen[I]);
    Emit(Format('net host dropped the frozen peers count=%d tick=%d', [Length(Frozen), GetTickCount64]));
    Frozen := nil;
  end;

begin
  Result := 0;
  Frozen := nil;
  FrozenUntil := 0;
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
    if Options.NetBuyRace or Options.NetShop then
    begin
      PreviousAfterCommand := AfterCommandHook;
      AfterCommandHook := @CountRemoteTrade;
    end;
    Host.OrderedTrades := True;
    Host.MayApplyTrades := @HeadlessMayApplyTrades;
    Host.TradeHook := @HostTradeHook;
    // CHANGE: ENHANCEMENT - --sim-net-quest: the probe, what the barrier applies of the quests,
    // and every client at one planet.
    QuestBegun := 0;
    QuestBarrierCommands := 0;
    QuestClosed := 0;
    QuestEarly := 0;
    QuestWaitShown := '';
    QuestJoinTarget := nil;
    if Options.NetQuestDay > 0 then
    begin
      RegisterNetQuestProbe;
      PreviousQuestAfterCommand := AfterCommandHook;
      AfterCommandHook := @CountQuestCommand;
      if not Options.NetShop then
        Host.JoinPlanetHook := @QuestJoinPlanet;
    end;
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
        OpenHostDialogue;
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
          DropFrozenPeers;
          if Options.NetQuestDay > 0 then
            EmitHostQuestWait(Day);
          // CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn: the first day waits until a client
          // has taken its end turn back (and ended it again); a day after a state that says a
          // client continues its travel, until it has stopped it (once in the run).
          if Host.PeersReady
              and (not Options.NetCancelEndTurn
                  or ((Day > 1) or (Host.CancelledEndTurns > 0))
                      and ((Host.StoppedTravels > 0) or not RemoteHumanContinues)) then
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
      QuestBarrier := True;
      try
        Host.ApplyQueues;
      finally
        QuestBarrier := False;
      end;
      CloseHostDialogue;
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
      // CHANGE: ENHANCEMENT - --sim-net-host-silent-at and --sim-net-host-exit-at: once every
      // client has the state, the host goes silent: every peer is frozen, so that the clients
      // hear nothing and time it out (docs/network.md, Tests). A silent host goes on and drops
      // what is left of them after the timeout and HostSilentLingerMs; an exiting one ends
      // without Bye, so that its clients cannot reconnect.
      if ((Options.NetHostSilentAt > 0) and (Day = Options.NetHostSilentAt))
          or ((Options.NetHostExitAt > 0) and (Day = Options.NetHostExitAt)) then
      begin
        Deadline := GetTickCount64 + StallTimeoutMs;
        while not Host.AllAcked(Host.LastSerial) do
        begin
          if GetTickCount64 > Deadline then
          begin
            Emit('net host failed: the clients did not take the state before the silence');
            Exit(1);
          end;
          Host.Pump;
          NetInboxEvent.WaitFor(5);
        end;
        Frozen := Host.FreezePeers;
        FrozenUntil := GetTickCount64 + QWord(NetSilenceTimeoutMs) + HostSilentLingerMs;
        Emit(
            Format(
                'net host silent day=%d peers=%d exit=%d tick=%d',
                [Galaxy.CurrentTurn, Length(Frozen), Ord(Day = Options.NetHostExitAt), GetTickCount64]
            )
        );
        if Day = Options.NetHostExitAt then
        begin
          StopNetwork;
          Emit(Format('done net host exited days=%d day=%d', [Day, Galaxy.CurrentTurn]));
          Exit(0);
        end;
      end;
    end;
    // The end: every client there has the last state, and as many as came at the start are
    // there (one that left may rejoin at the end).
    Deadline := GetTickCount64 + StallTimeoutMs;
    repeat
      Host.Pump;
      DropFrozenPeers;
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
    if Options.NetQuestDay > 0 then
      Emit(
          Format(
              'net host quest begun=%d barrier=%d closed=%d early=%d host=%d',
              [QuestBegun, QuestBarrierCommands, QuestClosed, QuestEarly, LocalHuman.Id]
          )
      );
    if Options.NetNested then
    begin
      Emit(Format('net host nested outer=%d inner=%d', [NestedOuterRuns, NestedInnerRuns]));
      Emit(Format('net host session flag friendly-fire=%d', [Ord(Session.FriendlyFireEnabled)]));
    end;
    Emit(
        Format(
            'done net host days=%d humans=%d day=%d hash=%s',
            [Options.Turns, Session.Humans.Count, Galaxy.CurrentTurn, HashText(GalaxyStateHash)]
        )
    );
  finally
    if @AfterCommandHook = @CountQuestCommand then
      AfterCommandHook := PreviousQuestAfterCommand;
    PreviousQuestAfterCommand := nil;
    QuestBarrier := False;
    if @AfterCommandHook = @CountRemoteTrade then
      AfterCommandHook := PreviousAfterCommand;
    PreviousAfterCommand := nil;
    if @ShopStockChangedHandler = @CountShopNotification then
      ShopStockChangedHandler := PreviousShopHandler;
    TradeWindow := False;
    RaceArmed := False;
    ShopRun := False;
    HostDialogueOpen := False;
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
  // CHANGE: ENHANCEMENT - The connection has gone silent (--sim-net-silent-at), once.
  WentSilent: Boolean;
  // CHANGE: ENHANCEMENT - The turns after which --sim-net-cancel-end-turn took the end turn back,
  // and whether it has stopped a continuing travel.
  CancelProbes: Integer;
  TravelProbed: Boolean;
  // Whether a turn it played began in normal space (else it could not travel).
  InSpaceTurns: Integer;
  // CHANGE: ENHANCEMENT - --sim-net-quest: the quest turn has come; the planet of a quest it
  // abandoned, checked after the state that follows (-1: none); the trade timeout it replaced.
  QuestPlayed: Boolean;
  QuestPlanetId, AbandonedPlanetId: Integer;
  SavedTradeTimeoutMs: Integer;
  AbandonedPlanet: TPlanet;
begin
  Result := 0;
  WentSilent := False;
  CancelProbes := 0;
  TravelProbed := False;
  InSpaceTurns := 0;
  QuestPlayed := False;
  AbandonedPlanetId := -1;
  SavedTradeTimeoutMs := ClientTradeTimeoutMs;
  if Options.NetReconnectMs > 0 then
    NetReconnectMs := Options.NetReconnectMs;
  // CHANGE: ENHANCEMENT - --sim-net-quest: a second client's BeginTextQuest waits at the host
  // while the first one plays its quest (OrderedTrades), longer than a player's would.
  if Options.NetQuestDay > 0 then
  begin
    RegisterNetQuestProbe;
    ClientStatusHook := @ShowClientQuestWait;
    ClientWaitShown := '';
    ClientTradeTimeoutMs := StallTimeoutMs;
  end;
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
          // CHANGE: ENHANCEMENT - A refused CancelEndTurn shows no bubble (NetClient).
          if Outcome.Kind <> ckCancelEndTurn then
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
      // CHANGE: ENHANCEMENT - The state after a reconnect: the turn of its day is played again,
      // since the host never got the one sent before the loss (rejoin=1).
      if Report.Rejoin then
        LastPlayedDay := -1;
      Emit(
          Format(
              'net client day=%d serial=%d hash=%s match=%d human=%d state=%d received=%d delta=%d film=%d films=%d load=%d rejoin=%d quest-days=%d',
              [Report.Day, Report.Serial, HashText(Report.Hash), Ord(Report.Hash = Report.HostHash),
                  Client.HumanId, Report.StateBytes, Report.ReceivedBytes, Ord(Report.Delta),
                  FilmBytes, FilmCount, Report.LoadMs, Ord(Report.Rejoin), LocalHuman.QuestDaysOwed]
          )
      );
      // CHANGE: ENHANCEMENT - --sim-net-quest: the quest abandoned in the reconnect is still
      // there: the host never got it.
      if AbandonedPlanetId >= 0 then
      begin
        AbandonedPlanet := TPlanet(Galaxy.IdToPlanet(Cardinal(AbandonedPlanetId), False));
        if AbandonedPlanet <> nil then
          Emit(
              Format(
                  'net client quest after rejoin planet=%d quest=%d holds=%d open=%d holder=%d rejoin=%d',
                  [AbandonedPlanetId, AbandonedPlanet.TextQuestId,
                      Ord(HoldsPlanetQuest(LocalHuman, AbandonedPlanet)), Ord(LocalHuman.TextQuestOpen),
                      Ord(TextQuestHolder(AbandonedPlanet, nil) <> nil), Ord(Report.Rejoin)]
              )
          )
        else
          Emit(Format('net client quest after rejoin planet=%d gone', [AbandonedPlanetId]));
        AbandonedPlanetId := -1;
      end;
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
      // CHANGE: ENHANCEMENT - --sim-net-silent-at: the connection goes silent before this day's
      // turn, as a lost link does: open, but nothing read or written. Without --sim-net-takeover
      // the client waits until the host must have timed it out, then drops the connection; with
      // it, at once, and the frozen one stays open, so the host still counts it. Either way the
      // client reconnects by itself (TNetClient's reconnect) with its token, gets the whole
      // state and plays on (docs/network.md, Tests).
      if (Options.NetSilentAt > 0) and (Days >= Options.NetSilentAt) and not WentSilent
          and (Options.NetQuestDay = 0) then
      begin
        WentSilent := True;
        Client.FreezeConnection;
        Emit(
            Format(
                'net client silent day=%d human=%d takeover=%d tick=%d',
                [Galaxy.CurrentTurn, Client.HumanId, Ord(Options.NetTakeover), GetTickCount64]
            )
        );
        if not Options.NetTakeover then
        begin
          Deadline := GetTickCount64 + QWord(NetSilenceTimeoutMs) + SilentLingerMs;
          while GetTickCount64 < Deadline do
            Sleep(50);
        end;
        Client.LoseConnection(Options.NetTakeover);
        Deadline := GetTickCount64 + StallTimeoutMs;
        Continue;
      end;
      // CHANGE: ENHANCEMENT - --sim-net-cancel-end-turn: the travel continues; it stops here,
      // and the human plays this day.
      if Options.NetCancelEndTurn and (CancelProbes >= 2) and not TravelProbed
          and LocalHuman.ContinueUntilArrival and not HumanHoldsDay(LocalHuman)
          and (LocalPlayer <> nil) and not LocalPlayer.InHyperspace then
      begin
        TravelProbed := True;
        EndTurnContinues := False;
        if not ProbeStopTravel(Client) then
        begin
          Emit('net client failed: the stopped travel');
          Exit(1);
        end;
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
          SetSessionFlagValue(SessionFlagFriendlyFire, not Session.FriendlyFireEnabled);
          Emit(Format('net client session flag friendly-fire=%d', [Ord(Session.FriendlyFireEnabled)]));
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
        // CHANGE: ENHANCEMENT - --sim-net-quest: the quest turn, landed for a planet quest.
        else if (Options.NetQuestDay > 0) and not QuestPlayed and (Days + 1 >= Options.NetQuestDay)
            and ((Options.TextQuest <> '') or (LocalPlayer.CurrentPlanet <> nil)) then
        begin
          QuestPlayed := True;
          case PlayNetQuest(Client, Options, Plan, QuestPlanetId) of
            nqFailed:
              begin
                Emit('net client failed: the text quest');
                Exit(1);
              end;
            nqTurn:
              PlayHumanTurn(LocalHuman, Galaxy.CurrentTurn, Index, Plan);
            nqAbandoned:
              begin
                // The state after the reconnect waits; the turn of its day is played again.
                WentSilent := True;
                AbandonedPlanetId := QuestPlanetId;
                Deadline := GetTickCount64 + StallTimeoutMs;
                Continue;
              end;
          end;
        end
        else if not (EndTurnContinues and PlayFarTravel(LocalHuman, Plan)) then
          PlayHumanTurn(LocalHuman, Galaxy.CurrentTurn, Index, Plan);
        if Options.NetCancelEndTurn and LocalPlayer.InNormalSpace then
          Inc(InSpaceTurns);
        if Options.NetCancelEndTurn then
          Emit(
              Format(
                  'net client turn day=%d plan=%s space=%d hyperspace=%d',
                  [Galaxy.CurrentTurn, Plan, Ord(LocalPlayer.InNormalSpace), Ord(LocalPlayer.InHyperspace)]
              )
          );
        LastPlayedDay := Galaxy.CurrentTurn;
        if Options.NetCancelEndTurn and (CancelProbes < 2) then
        begin
          if not ProbeCancelEndTurn(Client, CancelProbes = 0) then
          begin
            Emit('net client failed: the cancelled end turn');
            Exit(1);
          end;
          Inc(CancelProbes);
          // Then the end turns ask to continue, until a travel has been stopped.
          EndTurnContinues := (CancelProbes >= 2) and not TravelProbed;
        end;
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
    // CHANGE: ENHANCEMENT - Some new games' clients never leave their planet (each takeoff stays
    // landed); then no travel continued to stop.
    if Options.NetCancelEndTurn and not TravelProbed then
      Emit(Format('net client travel cancel untried in-space-turns=%d', [InSpaceTurns]));
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
    EndTurnContinues := False;
    ClientStatusHook := nil;
    ClientTradeTimeoutMs := SavedTradeTimeoutMs;
    StopNetwork;
    NetLogHook := nil;
  end;
end;

end.
