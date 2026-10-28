{$EXCESSPRECISION OFF}
unit HeadlessSim;

// CHANGE: ENHANCEMENT - Headless turn runner and state hash for regression tests.
// Loads a save, parks the player as the observer does, advances turns without
// a window and prints one line per result. The state hash covers the bytes
// TGalaxy.SaveToBuffer writes, so the save writer is the only serialiser.
interface
uses
  aHuman,
  aItem;
const
  // --sim-new-game: the host generates a new game instead of loading a save.
  NewGameSave = '<new game>';
type
  TSimulationOptions = record
    SavePath: AnsiString;
    Turns: Integer;
    Hash: Boolean;
    // Hash only after the last turn, to show that hashing changes nothing.
    HashLastOnly: Boolean;
    RoundTrip: Boolean;
    Seed: Cardinal;
    DumpDirectory: AnsiString;
    // Write a checkpoint after this turn and continue from it (0: never).
    ReloadAt: Integer;
    // The number of humans; the save's human is the first and the others join (0: as saved).
    Humans: Integer;
    // Before each round trip, give the session, the humans, the scripts and an event state
    // that a load without the per-human save block would lose (ProbeSession).
    SessionProbe: Boolean;
    // Print the per-human state at the end (DescribeHumans).
    HumansDump: Boolean;
    // Destroy the local human's ranger and the last human's before this turn and report how
    // they respawn (KillHumans; 0: never).
    KillHumansAt: Integer;
    // Two humans in one star fight, with friendly fire on and then off (RunPvp).
    Pvp: Boolean;
    // Hot-seat: every human plays this many days from its own commands, and each day waits
    // for every human's end turn (RunHotSeat; 0: no).
    HotSeatDays: Integer;
    // CHANGE: ENHANCEMENT - Networked play over loopback (ROADMAP.md, Phase 5; HeadlessNet).
    // The host listens on NetHostPort (0 picks one; -1: no host) and waits for NetClients
    // clients; a client joins NetJoin (host:port) as NetName and leaves after NetLeaveAt days
    // (0: stays to the end).
    NetHostPort: Integer;
    NetClients: Integer;
    NetJoin: AnsiString;
    NetName: AnsiString;
    NetLeaveAt: Integer;
    // CHANGE: ENHANCEMENT - Remote dialogue (docs/network.md, Tests): from this day on, the
    // host's day asks the remote humans of the first star where it can something
    // (HeadlessNet.InstallNetTalkProbe; 0: never). A client with NetTalkLeave leaves when the
    // host asks it something, without answering.
    NetTalkDay: Integer;
    NetTalkLeave: Boolean;
    // CHANGE: ENHANCEMENT - LAN-session checks (docs/network.md, Tests). The host's talk probe
    // sends the day's films before it asks (NetTalkAfterFilm), so the talk comes while a
    // client plays its film; a client plays each film of its star for NetFilmMs (0: none)
    // and keeps a dialogue that comes meanwhile for the film's end. A client with
    // NetCancelJoin cancels its join once the host has let it in, before the state is
    // applied. The host stops hosting after NetStopAt days (0: never), as the in-game menu's
    // Stop hosting does.
    NetTalkAfterFilm: Boolean;
    NetFilmMs: Integer;
    NetCancelJoin: Boolean;
    NetStopAt: Integer;
    // CHANGE: ENHANCEMENT - Silent losses (docs/network.md, Tests): after NetSilentAt days (0:
    // never) a client freezes its connection, so the host must time it out, and then drops it and
    // reconnects by itself; with NetTakeover it reconnects at once with its token, the frozen
    // connection still open, and the host must take its human over.
    NetSilentAt: Integer;
    NetTakeover: Boolean;
    // CHANGE: ENHANCEMENT - Reconnection (docs/network.md, Tests): after NetHostSilentAt days the
    // host freezes every peer for longer than the silence timeout and then drops those left, so
    // that its clients time it out and reconnect; after NetHostExitAt days it freezes them and
    // ends without Bye, so that they cannot. NetReconnectMs (0: NetClient's) is how long a
    // client tries to reconnect.
    NetHostSilentAt: Integer;
    NetHostExitAt: Integer;
    NetReconnectMs: Integer;
    // CHANGE: ENHANCEMENT - A refused command (docs/network.md, Tests): a client buys the good
    // whose whole stock it could pay for (BuyWholeStockGood), and the host, before it applies
    // the queues, buys that stock first in the client's human's name, once: the client's
    // purchase is refused.
    NetBuyRace: Boolean;
    // CHANGE: ENHANCEMENT - Two humans land at one planet and share its equipment stock
    // (RunSharedShop; aShopStock).
    SharedShop: Boolean;
    // CHANGE: ENHANCEMENT - Two humans land at one planet and share its storage
    // (RunSharedStorage; docs/humans.md, Storage).
    SharedStorage: Boolean;
    // CHANGE: ENHANCEMENT - The humans share the government quests (RunSharedQuests;
    // docs/humans.md, Quests).
    SharedQuests: Boolean;
    // CHANGE: ENHANCEMENT - The shared storage between networked humans (HeadlessNet): the
    // host's clients join at its human's planet and on their first day play a scripted storage
    // turn instead of PlayHumanTurn.
    NetStorage: Boolean;
    // CHANGE: ENHANCEMENT - The shared quests between networked humans (HeadlessNet): a client
    // takes a quest and the host's human fulfils it (docs/humans.md, Quests).
    NetSharedQuest: Boolean;
    // CHANGE: ENHANCEMENT - Money transfers between networked humans (HeadlessNet): the host's
    // human and a client each give another human money, and each tries more than it has.
    NetTransfer: Boolean;
    // CHANGE: ENHANCEMENT - Script builtins act for the script's human, on that human's
    // machine (RunScriptRouting).
    ScriptRouting: Boolean;
    // CHANGE: ENHANCEMENT - Two humans send the same command from copies made before either
    // acted; the second is refused before it changes anything (RunStaleCommands).
    StaleCommands: Boolean;
    // CHANGE: ENHANCEMENT - A client submits a command that submits another from inside it;
    // the host must run the inner one once (HeadlessNet).
    NetNested: Boolean;
    // CHANGE: ENHANCEMENT - Trades between humans at one planet (HeadlessNet, docs/network.md,
    // Tests): the host's clients join at its human's planet, and on their first day play a
    // scripted shop turn instead of PlayHumanTurn.
    NetShop: Boolean;
    // CHANGE: ENHANCEMENT - A client takes its end turn back before the host's first day and
    // ends it again, and tries the same once the second day has begun (HeadlessNet; docs/
    // network.md, Tests).
    NetCancelEndTurn: Boolean;
    // CHANGE: ENHANCEMENT - --sim-text-quest=ID|NAME: the save's one human plays this text quest
    // with the headless quest player (RunTextQuest; HeadlessQuest). With --sim-hotseat, the
    // last human plays it on the first day instead of its turn (RunHotSeat).
    TextQuest: AnsiString;
    // CHANGE: ENHANCEMENT - --sim-quest-lock: two humans hold the quest of one planet; one at a
    // time plays it (RunQuestLock).
    QuestLock: Boolean;
    // CHANGE: ENHANCEMENT - --sim-net-quest=DAY (HeadlessNet; docs/progress/
    // 2026-10-19-text-quests-plan.md, Phase C): on its DAY-th turn a client plays a text quest
    // with the headless quest player before its end turn: the planet quest a probe command gives
    // it at its planet, or with TextQuest that quest by name. The host lands every client at the
    // first one's planet, and a replay of its log registers the probe.
    NetQuestDay: Integer;
  end;
function RunHeadlessSimulation(const Options: TSimulationOptions): Integer;
// Shared with the networked runner (HeadlessNet).
procedure Emit(const Line: AnsiString);
procedure LoadSave(const FileName: AnsiString; Seed: Cardinal);
procedure PlayHumanTurn(Human: THuman; Day, Index: Integer; var Plan: AnsiString);
// CHANGE: ENHANCEMENT - Shared with HeadlessNet's shop run (NetShop).
function ShopSlotIndexOf(Human: THuman; Item: TItem): Integer;
function BuyShopItem(Human: THuman; Slot: Integer; Item: TItem): AnsiString;
procedure SellToShop(Human: THuman; Item: TItem);
// CHANGE: ENHANCEMENT - Human puts Item from its hold into its storage and sells it from there,
// as the ship screen does; the ship screen is open (SellToShop left it open).
procedure SellFromStorage(Human: THuman; Item: TItem);
// CHANGE: ENHANCEMENT - Shared with HeadlessNet's storage run (NetStorage). Human opens the ship
// screen of its ranger; puts Item from its hold into the storage where it is, at the first free
// cell, as the ship screen does, and returns the cell; takes the item Id from the storage cell
// Slot into its hand, '' when it did, else the refusal's reason; puts what it holds back into
// the storage cell Slot.
procedure OpenOwnShipScreen(Human: THuman);
function StoreFromHold(Human: THuman; Item: TItem): Integer;
function TakeFromStorage(Human: THuman; Slot: Integer; Id: Integer): AnsiString;
procedure StoreHeldAt(Human: THuman; Slot: Integer);
function IsTradedBack(Item: TItem): Boolean;
// CHANGE: ENHANCEMENT - Gives Human a government planet quest to Planet (a TPlanet whose
// TextQuestId is set), as AcceptQuest gives the offer; shared with HeadlessNet's quest probe.
procedure GiveProbePlanetQuest(Human: THuman; Planet: TObject);
// CHANGE: ENHANCEMENT - Human, the local one, plays the text quest Name headless and ends its
// turn unless it owes the quest's days; shared with HeadlessNet's host quest (Phase D of the
// text quests plan).
procedure PlayQuestTurn(Human: THuman; const Name: AnsiString; Seed: Cardinal; var Plan: AnsiString);
var
  // CHANGE: ENHANCEMENT - PlayHumanTurn buys one unit of the good with the smallest stock the
  // human could buy whole, when there is one (NetBuyRace).
  BuyWholeStockGood: Boolean;
implementation
uses
  SysUtils,
  Classes,
  Math,
  aConst,
  aHoldActions,
  EC_Buf,
  EC_Expression,
  Globals,
  GlobalsV,
  aMyFunction,
  aGalaxy,
  aGalaxyEvent,
  aGalaxyStruct,
  aHold,
  aCommands,
  aDialogActions,
  aShopActions,
  aStationActions,
  aPlanetActions,
  aRuins,
  EC_Struct,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aObjectRefs,
  aRanger,
  aScript,
  aScriptFun,
  aShip,
  aShopStock,
  aTalkActions,
  aUiScriptActions,
  SimEvents,
  aSaveLoad,
  aSession,
  SaveTrace,
  ThreadCalc,
  aMissile,
  WorkerErrors,
  ObserverHooks,
  ObserverSimulation,
  fGameSettings,
  fIntroduction,
  HeadlessQuest,
  QuestPage,
  QuestRun,
  aQuestActions,
  CheatCode;

var
  // Where each object starts in the state being dumped (SaveTrace).
  TraceLines: TStringList;

procedure RecordTrace(const Kind: AnsiString; Id: Cardinal; Offset: Integer);
begin
  TraceLines.Add(Format('%d %s:%d', [Offset, Kind, Id]));
end;

procedure Emit(const Line: AnsiString);
begin
  WriteLn(Line);
  Flush(Output);
end;

procedure DumpBuffer(const Directory, Name: AnsiString; Buffer: TBufEC);
var
  Stream: TFileStream;
begin
  if Directory = '' then
    Exit;
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(Directory) + Name, fmCreate);
  try
    Stream.WriteBuffer(Buffer.Data^, Buffer.DataSize);
  finally
    Stream.Free
  end;
end;

procedure EmitHash(Turn: Integer; const DumpDirectory: AnsiString);
var
  State: TBufEC;
begin
  if DumpDirectory <> '' then
  begin
    TraceLines := TStringList.Create;
    SaveTraceHook := @RecordTrace;
  end;
  try
    State := SerializeGalaxyState;
  finally
    SaveTraceHook := nil;
  end;
  try
    DumpBuffer(DumpDirectory, Format('turn-%.4d.bin', [Turn]), State);
    if TraceLines <> nil then
      TraceLines.SaveToFile(
          IncludeTrailingPathDelimiter(DumpDirectory) + Format('turn-%.4d.index', [Turn])
      );
    Emit(
        Format(
            'turn %d day=%d hash=%s bytes=%d unresolved=%d',
            [Turn, Galaxy.CurrentTurn, IntToHex(HashBytes(State.Data, State.DataSize), 16),
                State.DataSize, UnresolvedObjectCount]
        )
    );
  finally
    FreeAndNil(TraceLines);
    State.Free
  end;
end;

// Decodes a save file into its game-state and film payloads, as LoadGameFromFile reads them.
procedure ReadSavePayloads(const FileName: AnsiString; State, Films: TBufEC);
var
  Stream: TFileStream;
  Raw: TBufEC;
  I, Size, Seed: Integer;
  Crc: Cardinal;
begin
  Raw := TBufEC.Create;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      Raw.SetSize(Stream.Size);
      Stream.ReadBuffer(Raw.Data^, Stream.Size);
    finally
      Stream.Free
    end;
    Raw.SetPosition(0);
    for I := 1 to 8 do
      Raw.ReadWideString;
    for I := 1 to 2 do
    begin
      Size := Raw.GetInt32;
      Raw.SetPosition(Raw.Position + Size);
    end;
    Crc := Raw.GetUInt32;
    Seed := Raw.GetInt32;
    Size := Raw.GetInt32;
    State.SetSize(Size);
    Raw.ReadBytes(State.Data, Size);
    State.ApplyDatXorCipher(Seed);
    if State.ComputeCrc32 <> Crc then
      raise Exception.Create('Integrity check failed: ' + FileName);
    State.ExpandZlibPayloadInPlace;
    Size := Raw.DataSize - Raw.Position;
    Films.SetSize(Size);
    if Size > 0 then
    begin
      Raw.ReadBytes(Films.Data, Size);
      Films.ExpandZlibPayloadInPlace;
    end;
  finally
    Raw.Free
  end;
end;

function FirstDifference(A, B: TBufEC): Integer;
var
  I, Size: Integer;
begin
  Size := A.DataSize;
  if B.DataSize < Size then
    Size := B.DataSize;
  for I := 0 to Size - 1 do
    if PByte(A.Data)[I] <> PByte(B.Data)[I] then
      Exit(I);
  if A.DataSize = B.DataSize then
    Result := -1
  else
    Result := Size;
end;

function ComparePayload(const Name: AnsiString; Expected, Actual: TBufEC): Boolean;
var
  Offset: Integer;
begin
  Offset := FirstDifference(Expected, Actual);
  Result := Offset < 0;
  if Result then
    Emit(Format('roundtrip %s=ok bytes=%d', [Name, Expected.DataSize]))
  else
    Emit(
        Format(
            'roundtrip %s=diff offset=%d expected=%d actual=%d',
            [Name, Offset, Expected.DataSize, Actual.DataSize]
        )
    );
end;

// The new-game screen's defaults, on the generation thread as the introduction runs it.
procedure GenerateNewGame;
var
  I: Integer;
begin
  FilmHistory.Clear;
  NewGameGenerationThread := TThreadCreateNewGame.Create;
  try
    NewGameGenerationThread.PlayerName := 'Host';
    NewGameGenerationThread.PlayerRace := 2;
    NewGameGenerationThread.CharacterPreset := 3;
    for I := 0 to 7 do
      NewGameGenerationThread.DifficultyLevels[I] := 1;
    NewGameGenerationThread.StartingItemTypes[0] := 43;
    NewGameGenerationThread.StartingItemTypes[1] := 44;
    NewGameGenerationThread.StartingSkills[0] := 0;
    NewGameGenerationThread.StartingSkills[1] := 3;
    NewGameGenerationThread.Start;
    while NewGameGenerationThread.IsRunning do
      Sleep(10);
    if NewGameGenerationStage <> 8 then
      raise Exception.Create('New game generation failed');
  finally
    FreeAndNil(NewGameGenerationThread);
  end;
end;

procedure LoadSave(const FileName: AnsiString; Seed: Cardinal);
begin
  if FileName = NewGameSave then
    GenerateNewGame
  else if not LoadGameFromFile(UTF8Decode(FileName)) then
    raise Exception.Create('Load failed: ' + UTF8Encode(LastSaveLoadError));
  WaitForTurnCalculation;
  // TGalaxy.Create reseeds the shared stream from the clock; pin it so that
  // call sites still on the shared stream repeat between runs.
  System.RandSeed := Integer(Seed);
  SeedChaoticRandom(Seed);
end;

// The save and load counters would differ between the two files; write the
// values the galaxy was loaded with.
procedure SaveUnchanged(const FileName: AnsiString);
begin
  Dec(Galaxy.SaveCount);
  Dec(Galaxy.LoadCount);
  try
    if not SaveGameToFile(UTF8Decode(FileName), 'roundtrip') then
      raise Exception.Create('Save failed: ' + UTF8Encode(LastSaveLoadError));
  finally
    Inc(Galaxy.LoadCount);
  end;
end;

// Loading logs a SaveLoaded event; drop the one the round trip's load added.
procedure DropSaveLoadedEvent;
var
  Event: TGalaxyEvent;
begin
  if Galaxy.GalaxyEvents.Count = 0 then
    Exit;
  Event := TGalaxyEvent(Galaxy.GalaxyEvents.Last);
  if Event.EventType <> 'SaveLoaded' then
    raise Exception.Create('Load did not log SaveLoaded as the last galaxy event');
  Galaxy.GalaxyEvents.Extract(Event);
  Event.Free;
end;

function TextHash(const Text: WideString): AnsiString;
begin
  Result := IntToHex(HashBytes(PByte(PWideChar(Text)), Length(Text) * SizeOf(WideChar)), 8);
end;

function ShipIdOf(Ship: TObject): Integer;
begin
  if Ship = nil then
    Result := 0
  else
    Result := TShip(Ship).Id;
end;

// One line for the session flags, one per human with the state the save keeps for it, one
// per script with the human it is bound to, and one per event that names a human. The local
// human's automatic control, dialogue count, broken equipment and weapon panel are in no
// save, only in checkpoints, so they are left out for that human.
procedure DescribeHumans(Lines: TStrings);
var
  I, J: Integer;
  Human: THuman;
  Line, Part: AnsiString;
  Message: TMessagePlayer;
  OldQuest: PPlayerOldQuest;
  Slot: TShopStockSlot;
  Entry: TPlayerHoldUnit;
  Event: TGalaxyEvent;
begin
  Lines.Add(Format('session friendly-fire=%d', [Ord(Session.FriendlyFireEnabled)]));
  Lines.Add(Format('session cheats=%d', [Ord(Session.CheatsAllowed)]));
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Line := Format('human %d id=%d local=%d', [I, Human.Id, Ord(Human = LocalHuman)]);
    if Human.PlayerStar <> nil then
      Line := Line + Format(' star=%d', [Human.PlayerStar.Id])
    else
      Line := Line + ' star=0';
    Line := Line + Format(
        ' follow=%d tips=%d',
        [ShipIdOf(Human.PendingPlayerFollowTarget), Human.ShownPlayerTips]
    );
    if Human <> LocalHuman then
      Line := Line + Format(
          ' auto=%d broken=%d dialogues=%d panel=%d',
          [Ord(Human.PlayerAutomaticControl), Ord(Human.PlayerEquipmentBrokenThisTurn),
              Human.PlayerDialogueRequestCount, Ord(Human.StarMapWeaponPanelOpen)]
      );
    Part := '';
    for J := 0 to 8 do
      Part := Part + IntToStr(Human.HangarShipIds[J]) + ',';
    Line := Line + ' hangar=' + Part;
    Part := '';
    if Human.PlayerHoldEntries <> nil then
      for J := 0 to Human.PlayerHoldEntries.Count - 1 do
      begin
        Entry := TPlayerHoldUnit(Human.PlayerHoldEntries[J]);
        Part := Part + Format('%d:%d:%d,', [Ord(Entry.Kind), Entry.GoodsIndex, Entry.ItemId]);
      end;
    Line := Line + ' hold=' + Part;
    Part := '';
    Message := Human.FirstPersistentPlayerMessage;
    while Message <> nil do
    begin
      // A load renews the local human's storage bubbles (TPlayer.RefreshStorageBubbles),
      // which dates them to the loaded day.
      if Human = LocalHuman then
        Part := Part + Format('%s:%d:', [TextHash(Message.Key), Message.Kind])
      else
        Part := Part + Format('%s:%d:%d:', [TextHash(Message.Key), Message.Kind, Message.Turn]);
      Part := Part + Format('%s:%d,', [TextHash(Message.Text), Ord(Message.WasRead)]);
      Message := Message.Next;
    end;
    Line := Line + ' bubbles=' + Part;
    Part := '';
    if Human.PlayerOldQuests <> nil then
      for J := 0 to Human.PlayerOldQuests.Count - 1 do
      begin
        OldQuest := PPlayerOldQuest(Human.PlayerOldQuests[J]);
        if OldQuest.Planet <> nil then
          Part := Part + IntToStr(OldQuest.Planet.Id);
        Part := Part + Format(
            ':%d:%d:%s:%d:%d,',
            [Ord(OldQuest.QuestType), OldQuest.QuestNumber, TextHash(OldQuest.Description),
                Ord(OldQuest.Successful), Ord(OldQuest.Declined)]
        );
      end;
    Line := Line + ' quests=' + Part;
    Part := '';
    if Human.TemporaryShopSlots <> nil then
    begin
      if Human.TemporaryShopPlanet <> nil then
        Part := Format('planet %d:', [Human.TemporaryShopPlanet.Id])
      else if Human.TemporaryShopStation <> nil then
        Part := Format('station %d:', [Human.TemporaryShopStation.Id]);
      for J := 0 to Human.TemporaryShopSlots.Count - 1 do
      begin
        Slot := TShopStockSlot(Human.TemporaryShopSlots[J]);
        Part := Part + Format('%d.%d', [Slot.GridPoint.X, Slot.GridPoint.Y]);
        if Slot.Item <> nil then
          Part := Part + Format('=%d/%d', [Slot.Item.Id, Ord(Slot.Item.ItemType)]);
        Part := Part + ',';
      end;
    end;
    Line := Line + ' shop=' + Part;
    Part := IntToStr(Human.CheatPoints) + ':';
    for J := 0 to High(Human.UsedCheats) do
      Part := Part + UTF8Encode(Human.UsedCheats[J]) + ',';
    Line := Line + ' cheats=' + Part;
    Line := Line + Format(' finished=%d:%d', [Ord(Human.Finished), Human.FinishReason]);
    Line := Line + Format(' quest-days=%d', [Human.QuestDaysOwed]);
    Lines.Add(Line);
  end;
  for I := 0 to Galaxy.Scripts.Count - 1 do
    Lines.Add(
        Format(
            'script %d %s human=%d',
            [I, UTF8Encode(TScript(Galaxy.Scripts[I]).ScriptFileName),
                TScript(Galaxy.Scripts[I]).HumanId]
        )
    );
  for I := 0 to Galaxy.GalaxyEvents.Count - 1 do
  begin
    Event := TGalaxyEvent(Galaxy.GalaxyEvents[I]);
    if Event.HumanId <> -1 then
      Lines.Add(
          Format('event %d %s human=%d', [I, UTF8Encode(Event.EventType), Event.HumanId])
      );
  end;
end;

// CHANGE: ENHANCEMENT - The cheat probe (docs/network.md, Tests): the last human enters EXPA by
// command with cheats allowed, which must give its ranger the experience and put the cheat on
// its record; then the session turns cheats off, and a second EXPA must be refused in
// multiplayer (single player ignores the flag). The flag stays off.
procedure ProbeCheats;
var
  Human: THuman;
  Command: TPlayerCommand;
  Before: Integer;
  Outcome: AnsiString;
begin
  if Session.Humans.Count = 0 then
    Exit;
  Human := Session.Humans[Session.Humans.Count - 1];
  if Human.Player = nil then
    Exit;
  SetSessionFlagValue(SessionFlagCheats, True);
  Before := Human.Player.FreeExperience;
  Command := NewCheatCommand('EXPA');
  Command.Actor := Cardinal(Human.Id);
  SubmitCommand(Command);
  if (Human.Player.FreeExperience = Before + 1000000) and Human.HasUsedCheat('EXPA') then
    Outcome := 'applied'
  else
    Outcome := 'failed';
  SetSessionFlagValue(SessionFlagCheats, False);
  Before := Human.Player.FreeExperience;
  Command := NewCheatCommand('EXPA');
  Command.Actor := Cardinal(Human.Id);
  try
    SubmitCommand(Command);
    if Human.Player.FreeExperience = Before + 1000000 then
      Outcome := Outcome + ' off=applied'
    else
      Outcome := Outcome + ' off=failed';
  except
    on E: ECommandRefused do
      if Human.Player.FreeExperience = Before then
        Outcome := Outcome + ' off=refused'
      else
        Outcome := Outcome + ' off=failed';
  end;
  Emit(
      Format(
          'probe cheat human=%d multiplayer=%d on=%s points=%d',
          [Human.Id, Ord(IsMultiplayer), Outcome, Human.CheatPoints]
      )
  );
end;

// Gives the session, the humans, the scripts and an event state that a load without the
// per-human save block would lose: the flags, set by command, a cheat and text-quest days
// owed for every human, the other humans' THuman state with a shop for those who are landed,
// scripts bound to every human in turn, and the last event bound to the last human. With more than one human, the
// last one's game ends, as a script's EndGame ends it, and a command it issues must be
// refused.
procedure ProbeSession;
var
  I: Integer;
  Human: THuman;
  OldQuest: PPlayerOldQuest;
  Entry: TPlayerHoldUnit;
  Command: TPlayerCommand;
begin
  SetSessionFlagValue(SessionFlagFriendlyFire, False);
  // CHANGE: ENHANCEMENT - A cheat command of the last human runs for that human while the
  // session allows cheats, and is refused in multiplayer once the host turns them off; the
  // flag stays off for the round trip.
  ProbeCheats;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Human.RecordCheat('Probe' + WideString(IntToStr(Human.Id)), I + 1);
    Human.QuestDaysOwed := I + 1;
    if Human = LocalHuman then
      Continue;
    Human.PendingPlayerFollowTarget := LocalPlayer;
    Human.PlayerAutomaticControl := True;
    Human.PlayerEquipmentBrokenThisTurn := True;
    Human.PlayerDialogueRequestCount := 3;
    Human.ShownPlayerTips := Cardinal(Human.Id) xor $5A5A;
    Human.StarMapWeaponPanelOpen := True;
    Human.HangarShipIds[4] := Human.Id;
    if Human.PlayerHoldEntries = nil then
      InitializePlayerHoldView(Human);
    Entry := TPlayerHoldUnit.Create;
    Entry.Kind := phkGoods;
    Entry.GoodsIndex := 2;
    Human.PlayerHoldEntries.Add(Entry);
    Human.AddOrUpdateBubble(0, Galaxy.CurrentTurn, 'Probe ' + WideString(IntToStr(I)), 'probe');
    New(OldQuest);
    OldQuest.Planet := Human.Player.CurrentPlanet;
    OldQuest.QuestType := qtPlanetQuest;
    OldQuest.QuestNumber := I;
    OldQuest.Description := 'Probe';
    OldQuest.Successful := True;
    OldQuest.Declined := False;
    Human.PlayerOldQuests.Add(OldQuest);
    if Human.Player.CurrentPlanet <> nil then
      BuildTemporaryShopSlotGrid(Human);
  end;
  for I := 0 to Galaxy.Scripts.Count - 1 do
    TScript(Galaxy.Scripts[I]).HumanId := Session.Humans[I mod Session.Humans.Count].Id;
  if Galaxy.GalaxyEvents.Count > 0 then
    TGalaxyEvent(Galaxy.GalaxyEvents.Last).HumanId :=
        Session.Humans[Session.Humans.Count - 1].Id;
  if Session.Humans.Count > 1 then
  begin
    Human := Session.Humans[Session.Humans.Count - 1];
    FinishHuman(Human, 7);
    Command := NewCommand(ckSetSessionFlag);
    Command.Actor := Cardinal(Human.Id);
    AddInt(Command, SessionFlagFriendlyFire);
    AddInt(Command, 1);
    SubmitCommand(Command);
    if not Session.FriendlyFireEnabled then
      Emit(Format('probe finished human=%d command=refused', [Human.Id]))
    else
      Emit(Format('probe finished human=%d command=applied', [Human.Id]));
  end;
end;

// Save, load that save, and compare the state before and after in hashable
// form. A save made by the game can differ from its re-save, because loading
// recomputes derived values such as the average ranger capital, so the
// comparison starts from a loaded game.
function CheckRoundTrip(const DumpDirectory: AnsiString; Seed: Cardinal): Boolean;
var
  Before, After, FirstState, FirstFilms, SecondState, SecondFilms: TBufEC;
  First, Second: AnsiString;
  HumansBefore, HumansAfter: TStringList;
  I: Integer;
begin
  HumansBefore := TStringList.Create;
  HumansAfter := TStringList.Create;
  Before := nil;
  After := nil;
  FirstState := TBufEC.Create;
  FirstFilms := TBufEC.Create;
  SecondState := TBufEC.Create;
  SecondFilms := TBufEC.Create;
  First := GetTempDir(False) + 'rangers-roundtrip-' + IntToStr(GetProcessID) + '-1.sav';
  Second := GetTempDir(False) + 'rangers-roundtrip-' + IntToStr(GetProcessID) + '-2.sav';
  try
    Before := SerializeGalaxyState;
    SaveUnchanged(First);
    // As saved: saving puts the local human's hold in order first.
    DescribeHumans(HumansBefore);
    LoadSave(First, Seed);
    DropSaveLoadedEvent;
    After := SerializeGalaxyState;
    DescribeHumans(HumansAfter);
    SaveUnchanged(Second);
    ReadSavePayloads(First, FirstState, FirstFilms);
    ReadSavePayloads(Second, SecondState, SecondFilms);
    DumpBuffer(DumpDirectory, 'roundtrip-before.bin', Before);
    DumpBuffer(DumpDirectory, 'roundtrip-after.bin', After);
    Result := ComparePayload('galaxy', Before, After);
    Result := ComparePayload('films', FirstFilms, SecondFilms) and Result;
    // The per-human state field by field: the state hash leaves out what only the screens
    // use, and the local human's state that the save keeps outside the galaxy.
    I := 0;
    while (I < HumansBefore.Count) and (I < HumansAfter.Count)
        and (HumansBefore[I] = HumansAfter[I]) do
      Inc(I);
    if (I = HumansBefore.Count) and (I = HumansAfter.Count) then
      Emit(Format('roundtrip humans=ok lines=%d', [HumansBefore.Count]))
    else
    begin
      Result := False;
      Emit(Format('roundtrip humans=diff line=%d', [I]));
      if I < HumansBefore.Count then
        Emit('  expected ' + HumansBefore[I]);
      if I < HumansAfter.Count then
        Emit('  actual   ' + HumansAfter[I]);
    end;
  finally
    HumansBefore.Free;
    HumansAfter.Free;
    DeleteFile(First);
    DeleteFile(Second);
    Before.Free;
    After.Free;
    FirstState.Free;
    FirstFilms.Free;
    SecondState.Free;
    SecondFilms.Free;
  end;
end;

// Adds humans until there are Total, each landed at an inhabited coalition planet in a star
// that holds no other human (FindJoinPlanet). The choice depends only on the galaxy, so runs
// repeat. Each joins by command, so a command log replays it.
procedure JoinHumans(Total: Integer);
var
  Planet: TPlanet;
  Human: THuman;
begin
  while Session.Humans.Count < Total do
  begin
    Planet := FindJoinPlanet;
    if Planet = nil then
      raise Exception.Create('Not enough coalition planets for the humans');
    Human := JoinHumanAt(
        Planet,
        'Human' + WideString(IntToStr(Session.Humans.Count + 1)),
        1 + Session.Humans.Count mod 5
    );
    Emit(Format('human id=%d star=%d planet=%d', [Human.Id, Planet.CurrentStar.Id, Planet.Id]));
  end;
end;

// A checkpoint must give back a game that plays on as the one it was written from.
procedure ReloadFromCheckpoint;
var
  Buffer: TBufEC;
begin
  Buffer := TBufEC.Create;
  try
    WriteGameCheckpoint(Buffer);
    Buffer.SetPosition(0);
    ReadGameCheckpoint(Buffer);
  finally
    Buffer.Free
  end;
  Emit(Format('reloaded day=%d', [Galaxy.CurrentTurn]));
end;

// What a human keeps through death and respawn: its money, and its items by count and ids.
function HumanBelongings(Player: TPlayer): AnsiString;
var
  I: Integer;
  Ids: Int64;
begin
  Ids := 0;
  for I := 0 to Player.Inventory.Count - 1 do
    Inc(Ids, TItem(Player.Inventory[I]).Id);
  for I := 0 to Player.Artefacts.Count - 1 do
    Inc(Ids, TItem(Player.Artefacts[I]).Id);
  Result := Format(
      'money=%d items=%d:%d cargo-free=%d',
      [Player.Money, Player.Inventory.Count + Player.Artefacts.Count, Ids,
          Player.GetCargoFreeSpace]
  );
end;

// Destroys the local human's ranger and the last human's, as damage does (ROADMAP.md,
// Phase 4, item 9). The day that follows respawns them in multiplayer. The planets of the
// last human's star turn hostile to it first, so that it respawns in another star.
procedure KillHumans(Killed: TList);
var
  I, J: Integer;
  Human: THuman;
  Star: TStar;
begin
  Killed.Clear;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human <> LocalHuman) and (I <> Session.Humans.Count - 1) then
      Continue;
    Killed.Add(Pointer(PtrInt(Human.Id)));
    Emit(
        Format(
            'kill human id=%d local=%d star=%d %s',
            [Human.Id, Ord(Human = LocalHuman), Human.Player.CurrentStar.Id,
                HumanBelongings(Human.Player)]
        )
    );
    if (Human <> LocalHuman) and (Human.Player.CurrentPlanet <> nil) then
    begin
      Star := Human.Player.CurrentStar;
      for J := 0 to Star.Planets.Count - 1 do
        TPlanet(Star.Planets[J]).SetRelationLevelToRanger(Human.Player, rlHostile);
    end;
    Human.Player.GetHull.HullPoints := 0;
    Human.Player.RecordHumanDeath('KilledByExplosion');
  end;
end;

// Where each killed human is after the day: still a human, landed at a planet, repaired,
// with what it had.
procedure ReportRespawns(Killed: TList);
var
  I: Integer;
  Human: THuman;
  Player: TPlayer;
  Planet: Integer;
begin
  for I := 0 to Killed.Count - 1 do
  begin
    Human := FindHuman(Integer(PtrInt(Killed[I])));
    if (Human = nil) or (Human.Player = nil) then
    begin
      Emit(Format('respawn human id=%d present=0', [Integer(PtrInt(Killed[I]))]));
      Continue;
    end;
    Player := Human.Player;
    if Player.CurrentPlanet <> nil then
      Planet := Player.CurrentPlanet.Id
    else
      Planet := 0;
    Emit(
        Format(
            'respawn human id=%d present=1 star=%d playerstar=%d planet=%d hull=%d/%d %s',
            [Human.Id, Player.CurrentStar.Id, Human.PlayerStar.Id, Planet,
                Player.GetHull.HullPoints, Player.GetHull.Weight, HumanBelongings(Player)]
        )
    );
  end;
end;

var
  // The two humans of RunPvp, and what the attacker's hits on the target did.
  PvpAttacker, PvpTarget: TPlayer;
  PvpHits, PvpDamage: Integer;

// Counts the weapon and missile hits of PvpAttacker on PvpTarget (ObserverHit).
procedure RecordPvpHit(
    Star, Source, Target, Weapon: TObject;
    Damage: Integer;
    Color: Cardinal;
    Kind: Integer
);
begin
  if Source is TMissile then
    Source := TMissile(Source).OwnerShip;
  if (Kind in [0, 1]) and (Source = PvpAttacker) and (Target = PvpTarget) then
  begin
    Inc(PvpHits);
    if Damage > 0 then
      Inc(PvpDamage, Damage);
  end;
end;

// A human's command, as that human's machine would send it.
procedure SubmitAs(Player: TPlayer; var Command: TPlayerCommand);
begin
  Command.Actor := Cardinal(Player.Id);
  SubmitCommand(Command);
end;

// The weapons of Attacker aimed at Target.
function CountWeaponsAt(Attacker, Target: TShip): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Attacker.WeaponCount do
    if TObject(Attacker.Weapons[I].Target) = Target then
      Inc(Result);
end;

// One day in space, as the star map's end turn runs it for the local human.
procedure SimulateSpaceDay;
begin
  ApplyPendingOrders;
  BeginSpaceDay;
  StartPlayerStarTurnCalculation;
  WaitForTurnCalculation;
  RaisePendingWorkerError;
  if (LocalPlayer <> nil) and not LocalPlayer.InHyperspace then
  begin
    StartGalaxyTurnCalculation;
    WaitForTurnCalculation;
    RaisePendingWorkerError;
  end;
end;

// Humans as targets (ROADMAP.md, Phase 4, item 8). The local human (the attacker) and a
// second human, who joins at a planet in its star, take off, and the attacker orders an auto
// battle on the other. With friendly fire on, its hits must do damage. Then friendly fire goes
// off by command: the attack order must be gone at once, new attack orders refused, and neither
// the attacker's weapons (aimed by hand every day, as a target left from before would be) nor a
// direct hit may do damage. The other humans, up to Options.Humans, join elsewhere.
function RunPvp(const Options: TSimulationOptions): Integer;
const
  MaximumDays = 12;
  OffDays = 3;
var
  Planet: TPlanet;
  Star: TStar;
  I, Day, Direct, InRange: Integer;
  Command: TPlayerCommand;
  Color: Cardinal;
  Flags: Dword;
begin
  Result := 0;
  PvpAttacker := LocalPlayer;
  if (PvpAttacker = nil) or PvpAttacker.InHyperspace or (PvpAttacker.WeaponCount = 0) then
  begin
    Emit('pvp skipped: the local human is in hyperspace or has no weapons');
    Exit;
  end;
  Star := PvpAttacker.CurrentStar;
  Planet := nil;
  for I := 0 to Star.Planets.Count - 1 do
    if TPlanet(Star.Planets[I]).OwnerId <= Byte(oiGaal) then
    begin
      Planet := TPlanet(Star.Planets[I]);
      Break;
    end;
  if Planet = nil then
  begin
    Emit('pvp skipped: no inhabited planet in the star');
    Exit;
  end;
  PvpTarget := JoinHuman(Planet, 'Target', 2).Player;
  JoinHumans(Options.Humans);
  Emit(
      Format(
          'pvp attacker=%d target=%d star=%d humans=%d',
          [PvpAttacker.Id, PvpTarget.Id, Star.Id, Session.Humans.Count]
      )
  );
  ObserverHit := @RecordPvpHit;
  try
    if not PvpAttacker.InNormalSpace then
    begin
      Command := NewCommand(ckTakeoff);
      AddInt(Command, tfEndAutomaticControl);
      SubmitAs(PvpAttacker, Command);
    end;
    Command := NewCommand(ckTakeoff);
    AddInt(Command, tfEndAutomaticControl);
    SubmitAs(PvpTarget, Command);
    // Both leave the planets; an auto battle needs both in space.
    SimulateSpaceDay;
    // Friendly fire on, the default: the attack goes ahead.
    Command := NewCommand(ckOrderAutoBattle);
    AddRef(Command, PvpTarget);
    SubmitAs(PvpAttacker, Command);
    Emit(
        Format(
            'pvp on order=%d select=%d',
            [Ord(LocalHuman.PendingPlayerFollowTarget = PvpTarget),
                Ord(PvpAttacker.CanSelectShipTarget(PvpTarget))]
        )
    );
    PvpHits := 0;
    PvpDamage := 0;
    Day := 0;
    while (Day < MaximumDays) and (PvpDamage = 0) and (HumanOf(PvpTarget) <> nil) do
    begin
      SimulateSpaceDay;
      Inc(Day);
    end;
    Emit(
        Format(
            'pvp friendly-fire=1 days=%d hits=%d damage=%d target-hull=%d/%d',
            [Day, PvpHits, PvpDamage, PvpTarget.GetHull.HullPoints, PvpTarget.GetHull.Weight]
        )
    );
    if (PvpDamage = 0) or (HumanOf(PvpTarget) = nil) then
    begin
      Emit('pvp failed: no damage with friendly fire on');
      Exit(1);
    end;
    // Friendly fire off, by command: the attack order goes at once.
    PvpTarget.GetHull.HullPoints := PvpTarget.GetHull.Weight;
    SetSessionFlagValue(SessionFlagFriendlyFire, False);
    Emit(
        Format(
            'pvp off order=%d weapons=%d follow-mode=%d',
            [Ord(LocalHuman.PendingPlayerFollowTarget <> nil),
                CountWeaponsAt(PvpAttacker, PvpTarget), PvpAttacker.OrderStateData]
        )
    );
    // New attack orders are refused.
    Command := NewCommand(ckOrderAutoBattle);
    AddRef(Command, PvpTarget);
    SubmitAs(PvpAttacker, Command);
    Command := NewCommand(ckSetWeaponTarget);
    AddRef(Command, PvpTarget);
    AddInt(Command, 1);
    SubmitAs(PvpAttacker, Command);
    Command := NewCommand(ckOrderFollow);
    AddRef(Command, PvpTarget);
    AddInt(Command, 1);
    SubmitAs(PvpAttacker, Command);
    Emit(
        Format(
            'pvp refused order=%d weapons=%d select=%d follow-mode=%d',
            [Ord(LocalHuman.PendingPlayerFollowTarget <> nil),
                CountWeaponsAt(PvpAttacker, PvpTarget),
                Ord(PvpAttacker.CanSelectShipTarget(PvpTarget)), PvpAttacker.OrderStateData]
        )
    );
    if (LocalHuman.PendingPlayerFollowTarget <> nil)
        or (CountWeaponsAt(PvpAttacker, PvpTarget) > 0)
        or PvpAttacker.CanSelectShipTarget(PvpTarget)
        or (PvpAttacker.OrderStateData <> 0) then
    begin
      Emit('pvp failed: an attack order on a human stands with friendly fire off');
      Exit(1);
    end;
    // The attacker stays close (the follow order above) and aims by hand every day.
    PvpHits := 0;
    PvpDamage := 0;
    InRange := 0;
    for Day := 1 to OffDays do
    begin
      if HumanOf(PvpTarget) = nil then
        Break;
      for I := 1 to PvpAttacker.WeaponCount do
      begin
        PvpAttacker.Weapons[I].Target := PvpTarget;
        if PointDistanceSquared(PvpAttacker.Position, PvpTarget.Position)
            <= Sqr(PvpAttacker.GetWeaponRange(PvpAttacker.Weapons[I])) then
          Inc(InRange);
      end;
      SimulateSpaceDay;
    end;
    // A direct hit, as splash damage around another target lands.
    Direct := PvpTarget.ApplyWeaponHit(PvpAttacker, PvpAttacker.Weapons[1], -1, Color, Flags, 1, 0);
    Emit(
        Format(
            'pvp friendly-fire=0 days=%d in-range=%d hits=%d damage=%d direct=%d target-hull=%d/%d',
            [OffDays, InRange, PvpHits, PvpDamage, Direct, PvpTarget.GetHull.HullPoints,
                PvpTarget.GetHull.Weight]
        )
    );
    if (PvpHits > 0) or (Direct <> 0) then
    begin
      Emit('pvp failed: a human hurt another with friendly fire off');
      Exit(1);
    end;
    // Out of range, the days above would show nothing.
    if InRange = 0 then
    begin
      Emit('pvp failed: the attacker never had the target in range');
      Exit(1);
    end;
    Emit('pvp ok');
  finally
    ObserverHit := nil;
  end;
end;

// A human's command, sent as that human.
procedure SubmitFor(Human: THuman; var Command: TPlayerCommand);
begin
  Command.Actor := Cardinal(Human.Id);
  SubmitCommand(Command);
end;

procedure SubmitKindFor(Human: THuman; Kind: TCommandKind);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  SubmitFor(Human, Command);
end;

// CHANGE: ENHANCEMENT - A purchase of goods as the goods screen sends it (aShopActions.TradeGoods):
// a refusal is only logged. On a networked client the host answers a trade before it runs here,
// and refuses one another human made stale (docs/network.md, Trades); the turn goes on.
procedure SubmitGoodsFor(Human: THuman; var Command: TPlayerCommand);
begin
  try
    SubmitFor(Human, Command);
  except
    on E: ECommandRefused do
      Emit('trade refused: ' + E.Message);
  end;
end;

// Buys one unit of the first good the planet sells that the ranger can pay and carry. The
// goods screen checks the same before it sends the command.
function BuyOneGood(Human: THuman): Boolean;
var
  P: TPlayer;
  Good, Best: Byte;
  Command: TPlayerCommand;
  Cost, BestCost: Int64;
begin
  Result := False;
  P := Human.Player;
  if (P.CurrentPlanet = nil) or (P.CurrentPlanet.OwnerId > Byte(oiGaal)) then
    Exit;
  if P.GetCargoFreeSpace < 1 then
    Exit;
  if BuyWholeStockGood then
  begin
    Best := 255;
    BestCost := 0;
    for Good := 0 to 7 do
      if P.GetLocationGoodsEntry(Good).Count >= 1 then
      begin
        Cost := Int64(P.GetLocationGoodsEntry(Good).Count) * P.ShopGoodsPurchasePrice(Good, nil);
        if (Cost <= P.Money) and ((Best = 255) or (Cost < BestCost)) then
        begin
          Best := Good;
          BestCost := Cost;
        end;
      end;
    if Best <> 255 then
    begin
      Command := NewCommand(ckTradeGoods);
      AddRef(Command, nil);
      AddInt(Command, Best);
      AddInt(Command, 1);
      AddInt(Command, 0);
      SubmitGoodsFor(Human, Command);
      Exit(True);
    end;
  end;
  for Good := 0 to 7 do
    if (P.GetLocationGoodsEntry(Good).Count >= 1)
        and (P.ShopGoodsPurchasePrice(Good, nil) <= P.Money) then
    begin
      Command := NewCommand(ckTradeGoods);
      AddRef(Command, nil);
      AddInt(Command, Good);
      AddInt(Command, 1);
      AddInt(Command, 0);
      SubmitGoodsFor(Human, Command);
      Exit(True);
    end;
end;

// The inhabited planet of the human's star to head for on Day, or nil.
function TargetPlanet(Human: THuman; Day: Integer): TPlanet;
var
  I, Count, Pick: Integer;
  Star: TStar;
begin
  Result := nil;
  Star := Human.Player.CurrentStar;
  Count := 0;
  for I := 0 to Star.Planets.Count - 1 do
    if TPlanet(Star.Planets[I]).OwnerId <= Byte(oiGaal) then
      Inc(Count);
  if Count = 0 then
    Exit;
  Pick := (Day + Human.Id) mod Count;
  for I := 0 to Star.Planets.Count - 1 do
    if TPlanet(Star.Planets[I]).OwnerId <= Byte(oiGaal) then
    begin
      if Pick = 0 then
        Exit(TPlanet(Star.Planets[I]));
      Dec(Pick);
    end;
end;

// One human's turn on Day, as its screens would send it: landed, it buys a good on some days
// and takes off on others; docked at a station it takes off; in space, idle, it flies toward
// a planet or lands on one; then it ends its turn. What it did goes into Plan.
procedure PlayHumanTurn(Human: THuman; Day, Index: Integer; var Plan: AnsiString);
var
  P: TPlayer;
  Planet: TPlanet;
  Command: TPlayerCommand;
  Target: TPointF;
begin
  P := Human.Player;
  if P.CurrentPlanet <> nil then
  begin
    if BuyOneGood(Human) then
      Plan := Plan + 'b';
    if (Day + Index) mod 3 <> 0 then
    begin
      // The shop's stock goes back, as the screens give it back on leaving (fPanelRuins); a
      // shop left open in space does not survive a load (TGalaxy.LoadFromBuffer).
      Command := NewCommand(ckTakeoff);
      AddInt(Command, tfEndAutomaticControl or tfReturnShopStock);
      SubmitFor(Human, Command);
      Plan := Plan + 't';
    end
    else
    begin
      SubmitKindFor(Human, ckPruneMessages);
      Plan := Plan + 'w';
    end;
  end
  else if P.DockedTo <> nil then
  begin
    Command := NewCommand(ckTakeoff);
    AddInt(Command, tfEndAutomaticControl or tfReturnShopStock);
    SubmitFor(Human, Command);
    Plan := Plan + 't';
  end
  else if P.InNormalSpace then
  begin
    if P.Order = soNone then
    begin
      Planet := TargetPlanet(Human, Day);
      if Planet = nil then
      begin
        Target := MakePointF(P.Position.X / 2, P.Position.Y / 2);
        Command := NewCommand(ckOrderMove);
        AddPoint(Command, Target);
        AddInt(Command, mfClearPending);
        SubmitFor(Human, Command);
        Plan := Plan + 'f';
      end
      else if (Day + Index) mod 2 = 0 then
      begin
        // Halfway to the planet.
        Target := Planet.GetPosition;
        Target := MakePointF((P.Position.X + Target.X) / 2, (P.Position.Y + Target.Y) / 2);
        Command := NewCommand(ckOrderMove);
        AddPoint(Command, Target);
        AddInt(Command, mfClearPending);
        SubmitFor(Human, Command);
        Plan := Plan + 'f';
      end
      else
      begin
        Command := NewCommand(ckOrderLand);
        AddRef(Command, Planet);
        AddPoint(Command, MakePointF(0, 0));
        SubmitFor(Human, Command);
        Plan := Plan + 'l';
      end;
    end
    else
      Plan := Plan + '-';
    SubmitKindFor(Human, ckApplyPendingOrders);
    SubmitKindFor(Human, ckBeginSpaceDay);
  end
  else
    Plan := Plan + 'h';
  Command := NewCommand(ckEndTurn);
  AddInt(Command, 0);
  SubmitFor(Human, Command);
end;

// CHANGE: ENHANCEMENT - The quest human's first hot-seat day (docs/progress/
// 2026-10-19-text-quests-plan.md, Phase B): it plays the text quest Name with the headless
// quest player, as the local human (the run's commands are the local human's), and ends its
// turn only when the quest owes no day: in multiplayer the quest passes no galaxy day, and
// a human who owes days does not hold the day.
procedure PlayQuestTurn(Human: THuman; const Name: AnsiString; Seed: Cardinal; var Plan: AnsiString);
var
  Player: THeadlessQuestPlayer;
  Outcome: TQuestRunOutcome;
  Command: TPlayerCommand;
begin
  Player := THeadlessQuestPlayer.Create(Seed);
  try
    Outcome := Player.Play(UTF8Decode(Name));
    Emit(
        Format(
            'quest done name=%s outcome=%s pages=%d steps=%d days=%d errors=%d respawned=%d',
            [Name, QuestOutcomeName(Outcome), Player.Pages, Player.Steps,
                Player.Run.DaysElapsed, Player.Errors, Ord(Player.Run.Respawned)]
        )
    );
  finally
    Player.Free;
  end;
  Plan := Plan + 'q';
  if Human.Player = nil then
    Exit;
  Emit(
      Format(
          'quest owed day=%d human=%d days=%d holds=%d open=%d',
          [Galaxy.CurrentTurn, Human.Id, Human.QuestDaysOwed, Ord(HumanHoldsDay(Human)),
              Ord(Human.TextQuestOpen)]
      )
  );
  if HumanHoldsDay(Human) then
  begin
    Command := NewCommand(ckEndTurn);
    AddInt(Command, 0);
    SubmitFor(Human, Command);
  end;
end;

// Hot-seat without a window (ROADMAP.md, Phase 4, test plan): every day each human who holds
// the day plays its turn in Session.Humans order, each from its own commands; the day starts
// only when none holds it. With --record-commands the log splits into one log per human
// (tools/split_commands.py), and the merged replay of those must reach the same hash.
// CHANGE: ENHANCEMENT - With --sim-text-quest, the last human is the local one and plays the
// quest on the first day (PlayQuestTurn); the days go on, at least HotSeatDays, until it has
// paid the days the quest owes and played two more. Each day after the quest says what it
// owes and whether it holds the day.
function RunHotSeat(const Options: TSimulationOptions): Integer;
var
  Day, I, Waits, Early, Holders, PlayedAfter: Integer;
  Human, QuestHuman: THuman;
  Plan: AnsiString;
begin
  Result := 0;
  Waits := 0;
  Early := 0;
  CurrentScreenId := screenPlanet;
  RequestedScreenId := screenNone;
  QuestHuman := nil;
  PlayedAfter := 0;
  if (Options.TextQuest <> '') and (Session.Humans.Count > 1) then
  begin
    QuestHuman := Session.Humans[Session.Humans.Count - 1];
    SetLocalHuman(QuestHuman);
  end;
  Day := 0;
  while (Day < Options.HotSeatDays)
      or ((QuestHuman <> nil) and (PlayedAfter < 2) and (Day < Options.HotSeatDays + 400)) do
  begin
    Inc(Day);
    Plan := '';
    Holders := 0;
    for I := 0 to Session.Humans.Count - 1 do
      if HumanHoldsDay(Session.Humans[I]) then
        Inc(Holders);
    I := 0;
    while I < Session.Humans.Count do
    begin
      Human := Session.Humans[I];
      Inc(I);
      if not HumanHoldsDay(Human) then
      begin
        Plan := Plan + '.';
        Continue;
      end;
      if (Human = QuestHuman) and (Day = 1) then
        PlayQuestTurn(Human, Options.TextQuest, Options.Seed, Plan)
      else
      begin
        if (Human = QuestHuman) and (Day > 1) then
          Inc(PlayedAfter);
        PlayHumanTurn(Human, Day, I, Plan);
      end;
      Dec(Holders);
      // Its end turn counts, and the day still waits for every human after it.
      if HumanHoldsDay(Human) then
        Inc(Waits);
      if (Holders > 0) and AllHumansEndedTurn then
        Inc(Early);
    end;
    if not AllHumansEndedTurn then
    begin
      Emit(Format('hotseat failed: day %d cannot start after every human ended the turn', [Day]));
      Exit(1);
    end;
    StartPlayerStarTurnCalculation;
    WaitForTurnCalculation;
    RaisePendingWorkerError;
    if (LocalPlayer <> nil) and not LocalPlayer.InHyperspace then
    begin
      StartGalaxyTurnCalculation;
      WaitForTurnCalculation;
      RaisePendingWorkerError;
    end;
    if AllHumansEndedTurn and (Session.Humans.Count > 0) then
      Inc(Early);
    if Options.Hash then
      Emit(
          Format(
              'hotseat day=%d plan=%s hash=%s',
              [Galaxy.CurrentTurn, Plan, IntToHex(GalaxyStateHash, 16)]
          )
      );
    if (QuestHuman <> nil) and (QuestHuman.Player <> nil) then
      Emit(
          Format(
              'quest owed day=%d human=%d days=%d holds=%d open=%d',
              [Galaxy.CurrentTurn, QuestHuman.Id, QuestHuman.QuestDaysOwed,
                  Ord(HumanHoldsDay(QuestHuman)), Ord(QuestHuman.TextQuestOpen)]
          )
      )
    else if QuestHuman <> nil then
      // No ranger to play for (it left the game in the quest): the days stop.
      PlayedAfter := 2;
  end;
  if (Waits > 0) or (Early > 0) then
  begin
    Emit(Format('hotseat failed: barrier held=%d released-early=%d', [Waits, Early]));
    Result := 1;
  end
  else
    Emit('hotseat barrier ok');
  Emit(
      Format(
          'done hotseat days=%d humans=%d day=%d hash=%s',
          [Day, Session.Humans.Count, Galaxy.CurrentTurn, IntToHex(GalaxyStateHash, 16)]
      )
  );
end;

// '' when every open shop grid shows only items of its location's list and no list holds an
// item twice; otherwise what is wrong.
function CheckShopViews: AnsiString;
var
  I, J, K: Integer;
  Human: THuman;
  List: TList;
  Slot: TShopStockSlot;
begin
  Result := '';
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if Human.TemporaryShopSlots = nil then
      Continue;
    List := ShopStockOf(ShopViewLocation(Human));
    if List = nil then
      Exit(Format('human %d has a grid at no shop', [Human.Id]));
    for J := 0 to List.Count - 1 do
      for K := J + 1 to List.Count - 1 do
        if List[J] = List[K] then
          Exit(Format('item %d is twice in the stock', [TItem(List[J]).Id]));
    for J := 0 to Human.TemporaryShopSlots.Count - 1 do
    begin
      Slot := TShopStockSlot(Human.TemporaryShopSlots[J]);
      if (Slot.Item <> nil) and (List.IndexOf(Slot.Item) < 0) then
        Exit(
            Format(
                'human %d shows item %d, which the stock does not hold',
                [Human.Id, Slot.Item.Id]
            )
        );
    end;
  end;
end;

// Whether the human's grid shows its location's list in order, with nothing left out.
function ShowsWholeStock(Human: THuman): Boolean;
var
  I, Index: Integer;
  List: TList;
  Item: TItem;
begin
  Result := False;
  if Human.TemporaryShopSlots = nil then
    Exit;
  List := ShopStockOf(ShopViewLocation(Human));
  Index := 0;
  for I := 0 to Human.TemporaryShopSlots.Count - 1 do
  begin
    Item := TShopStockSlot(Human.TemporaryShopSlots[I]).Item;
    if Item = nil then
      Continue;
    if (Index >= List.Count) or (List[Index] <> Pointer(Item)) then
      Exit;
    Inc(Index);
  end;
  Result := Index = List.Count;
end;

function ShopSlotIndexOf(Human: THuman; Item: TItem): Integer;
var
  I: Integer;
begin
  Result := -1;
  if Human.TemporaryShopSlots <> nil then
    for I := 0 to Human.TemporaryShopSlots.Count - 1 do
      if TShopStockSlot(Human.TemporaryShopSlots[I]).Item = Item then
        Exit(I);
end;

// The items of the planet's shop and of the two humans' holds and storage, in Count; '' when
// none is in two places.
function CountSharedShopItems(Planet: TPlanet; A, B: THuman; out Count: Integer): AnsiString;
var
  Items: TList;
  I, J: Integer;
  Human: THuman;
begin
  Result := '';
  Items := TList.Create;
  try
    for I := 0 to Planet.EquipmentShop.Count - 1 do
      Items.Add(Planet.EquipmentShop[I]);
    for I := 0 to 1 do
    begin
      if I = 0 then
        Human := A
      else
        Human := B;
      for J := 0 to Human.Player.Inventory.Count - 1 do
        Items.Add(Human.Player.Inventory[J]);
      for J := 0 to Human.Player.Artefacts.Count - 1 do
        Items.Add(Human.Player.Artefacts[J]);
      // CHANGE: ENHANCEMENT - The humans share one storage pool: it is counted once.
      if (I = 1) and (B.Player.StorageEntries = A.Player.StorageEntries) then
        Continue;
      for J := 0 to Human.Player.StorageEntries.Count - 1 do
        if PStorageEntry(Human.Player.StorageEntries[J]).Item <> nil then
          Items.Add(PStorageEntry(Human.Player.StorageEntries[J]).Item);
    end;
    Count := Items.Count;
    for I := 0 to Items.Count - 1 do
      for J := I + 1 to Items.Count - 1 do
        if Items[I] = Items[J] then
          Exit(Format('item %d is in two places', [TItem(Items[I]).Id]));
  finally
    Items.Free;
  end;
end;

// Human buys Item from the slot Slot; '' when it bought it, else the refusal's reason.
function BuyShopItem(Human: THuman; Slot: Integer; Item: TItem): AnsiString;
var
  Command: TPlayerCommand;
begin
  Result := '';
  Command := NewCommand(ckBuyEquipment);
  AddInt(Command, Slot);
  AddInt(Command, Item.Id);
  try
    SubmitFor(Human, Command);
  except
    on E: ECommandRefused do
      Result := RefusalReasonName(E.Reason);
  end;
end;

// Human sells Item from its hold back to the shop, as the ship screen does.
procedure SellToShop(Human: THuman; Item: TItem);
var
  Command: TPlayerCommand;
  I, Index: Integer;
begin
  Command := NewCommand(ckOpenShipScreen);
  AddRef(Command, Human.Player);
  AddInt(Command, 0);
  SubmitFor(Human, Command);
  SubmitKindFor(Human, ckRefreshHoldView);
  Index := -1;
  for I := 0 to Human.PlayerHoldEntries.Count - 1 do
    if TPlayerHoldUnit(Human.PlayerHoldEntries[I]).Item = Item then
      Index := I;
  if Index < 0 then
    raise Exception.Create('The item to sell is not in the hold');
  Command := NewCommand(ckTakeHoldEntry);
  AddInt(Command, Index);
  AddInt(Command, 0);
  SubmitFor(Human, Command);
  Command := NewCommand(ckSellHeld);
  AddInt(Command, 1);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitFor(Human, Command);
end;

procedure SellFromStorage(Human: THuman; Item: TItem);
var
  Command: TPlayerCommand;
  I, Index, Slot: Integer;
  Owner: TObject;
begin
  SubmitKindFor(Human, ckRefreshHoldView);
  Index := -1;
  for I := 0 to Human.PlayerHoldEntries.Count - 1 do
    if TPlayerHoldUnit(Human.PlayerHoldEntries[I]).Item = Item then
      Index := I;
  if Index < 0 then
    raise Exception.Create('The item to store is not in the hold');
  Command := NewCommand(ckTakeHoldEntry);
  AddInt(Command, Index);
  AddInt(Command, 0);
  SubmitFor(Human, Command);
  Owner := GetLocalStorageOwner(Human);
  Slot := 0;
  while Human.Player.FindStorageIndexByLocationAndSlot(Owner, Slot) >= 0 do
    Inc(Slot);
  Command := NewCommand(ckStoreHeld);
  AddInt(Command, Slot);
  AddInt(Command, 1);
  SubmitFor(Human, Command);
  Index := Human.Player.FindStorageIndexByLocationAndSlot(Owner, Slot);
  if (Index < 0) or (PStorageEntry(Human.Player.StorageEntries[Index]).Item <> Item) then
    raise Exception.Create('The item did not go into the storage');
  Command := NewCommand(ckSellStoredItem);
  AddInt(Command, Index);
  AddInt(Command, Item.Id);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitFor(Human, Command);
end;

// An item of the shop the test can buy and sell back: equipment the shop takes back (the
// ship screen's sale rule), no hull or weapon, and no script.
function IsTradedBack(Item: TItem): Boolean;
begin
  Result := (Item.ItemType in [t_Hull..t_CustomWeapon])
      and not (Item is THull)
      and not (Item is TWeapon)
      and (Item.ScriptItem = nil)
      and (Item.OwnerId in [Ord(oiMaloc)..Ord(oiGaal), Ord(oiPirate)]);
end;

// CHANGE: ENHANCEMENT - Two humans in one shop (aShopStock): the stock is the planet's and
// each human's grid is a view of it. A save loads with its open grids' items back in their
// shops. Two humans join at one planet and open its shop: both see the whole stock. The first
// buys an item; the second's purchase of it is refused (item gone), and its purchase of a later
// item, by the slot its grid showed before, goes through. The first sells its item back and
// the second buys it. No item is lost or in two places, and a round trip keeps both grids.
function RunSharedShop(const Options: TSimulationOptions): Integer;
var
  I, J, Before, After, SlotX, SlotY, Grids, AId, BId: Integer;
  Star: TStar;
  Planet, Candidate: TPlanet;
  A, B: THuman;
  X, Y: TItem;
  Command: TPlayerCommand;
  Problem, Reason: AnsiString;

  procedure Fail(const Text: AnsiString);
  begin
    Emit('shared shop failed: ' + Text);
    raise EAbort.Create(Text);
  end;

  procedure Open(Human: THuman);
  begin
    Command := NewCommand(ckOpenShopStock);
    AddInt(Command, ShopVisibleColumnCount);
    SubmitFor(Human, Command);
  end;

  // Two tradable items, X before Y in the shop's order, that both humans can carry together.
  function FindPair: Boolean;
  var
    K, L, Space: Integer;
    List: TList;
  begin
    Result := False;
    List := Planet.EquipmentShop;
    Space := Min(A.Player.GetCargoFreeSpace, B.Player.GetCargoFreeSpace);
    for K := 0 to List.Count - 1 do
      for L := K + 1 to List.Count - 1 do
        if IsTradedBack(TItem(List[K]))
            and IsTradedBack(TItem(List[L]))
            and (TItem(List[K]).Weight + TItem(List[L]).Weight <= Space) then
        begin
          X := TItem(List[K]);
          Y := TItem(List[L]);
          Exit(True);
        end;
  end;

begin
  Result := 0;
  try
    // The save's open grids, the local one in the original layout, went back to their shops.
    Grids := 0;
    for I := 0 to Session.Humans.Count - 1 do
      if Session.Humans[I].TemporaryShopSlots <> nil then
        Inc(Grids);
    Problem := CheckShopViews;
    if Problem <> '' then
      Fail('after the load: ' + Problem);
    for I := 0 to Session.Humans.Count - 1 do
      if (Session.Humans[I].TemporaryShopSlots <> nil)
          and not ShowsWholeStock(Session.Humans[I]) then
        Fail('a loaded grid does not show its shop');
    Emit(Format('shared shop loaded grids=%d ok', [Grids]));
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      for J := 0 to Star.Planets.Count - 1 do
      begin
        Candidate := TPlanet(Star.Planets[J]);
        if (Planet = nil)
            and (Candidate.OwnerId <= Byte(oiGaal))
            and (Candidate.EquipmentShop.Count >= 6) then
          Planet := Candidate;
      end;
    end;
    if Planet = nil then
      Fail('no planet with a shop');
    A := JoinHumanAt(Planet, 'ShopA', 1);
    B := JoinHumanAt(Planet, 'ShopB', 2);
    if (A = nil) or (B = nil) then
      Fail('the humans did not join');
    // Money and room for what they trade: a new ranger's hold is small.
    A.Player.SetMoney(10000000);
    B.Player.SetMoney(10000000);
    Inc(A.Player.GetHull.Weight, 1000);
    Inc(B.Player.GetHull.Weight, 1000);
    A.Player.RefreshDerivedStats(True);
    B.Player.RefreshDerivedStats(True);
    Open(A);
    Open(B);
    if not FindPair then
      Fail('no two items to trade');
    Problem := CountSharedShopItems(Planet, A, B, Before);
    if Problem <> '' then
      Fail(Problem);
    // (a) Both see the whole stock.
    if not ShowsWholeStock(A) or not ShowsWholeStock(B) then
      Fail('a grid does not show the whole stock');
    Emit(
        Format(
            'shared shop planet=%d items=%d both see the stock',
            [Planet.Id, Planet.EquipmentShop.Count]
        )
    );
    // (b) A buys X; B's purchase of X is refused, and of Y by its old slot goes through.
    SlotX := ShopSlotIndexOf(B, X);
    SlotY := ShopSlotIndexOf(B, Y);
    Reason := BuyShopItem(A, ShopSlotIndexOf(A, X), X);
    if Reason <> '' then
      Fail('the first purchase was refused: ' + Reason);
    if (Planet.EquipmentShop.IndexOf(X) >= 0) or (A.Player.Inventory.IndexOf(X) < 0) then
      Fail('the bought item did not move to the buyer');
    if ShopSlotIndexOf(A, X) >= 0 then
      Fail('the buyer still shows the item');
    if (ShopSlotIndexOf(B, X) >= 0) or not ShowsWholeStock(B) then
      Fail('the other human''s grid was not rebuilt');
    Reason := BuyShopItem(B, SlotX, X);
    if Reason <> RefusalReasonName(rrItemGone) then
      Fail('the purchase of the sold item was not refused as gone: ' + Reason);
    if ShopSlotIndexOf(B, Y) = SlotY then
      Fail('the later item did not move');
    Reason := BuyShopItem(B, SlotY, Y);
    if Reason <> '' then
      Fail('the purchase by the old slot was refused: ' + Reason);
    if (Planet.EquipmentShop.IndexOf(Y) >= 0) or (B.Player.Inventory.IndexOf(Y) < 0) then
      Fail('the item bought by its old slot did not move to the buyer');
    Emit(
        Format(
            'shared shop bought item=%d again=%s slot=%d moved ok',
            [X.Id, RefusalReasonName(rrItemGone), SlotY]
        )
    );
    // (c) A sells X back; B sees it and buys it.
    SellToShop(A, X);
    if (Planet.EquipmentShop.IndexOf(X) < 0) or (A.Player.Inventory.IndexOf(X) >= 0) then
      Fail('the sold item is not back in the shop');
    if (ShopSlotIndexOf(B, X) < 0) or not ShowsWholeStock(B) then
      Fail('the other human does not see the sold item');
    Reason := BuyShopItem(B, ShopSlotIndexOf(B, X), X);
    if Reason <> '' then
      Fail('the purchase of the sold item was refused: ' + Reason);
    if (Planet.EquipmentShop.IndexOf(X) >= 0) or (B.Player.Inventory.IndexOf(X) < 0) then
      Fail('the item bought again did not move to the buyer');
    Emit('shared shop sold back and bought again ok');
    // (d) Nothing lost or in two places.
    Problem := CountSharedShopItems(Planet, A, B, After);
    if Problem <> '' then
      Fail(Problem);
    if After <> Before then
      Fail(Format('the items went from %d to %d', [Before, After]));
    Problem := CheckShopViews;
    if Problem <> '' then
      Fail(Problem);
    Emit(Format('shared shop items before=%d after=%d ok', [Before, After]));
    // (e) Both grids survive a round trip; the second names its items by id.
    AId := A.Id;
    BId := B.Id;
    // A load computes the rangers' wealth again; the trades changed it outside a day.
    Galaxy.RefreshRangerWealthStats;
    Galaxy.RefreshRangerRatingPlaces;
    if not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
      Fail('round trip');
    A := FindHuman(AId);
    B := FindHuman(BId);
    if (A = nil) or (B = nil) then
      Fail('a human is missing after the round trip');
    if not ShowsWholeStock(A) or not ShowsWholeStock(B) then
      Fail('a grid does not show the whole stock after the round trip');
    Problem := CheckShopViews;
    if Problem <> '' then
      Fail('after the round trip: ' + Problem);
    Emit('shared shop ok');
  except
    on E: EAbort do
      Result := 1;
  end;
end;

procedure OpenOwnShipScreen(Human: THuman);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOpenShipScreen);
  AddRef(Command, Human.Player);
  AddInt(Command, 0);
  SubmitFor(Human, Command);
end;

function StoreFromHold(Human: THuman; Item: TItem): Integer;
var
  Command: TPlayerCommand;
  I, Index: Integer;
  Owner: TObject;
begin
  SubmitKindFor(Human, ckRefreshHoldView);
  Index := -1;
  for I := 0 to Human.PlayerHoldEntries.Count - 1 do
    if TPlayerHoldUnit(Human.PlayerHoldEntries[I]).Item = Item then
      Index := I;
  if Index < 0 then
    raise Exception.Create('The item to store is not in the hold');
  Command := NewCommand(ckTakeHoldEntry);
  AddInt(Command, Index);
  AddInt(Command, 0);
  SubmitFor(Human, Command);
  Owner := GetLocalStorageOwner(Human);
  Result := 0;
  while Human.Player.FindStorageIndexByLocationAndSlot(Owner, Result) >= 0 do
    Inc(Result);
  StoreHeldAt(Human, Result);
end;

function TakeFromStorage(Human: THuman; Slot: Integer; Id: Integer): AnsiString;
var
  Command: TPlayerCommand;
begin
  Result := '';
  Command := NewCommand(ckTakeStored);
  AddInt(Command, Slot);
  AddInt(Command, Id);
  try
    SubmitFor(Human, Command);
  except
    on E: ECommandRefused do
      Result := RefusalReasonName(E.Reason);
  end;
end;

procedure StoreHeldAt(Human: THuman; Slot: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckStoreHeld);
  AddInt(Command, Slot);
  AddInt(Command, 1);
  SubmitFor(Human, Command);
end;

// CHANGE: ENHANCEMENT - The storage at a planet is one pool for every human (docs/humans.md,
// Storage). A loaded save's humans share one list. Two humans join at one planet: they share
// it too. The first buys two items and stores them; the second sees both in its storage there
// and takes the first; the first's take of it, by the cell and the id its copy showed, is
// refused (item gone); the second puts it back. A save with a storage of its own for one human
// (one made before the pool) loads with it merged into the pool, a cell taken twice moved to the
// next free one. No item is lost or in two places, and a round trip keeps the pool.
function RunSharedStorage(const Options: TSimulationOptions): Integer;
var
  I, J, SlotX, SlotY, AId, BId, PlanetId, XId, YId: Integer;
  Star: TStar;
  Planet, Candidate: TPlanet;
  A, B: THuman;
  X, Y: TItem;
  Command: TPlayerCommand;
  Reason, MergePath: AnsiString;
  Own: TStorageList;
  Pool: TList;
  Entry: PStorageEntry;

  procedure Fail(const Text: AnsiString);
  begin
    Emit('shared storage failed: ' + Text);
    raise EAbort.Create(Text);
  end;

  // Every human's ranger uses the first one's storage list.
  function AllShare: Boolean;
  var
    K: Integer;
  begin
    Result := True;
    for K := 1 to Session.Humans.Count - 1 do
      if (Session.Humans[K].Player <> nil)
          and (Session.Humans[K].Player.StorageEntries <> Session.Humans[0].Player.StorageEntries) then
        Exit(False);
  end;

  // The storage cell at Planet that holds the item with that id, -1 for none; twice is an error.
  function StoredSlot(Id: Integer): Integer;
  var
    K: Integer;
    Stored: PStorageEntry;
  begin
    Result := -1;
    for K := 0 to Session.Humans[0].Player.StorageEntries.Count - 1 do
    begin
      Stored := Session.Humans[0].Player.StorageEntries[K];
      if (Stored.Item <> nil) and (Integer(Stored.Item.Id) = Id) then
      begin
        if Result >= 0 then
          Fail(Format('item %d is stored twice', [Id]));
        if Stored.LocationOwner = Planet then
          Result := Stored.SlotIndex
        else
          Result := -2;
      end;
    end;
  end;

  // Whether Human's storage cell Slot at Planet shows the item with that id.
  function Shows(Human: THuman; Slot, Id: Integer): Boolean;
  var
    Index: Integer;
  begin
    Index := Human.Player.FindStorageIndexByLocationAndSlot(Planet, Slot);
    Result := (Index >= 0)
        and (Integer(PStorageEntry(Human.Player.StorageEntries[Index]).Item.Id) = Id);
  end;

  function FindPair: Boolean;
  var
    K, L, Space: Integer;
    List: TList;
  begin
    Result := False;
    List := Planet.EquipmentShop;
    Space := A.Player.GetCargoFreeSpace;
    for K := 0 to List.Count - 1 do
      for L := K + 1 to List.Count - 1 do
        if IsTradedBack(TItem(List[K]))
            and IsTradedBack(TItem(List[L]))
            and (TItem(List[K]).Weight + TItem(List[L]).Weight <= Space) then
        begin
          X := TItem(List[K]);
          Y := TItem(List[L]);
          Exit(True);
        end;
  end;

begin
  Result := 0;
  try
    if not AllShare then
      Fail('the loaded humans do not share one storage');
    Emit(Format('shared storage loaded humans=%d shared=1', [Session.Humans.Count]));
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      for J := 0 to Star.Planets.Count - 1 do
      begin
        Candidate := TPlanet(Star.Planets[J]);
        if (Planet = nil)
            and (Candidate.OwnerId <= Byte(oiGaal))
            and (Candidate.EquipmentShop.Count >= 6) then
          Planet := Candidate;
      end;
    end;
    if Planet = nil then
      Fail('no planet with a shop');
    A := JoinHumanAt(Planet, 'StoreA', 1);
    B := JoinHumanAt(Planet, 'StoreB', 2);
    if (A = nil) or (B = nil) then
      Fail('the humans did not join');
    if not AllShare then
      Fail('the joined humans do not share the storage');
    A.Player.SetMoney(10000000);
    Inc(A.Player.GetHull.Weight, 1000);
    A.Player.RefreshDerivedStats(True);
    Command := NewCommand(ckOpenShopStock);
    AddInt(Command, ShopVisibleColumnCount);
    SubmitFor(A, Command);
    if not FindPair then
      Fail('no two items to buy');
    XId := X.Id;
    YId := Y.Id;
    Reason := BuyShopItem(A, ShopSlotIndexOf(A, X), X);
    if Reason = '' then
      Reason := BuyShopItem(A, ShopSlotIndexOf(A, Y), Y);
    if Reason <> '' then
      Fail('a purchase was refused: ' + Reason);
    SubmitKindFor(A, ckReturnShopStock);
    // (a) A stores both; B sees them in its storage there.
    OpenOwnShipScreen(A);
    OpenOwnShipScreen(B);
    SlotX := StoreFromHold(A, X);
    SlotY := StoreFromHold(A, Y);
    if (StoredSlot(XId) <> SlotX) or (StoredSlot(YId) <> SlotY) then
      Fail('the stored items are not in the storage');
    if not Shows(B, SlotX, XId) or not Shows(B, SlotY, YId) then
      Fail('the other human does not see the stored items');
    Emit(Format('shared storage stored x=%d y=%d other-sees=1', [XId, YId]));
    // (b) B takes X; A's take of it, by the cell its copy showed, is refused.
    Reason := TakeFromStorage(B, SlotX, XId);
    if Reason <> '' then
      Fail('the take was refused: ' + Reason);
    if (B.SelectedHoldItem = nil) or (Integer(B.SelectedHoldItem.Id) <> XId) or (StoredSlot(XId) <> -1) then
      Fail('the taken item is not in the taker''s hand');
    if Shows(A, SlotX, XId) then
      Fail('the first human still sees the taken item');
    Reason := TakeFromStorage(A, SlotX, XId);
    if Reason <> RefusalReasonName(rrItemGone) then
      Fail('the second take of the item was not refused as gone: ' + Reason);
    if A.SelectedHoldKind <> phkEmpty then
      Fail('the refused take changed the first human''s hand');
    // A take of Y by X's old cell names the wrong item there: refused as well.
    Reason := TakeFromStorage(A, SlotY, XId);
    if Reason <> RefusalReasonName(rrItemGone) then
      Fail('a take naming another item in the cell was not refused: ' + Reason);
    StoreHeldAt(B, SlotX);
    if (B.SelectedHoldKind <> phkEmpty) or (StoredSlot(XId) <> SlotX) or not Shows(A, SlotX, XId) then
      Fail('the item put back is not in the storage');
    Emit(Format('shared storage race taken=%d again=%s back=1', [XId, RefusalReasonName(rrItemGone)]));
    for I := 0 to 1 do
    begin
      Command := NewCommand(ckCloseShipScreen);
      AddInt(Command, 0);
      if I = 0 then
        SubmitFor(A, Command)
      else
        SubmitFor(B, Command);
    end;
    // (c) A save in which B has a storage of its own (made before the pool): X is in it, in Y's
    // cell. It loads with X merged into the pool, in another cell.
    AId := A.Id;
    BId := B.Id;
    PlanetId := Planet.Id;
    Pool := B.Player.StorageEntries;
    Own := TStorageList.Create;
    Dec(TStorageList(Pool).Sharers);
    B.Player.StorageEntries := Own;
    for I := Pool.Count - 1 downto 0 do
    begin
      Entry := Pool[I];
      if (Entry.Item <> nil) and (Integer(Entry.Item.Id) = XId) then
      begin
        Pool.Delete(I);
        Entry.SlotIndex := SlotY;
        Own.Add(Entry);
      end;
    end;
    Galaxy.RefreshRangerWealthStats;
    Galaxy.RefreshRangerRatingPlaces;
    MergePath := GetTempDir(False) + 'rangers-storage-' + IntToStr(GetProcessID) + '.sav';
    try
      SaveUnchanged(MergePath);
      LoadSave(MergePath, Options.Seed);
    finally
      DeleteFile(MergePath);
    end;
    A := FindHuman(AId);
    B := FindHuman(BId);
    Planet := TPlanet(Galaxy.IdToPlanet(PlanetId, False));
    if (A = nil) or (B = nil) or (Planet = nil) then
      Fail('a human or the planet is missing after the load');
    if not AllShare then
      Fail('the loaded humans do not share one storage');
    SlotX := StoredSlot(XId);
    SlotY := StoredSlot(YId);
    if (SlotX < 0) or (SlotY < 0) or (SlotX = SlotY) then
      Fail(Format('the merged storage holds x at %d and y at %d', [SlotX, SlotY]));
    Emit(Format('shared storage merged x-slot=%d y-slot=%d', [SlotX, SlotY]));
    // (d) The pool survives a round trip.
    if not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
      Fail('round trip');
    A := FindHuman(AId);
    if (A = nil) or not AllShare then
      Fail('the humans do not share one storage after the round trip');
    Emit('shared storage ok');
  except
    on E: EAbort do
      Result := 1;
  end;
end;

// CHANGE: ENHANCEMENT - --sim-shared-quests (docs/humans.md, Quests). Human A joins at a
// planet P and takes a letter quest to a planet Q of another star, where human B joined: every
// human's journal shows it. A's letter goes to B (by the storage, in play) and B delivers it:
// A's quest is done, the reward is split equally (B gets what does not divide), every human
// gets the whole experience, the journal's completion, the finished quest and the relation to
// Q. A takes another quest from P: a third human at P is refused a quest there (the government
// gave its quest), and so is its AcceptQuest of an earlier offer (offer-gone). The quest's
// deadline passes: it fails once, for every human (journal, finished quest, relation to P). A
// round trip keeps every human's finished quests.
function RunSharedQuests(const Options: TSimulationOptions): Integer;
var
  I, J, Number, Reward, Share, Count, AId: Integer;
  Star: TStar;
  P, Q, Candidate: TPlanet;
  A, B, C, Human: THuman;
  Item, Letter: TItem;
  Before, Experience, OldCounts: array of Integer;
  Name, Key, Text, Expected: WideString;
  Offer: TQuest;
  Reason: AnsiString;
  Quest: PPlayerOldQuest;

  procedure Fail(const Text: AnsiString);
  begin
    Emit('shared quests failed: ' + Text);
    raise EAbort.Create(Text);
  end;

  function LetterName(N: Integer): WideString;
  begin
    Result := LocalizedColorText('Quest.SendLetter.' + IntToStr(N) + '.SysName');
  end;

  procedure SetOffer(Human: THuman; N, Money: Integer);
  begin
    FillChar(Offer, SizeOf(Offer), 0);
    Offer.QuestType := qtSendLetter;
    Offer.QuestNumber := N;
    Offer.Planet := P;
    Offer.DeadlineTurn := Galaxy.CurrentTurn + 50;
    Offer.RewardMoney := Money;
    Offer.ObjectiveTarget := Q;
    Offer.Successful := False;
    Human.GovernmentQuestOffer := Offer;
  end;

  // Whether every human's journal has the entry Key of that kind.
  function AllHaveEntry(Kind: Byte): Boolean;
  var
    K: Integer;
    Message: TMessagePlayer;
  begin
    Result := True;
    for K := 0 to Session.Humans.Count - 1 do
    begin
      Message := Session.Humans[K].FindBubbleByKey(Key, False);
      if (Message = nil) or (Message.Kind <> Kind) then
        Exit(False);
    end;
  end;

  // Whether every human's last finished quest is letter N with that outcome.
  function AllFinished(N: Integer; Successful: Boolean): Boolean;
  var
    K: Integer;
    List: TList;
  begin
    Result := True;
    for K := 0 to Session.Humans.Count - 1 do
    begin
      List := Session.Humans[K].PlayerOldQuests;
      if (List = nil) or (List.Count = 0) then
        Exit(False);
      Quest := List[List.Count - 1];
      if (Quest.QuestType <> qtSendLetter) or (Quest.QuestNumber <> N)
          or (Quest.Successful <> Successful) then
        Exit(False);
    end;
  end;

  function NextLetter(After: Integer): Integer;
  var
    K: Integer;
  begin
    for K := After + 1 to 500 do
    begin
      Name := LetterName(K);
      if (Name <> '') and (Pos('Quest.', Name) <> 1) then
        Exit(K);
    end;
    Result := -1;
  end;

begin
  Result := 0;
  try
    P := nil;
    Q := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      for J := 0 to Star.Planets.Count - 1 do
      begin
        Candidate := TPlanet(Star.Planets[J]);
        if Candidate.OwnerId > Byte(oiGaal) then
          Continue;
        if P = nil then
          P := Candidate
        else if (Q = nil) and (Candidate.CurrentStar <> P.CurrentStar) then
          Q := Candidate;
      end;
    end;
    if (P = nil) or (Q = nil) then
      Fail('no two coalition planets');
    A := JoinHumanAt(P, 'QuestA', 1);
    B := JoinHumanAt(Q, 'QuestB', 2);
    if (A = nil) or (B = nil) then
      Fail('the humans did not join');
    AId := A.Id;
    // (a) A takes a letter quest to Q: every human's journal shows it.
    Number := NextLetter(0);
    if Number < 0 then
      Fail('no letter quest in the texts');
    Reward := 3001;
    SetOffer(A, Number, Reward);
    SubmitKindFor(A, ckAcceptQuest);
    if A.Player.Quests.Count <> 1 then
      Fail('the quest was not accepted');
    Key := 'ZP_' + IntToStr(Cardinal(P.Id)) + '_' + IntToStr(Number);
    if not AllHaveEntry(3) then
      Fail('a human''s journal lacks the accepted quest');
    Emit(Format('shared quests accepted humans=%d number=%d journal=all',
        [Session.Humans.Count, Number]));
    // (b) A's letter goes to B, who delivers it at Q.
    Letter := nil;
    for I := A.Player.Inventory.Count - 1 downto 1 do
    begin
      Item := A.Player.Inventory[I];
      if (Item is TUselessItem) and (TUselessItem(Item).ConfigBlockName = LetterName(Number)) then
      begin
        Letter := Item;
        A.Player.Inventory.Delete(I);
        Break;
      end;
    end;
    if Letter = nil then
      Fail('A has no letter');
    B.Player.Inventory.Add(Letter);
    A.Player.RefreshDerivedStats(True);
    B.Player.RefreshDerivedStats(True);
    Count := Session.Humans.Count;
    SetLength(Before, Count);
    SetLength(Experience, Count);
    for I := 0 to Count - 1 do
    begin
      Before[I] := Session.Humans[I].Player.Money;
      Experience[I] := Session.Humans[I].Player.TotalExperience;
    end;
    SubmitKindFor(B, ckBeginGovernmentDialog);
    if not GovernmentQuestTurnedIn then
      Fail('B did not turn in A''s quest');
    if A.Player.Quests.Count <> 0 then
      Fail('A still holds the delivered quest');
    Share := Reward div Count;
    for I := 0 to Count - 1 do
    begin
      Human := Session.Humans[I];
      if Human = B then
        J := Reward - Share * (Count - 1)
      else
        J := Share;
      if Human.Player.Money - Before[I] <> J then
        Fail(Format('human %d got %d of the reward, not %d',
            [Human.Id, Human.Player.Money - Before[I], J]));
      if Human.Player.TotalExperience <= Experience[I] then
        Fail(Format('human %d got no experience', [Human.Id]));
      // Each gets the whole experience: the same gain as B's.
      if Human.Player.TotalExperience - Experience[I]
          <> B.Player.TotalExperience - Experience[Session.Humans.IndexOf(B)] then
        Fail(Format('human %d got %d experience, B %d',
            [Human.Id, Human.Player.TotalExperience - Experience[I],
                B.Player.TotalExperience - Experience[Session.Humans.IndexOf(B)]]));
      if (Integer(Q.RelationToShip(Human.Player)) and $7F) < 70 then
        Fail(Format('human %d''s relation to Q did not rise', [Human.Id]));
    end;
    if not AllHaveEntry(4) then
      Fail('a human''s journal lacks the completed quest');
    if not AllFinished(Number, True) then
      Fail('a human''s finished quests lack the completed quest');
    Emit(Format('shared quests delivered by=other share=%d actor=%d journal=all finished=all',
        [Share, Reward - Share * (Count - 1)]));
    // (c) A takes another quest from P: P gives no other human a quest meanwhile.
    Number := NextLetter(Number);
    if Number < 0 then
      Fail('no second letter quest in the texts');
    SetOffer(A, Number, 2000);
    SubmitKindFor(A, ckAcceptQuest);
    if A.Player.Quests.Count <> 1 then
      Fail('the second quest was not accepted');
    C := JoinHumanAt(P, 'QuestC', 3);
    if C = nil then
      Fail('the third human did not join');
    P.SetRelationLevelToRanger(C.Player, rlExcellent);
    if C.Player.GenerateQuestOffer(Offer, Text) then
      Fail('P offered another human a quest while its quest is held');
    Expected :=
        PickLocalizedTextVariant(
            'FormGov.DontQuest.YouHaveQuest',
            P.GenerationSeed * (Galaxy.CurrentTurn div 5) + 165856
        );
    if Text <> Expected then
      Fail('P''s refusal is not that the humans have its quest');
    SetOffer(C, Number + 1000, 2000);
    Reason := 'applied';
    try
      SubmitKindFor(C, ckAcceptQuest);
    except
      on E: ECommandRefused do
        Reason := RefusalReasonName(E.Reason);
    end;
    if Reason <> RefusalReasonName(rrOfferGone) then
      Fail('a stale offer from P was accepted: ' + Reason);
    if C.Player.Quests.Count <> 0 then
      Fail('the refused offer left a quest');
    Emit(Format('shared quests offer refused=1 accept=%s', [Reason]));
    // (d) The quest's deadline passes: it fails once, for every human.
    Key := 'ZP_' + IntToStr(Cardinal(P.Id)) + '_' + IntToStr(Number);
    PQuest(A.Player.Quests[0]).DeadlineTurn := Galaxy.CurrentTurn;
    A.Player.ProcessQuestTimersAndOutcomes;
    if A.Player.Quests.Count <> 0 then
      Fail('the failed quest is still held');
    if not AllHaveEntry(5) then
      Fail('a human''s journal lacks the failed quest');
    if not AllFinished(Number, False) then
      Fail('a human''s finished quests lack the failed quest');
    for I := 0 to Session.Humans.Count - 1 do
      if P.GetRelationLevelToShip(Session.Humans[I].Player) > rlBad then
        Fail(Format('human %d''s relation to P did not drop', [Session.Humans[I].Id]));
    Emit('shared quests failed-once journal=all finished=all relation=all');
    // (e) A round trip keeps every human's finished quests.
    SetLength(OldCounts, Session.Humans.Count);
    for I := 0 to Session.Humans.Count - 1 do
      OldCounts[I] := Session.Humans[I].PlayerOldQuests.Count;
    if not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
      Fail('round trip');
    if FindHuman(AId) = nil then
      Fail('A is missing after the round trip');
    for I := 0 to Session.Humans.Count - 1 do
      if Session.Humans[I].PlayerOldQuests.Count <> OldCounts[I] then
        Fail(Format('human %d''s finished quests changed in the round trip',
            [Session.Humans[I].Id]));
    Emit('shared quests ok');
  except
    on E: EAbort do
      Result := 1;
  end;
end;

// CHANGE: ENHANCEMENT - Script builtins act for the script's human, on that human's machine
// (--sim-script-routing; docs/humans.md, Scripts). Two joined humans: one is made local, the
// other stands for a remote one. Headless there are no screens, so a builtin that touched one
// would fail.
const
  ckRoutingProbe = 1000;
var
  RoutingProbeRegistered: Boolean;
  // What the probe command runs, as its actor.
  RoutingProbeAction: procedure;
  // The human the probe command's script code runs for (nil: the actor).
  RoutingScriptHuman: THuman;
  RoutingNestedActor: Cardinal;
  RoutingCode: TCodeEC;
  RoutingText: WideString;
  RoutingScreenRequests: Integer;

// Runs Text as code of no script for Human (ScriptHuman); the caller reads the variables and
// frees the code.
function RunProbeScript(Human: THuman; const Text: WideString): TCodeEC;
var
  SavedHuman: THuman;
  SavedScript: TScript;
begin
  Result := CompileScriptText(Text);
  Result.LinkAll(Session.SharedScriptVariables, False);
  Result.LinkAll(ScriptFunctionScope, False);
  Result.ScriptFunLinked := True;
  SavedHuman := ScriptHuman;
  SavedScript := CurrentScript;
  ScriptHuman := Human;
  CurrentScript := nil;
  try
    Result.Run(ScriptProcess);
  finally
    ScriptHuman := SavedHuman;
    CurrentScript := SavedScript;
  end;
end;

procedure ExecuteRoutingProbe(const Command: TPlayerCommand);
begin
  RoutingProbeAction;
end;

procedure RecordNestedActor;
var
  SavedHuman: THuman;
begin
  SavedHuman := ScriptHuman;
  if RoutingScriptHuman <> nil then
    ScriptHuman := RoutingScriptHuman;
  try
    RoutingNestedActor := NewCommand(ckRoutingProbe).Actor;
  finally
    ScriptHuman := SavedHuman;
  end;
end;

procedure RunRoutingText;
var
  Human: THuman;
begin
  Human := RoutingScriptHuman;
  if Human = nil then
    Human := ActingHuman;
  RoutingCode := RunProbeScript(Human, RoutingText);
end;

// Runs Text in a command of Actor, as script code of ScriptOf (nil: the actor's).
function RunInCommand(Actor, ScriptOf: THuman; const Text: WideString): TCodeEC;
begin
  RoutingProbeAction := @RunRoutingText;
  RoutingScriptHuman := ScriptOf;
  RoutingText := Text;
  RoutingCode := nil;
  SubmitKindFor(Actor, ckRoutingProbe);
  Result := RoutingCode;
end;

procedure CountScreenRequest(Screen: TGameScreenId);
begin
  Inc(RoutingScreenRequests);
end;

// CHANGE: ENHANCEMENT - Commands name scripts, injected answers and overrides by key, and a
// remote human's dialogue commands keep to that human's dialogue state (docs/humans.md,
// Scripts; docs/commands.md). L is local, R stands for a client's human whose commands the
// host applies. Prints what fails and returns False.
function CheckDialogKeys(L, R: THuman): Boolean;
var
  S1, S2: TScript;
  SavedHuman1, SavedHuman2, Index1, Index2: Integer;
  SavedName2: WideString;
  Command, OldCommand, OverrideCommand, ShortCommand, FirstCommand: TPlayerCommand;
  LocalEntry, X, Y: PScriptDialogInjection;
  Removed: TScript;
  RemovedAt: Integer;
  Override1, Override2: PScriptDialogOverride;
  State: TScriptDialogState;
  Got: AnsiString;
  Exchanged: Boolean;

  procedure Fail(const Text: AnsiString);
  begin
    Emit('script routing failed: ' + Text);
    raise EAbort.Create(Text);
  end;

  procedure Expect(Condition: Boolean; const Text: AnsiString);
  begin
    if not Condition then
      Fail(Text);
  end;

  // '' when Human's command ran, else the reason it was refused for.
  function TryFor(Human: THuman; Command: TPlayerCommand): AnsiString;
  begin
    Result := '';
    try
      SubmitFor(Human, Command);
    except
      on E: ECommandRefused do
        Result := RefusalReasonName(E.Reason);
    end;
  end;

  function NewInjection(Script: TScript; const Answer, Action: WideString): PScriptDialogInjection;
  begin
    New(Result);
    Result.Script := Script;
    Result.DialogName := 'probe';
    Result.Text := '';
    Result.Answer := Answer;
    Result.Priority := 0;
    Result.AnswerData := 0;
    Result.ReplaceGreeting := False;
    Result.ActionCode := Action;
    Result.ActionScript := Script;
  end;

  function NewOverride(Script: TScript; Priority: Integer): PScriptDialogOverride;
  begin
    New(Result);
    Result.Script := Script;
    Result.DialogName := '';
    Result.Priority := Priority;
    Result.AnswerData := 0;
  end;

  // R's dialogue state while none of its commands runs.
  function RemoteState: TScriptDialogState;
  begin
    Result := HumanDialogState(R);
  end;

  // The local human's dialogue is as the probe left it.
  procedure ExpectLocalDialog(const What: AnsiString);
  begin
    Expect(ForeignDialogHuman = nil, What + ': a remote dialogue state is still in place');
    Expect(Session.ScriptDialogIndex = 3, What + ': the local dialogue message changed');
    Expect(CurrentScript = S2, What + ': the local dialogue''s script changed');
    Expect(
        (ScriptDialogInjections <> nil)
            and (ScriptDialogInjections.Count = 1)
            and (ScriptDialogInjections[0] = LocalEntry)
            and (LocalEntry.Answer = 'local'),
        What + ': the local injected answers changed'
    );
  end;

begin
  Result := True;
  if Galaxy.Scripts.Count < 2 then
  begin
    Emit(Format('script routing keys skipped scripts=%d', [Galaxy.Scripts.Count]));
    Exit;
  end;
  S1 := TScript(Galaxy.Scripts[0]);
  S2 := TScript(Galaxy.Scripts[1]);
  SavedHuman1 := S1.HumanId;
  SavedHuman2 := S2.HumanId;
  SavedName2 := S2.ScriptFileName;
  Exchanged := False;
  Removed := nil;
  RemovedAt := 0;
  try
    try
      // The local human has a dialogue open: its message, script and an injected answer.
      ClearScriptDialogRules;
      LocalEntry := NewInjection(S2, 'local', '');
      ScriptDialogInjections.Add(LocalEntry);
      Session.ScriptDialogIndex := 3;
      CurrentScript := S2;
      // (1) The same script for two humans, started in a different order here: R's answer
      // names R's script by its key, not by its index.
      S1.HumanId := R.Id;
      S2.HumanId := L.Id;
      S2.ScriptFileName := S1.ScriptFileName;
      Command := NewCommand(ckScriptAnswerOnly);
      AddScriptIndex(Command, S1);
      AddInt(Command, -1);
      AddScriptKey(Command, S1);
      // CHANGE: BUGFIX - The key's count follows; ShortCommand is the three-integer key
      // without it, as sent before the count.
      ShortCommand := NewCommand(ckScriptAnswerOnly);
      AddScriptIndex(ShortCommand, S1);
      AddInt(ShortCommand, -1);
      AddScriptKey(ShortCommand, S1);
      AddScriptCount(Command, S1);
      OldCommand := NewCommand(ckScriptAnswerOnly);
      AddScriptIndex(OldCommand, S1);
      AddInt(OldCommand, -1);
      Galaxy.Scripts.Exchange(0, 1);
      Exchanged := True;
      Got := TryFor(R, Command);
      Expect(Got = '', 'an answer by key was refused: ' + Got);
      Expect(RemoteState.Script = S1, 'an answer by key did not reach its human''s script');
      ExpectLocalDialog('a remote answer');
      RemoteState.Script := nil;
      Got := TryFor(R, ShortCommand);
      Expect(Got = '', 'an answer by a key without its count was refused: ' + Got);
      Expect(
          RemoteState.Script = S1,
          'an answer by a key without its count did not reach its human''s script'
      );
      ExpectLocalDialog('a remote answer without a count');
      // A log from before names the script by its index, which now holds the other one.
      Got := TryFor(R, OldCommand);
      Expect(Got = '', 'an answer by index was refused: ' + Got);
      Expect(RemoteState.Script = S2, 'an answer by index did not reach the indexed script');
      ExpectLocalDialog('a remote answer by index');
      // (2) A key that names no script is refused before anything changes.
      Command.Ints[4] := 7;
      Got := TryFor(R, Command);
      Expect(Got = RefusalReasonName(rrTargetGone), 'a stale script key was not refused: ' + Got);
      Command.Ints[4] := 0;
      Command.Ints[3] := Command.Ints[3] xor $5A5A;
      Got := TryFor(R, Command);
      Expect(Got = RefusalReasonName(rrTargetGone), 'an unknown script key was not refused: ' + Got);
      Expect(RemoteState.Script = S2, 'a refused answer changed the dialogue''s script');
      ExpectLocalDialog('a refused answer');
      Emit('script routing script keys ok');
      // (3) R's injected answers: the command names Y, and R's list is then built again in
      // another order; the answer runs Y's action, not the one now at Y's index.
      Got := TryFor(R, NewCommand(ckClearTalkDialogRules));
      Expect(Got = '', 'clearing the remote rules was refused: ' + Got);
      ExpectLocalDialog('the remote rules cleared');
      State := RemoteState;
      X := NewInjection(S1, 'x', 'ForceNextDay();');
      Y := NewInjection(S1, 'y', 'ExtremalTakeOff();');
      State.Injections.Add(X);
      State.Injections.Add(Y);
      Expect(EnterHumanDialogState(R), 'the remote dialogue state was not put in place');
      try
        Command := NewCommand(ckRunInjectedAnswerAction);
        AddInt(Command, ScriptDialogInjections.IndexOf(Y));
        AddInjectionKey(Command, Y);
        AddInjectionCount(Command, Y);
        Override1 := NewOverride(S1, 1);
        ScriptDialogOverrides.Add(Override1);
        OverrideCommand := NewCommand(ckTalkDialogOverride);
        AddOverrideKey(OverrideCommand, SelectedDialogOverride);
        AddOverrideCount(OverrideCommand, SelectedDialogOverride);
      finally
        LeaveHumanDialogState;
      end;
      ExpectLocalDialog('the remote answer named');
      Got := TryFor(R, NewCommand(ckClearTalkDialogRules));
      Expect(Got = '', 'clearing the remote rules was refused: ' + Got);
      State.Injections.Add(NewInjection(S1, 'y', 'ExtremalTakeOff();'));
      State.Injections.Add(NewInjection(S1, 'x', 'ForceNextDay();'));
      R.ScriptTakeoffRequested := False;
      R.ScriptEndTurnRequested := False;
      Got := TryFor(R, Command);
      Expect(Got = '', 'an injected answer by key was refused: ' + Got);
      Expect(
          R.ScriptTakeoffRequested and not R.ScriptEndTurnRequested,
          'an injected answer by key ran another answer''s action'
      );
      ExpectLocalDialog('a remote injected answer');
      // A log from before names the answer by its index only: the one now there runs.
      OldCommand := NewCommand(ckRunInjectedAnswerAction);
      AddInt(OldCommand, Command.Ints[0]);
      R.ScriptTakeoffRequested := False;
      Got := TryFor(R, OldCommand);
      Expect(Got = '', 'an injected answer by index was refused: ' + Got);
      Expect(
          R.ScriptEndTurnRequested and not R.ScriptTakeoffRequested,
          'an injected answer by index did not run the answer at that index'
      );
      R.ScriptEndTurnRequested := False;
      // Built again without it: refused, and nothing runs.
      Got := TryFor(R, NewCommand(ckClearTalkDialogRules));
      Expect(Got = '', 'clearing the remote rules was refused: ' + Got);
      State.Injections.Add(NewInjection(S1, 'x', 'ForceNextDay();'));
      R.ScriptTakeoffRequested := False;
      Got := TryFor(R, Command);
      Expect(
          Got = RefusalReasonName(rrTargetGone),
          'a stale injected answer was not refused: ' + Got
      );
      Expect(
          not R.ScriptTakeoffRequested and not R.ScriptEndTurnRequested,
          'a refused injected answer ran an action'
      );
      ExpectLocalDialog('a refused injected answer');
      Emit('script routing injection keys ok');
      // (4) Overrides: none is refused (the list was read at [0] unchecked), and a stale key
      // is refused.
      Got := TryFor(R, NewCommand(ckTalkDialogOverride));
      Expect(Got = RefusalReasonName(rrTargetGone), 'an override with none was not refused: ' + Got);
      Override2 := NewOverride(S1, 2);
      State.Overrides.Add(Override2);
      Got := TryFor(R, OverrideCommand);
      Expect(
          Got = RefusalReasonName(rrTargetGone),
          'a stale override key was not refused: ' + Got
      );
      Got := TryFor(R, NewCommand(ckTalkDialogOverride));
      Expect(Got = '', 'the remote override was refused: ' + Got);
      Expect(TalkScript = S1, 'the remote override did not select its script');
      ExpectLocalDialog('a remote override');
      // A remote reset of the dialogue leaves the local one.
      Got := TryFor(R, NewCommand(ckResetScriptDialog));
      Expect(Got = '', 'the remote reset was refused: ' + Got);
      ExpectLocalDialog('a remote reset');
      Emit('script routing dialog state ok');
      // CHANGE: BUGFIX - (5) Two instances of one file for R: S2 first, S1 second. Commands
      // built before the first ends name them with a count of two; once it has ended, the
      // second's key would shift its ordinal and the first's would name the second. Both are
      // refused, nothing changes, and a command built afresh reaches the second.
      S2.HumanId := R.Id;
      FirstCommand := NewCommand(ckScriptAnswerOnly);
      AddScriptIndex(FirstCommand, S2);
      AddInt(FirstCommand, -1);
      AddScriptKey(FirstCommand, S2);
      AddScriptCount(FirstCommand, S2);
      Command := NewCommand(ckScriptAnswerOnly);
      AddScriptIndex(Command, S1);
      AddInt(Command, -1);
      AddScriptKey(Command, S1);
      AddScriptCount(Command, S1);
      // Other scripts of the save may share the file and the human; the two are next to each
      // other.
      Expect(
          (Command.Ints[4] = FirstCommand.Ints[4] + 1)
              and (Command.Ints[5] = FirstCommand.Ints[5])
              and (Command.Ints[5] >= 2),
          'the two instances do not have neighbouring ordinals of one count'
      );
      RemovedAt := Galaxy.Scripts.IndexOf(S2);
      Removed := S2;
      Galaxy.Scripts.Delete(RemovedAt);
      RemoteState.Script := nil;
      Got := TryFor(R, Command);
      Expect(
          Got = RefusalReasonName(rrTargetGone),
          'a key from before the first instance ended was not refused: ' + Got
      );
      Got := TryFor(R, FirstCommand);
      Expect(
          Got = RefusalReasonName(rrTargetGone),
          'the ended instance''s key was not refused: ' + Got
      );
      Expect(RemoteState.Script = nil, 'a refused instance key reached a script');
      Command := NewCommand(ckScriptAnswerOnly);
      AddScriptIndex(Command, S1);
      AddInt(Command, -1);
      AddScriptKey(Command, S1);
      AddScriptCount(Command, S1);
      Got := TryFor(R, Command);
      Expect(Got = '', 'a fresh key of the remaining instance was refused: ' + Got);
      Expect(RemoteState.Script = S1, 'a fresh key did not reach the remaining instance');
      Galaxy.Scripts.Insert(RemovedAt, Removed);
      Removed := nil;
      // The entry keys carry the count too: an answer of the first instance, named while both
      // run, is refused once the second has ended, and runs while both run.
      Got := TryFor(R, NewCommand(ckClearTalkDialogRules));
      Expect(Got = '', 'clearing the remote rules was refused: ' + Got);
      State := RemoteState;
      State.Injections.Add(NewInjection(S2, 'z', 'ExtremalTakeOff();'));
      Expect(EnterHumanDialogState(R), 'the remote dialogue state was not put in place');
      try
        Command := NewCommand(ckRunInjectedAnswerAction);
        AddInt(Command, 0);
        AddInjectionKey(Command, PScriptDialogInjection(ScriptDialogInjections[0]));
        AddInjectionCount(Command, PScriptDialogInjection(ScriptDialogInjections[0]));
      finally
        LeaveHumanDialogState;
      end;
      Expect(
          Command.Ints[6] = FirstCommand.Ints[5],
          'an answer''s key does not count both instances'
      );
      RemovedAt := Galaxy.Scripts.IndexOf(S1);
      Removed := S1;
      Galaxy.Scripts.Delete(RemovedAt);
      R.ScriptTakeoffRequested := False;
      Got := TryFor(R, Command);
      Expect(
          Got = RefusalReasonName(rrTargetGone),
          'an answer named before another instance ended was not refused: ' + Got
      );
      Expect(not R.ScriptTakeoffRequested, 'a refused answer ran its action');
      Galaxy.Scripts.Insert(RemovedAt, Removed);
      Removed := nil;
      Got := TryFor(R, Command);
      Expect(Got = '', 'an answer of one of two instances was refused: ' + Got);
      Expect(R.ScriptTakeoffRequested, 'an answer of one of two instances did not run');
      R.ScriptTakeoffRequested := False;
      Got := TryFor(R, NewCommand(ckClearTalkDialogRules));
      Expect(Got = '', 'clearing the remote rules was refused: ' + Got);
      ExpectLocalDialog('instance keys');
      Emit('script routing instance keys ok');
    except
      on E: EAbort do
        Result := False;
    end;
  finally
    if Removed <> nil then
      Galaxy.Scripts.Insert(RemovedAt, Removed);
    if Exchanged then
      Galaxy.Scripts.Exchange(0, 1);
    S1.HumanId := SavedHuman1;
    S2.HumanId := SavedHuman2;
    S2.ScriptFileName := SavedName2;
    R.ScriptTakeoffRequested := False;
    R.ScriptEndTurnRequested := False;
    ClearScriptDialogRules;
    Session.ScriptDialogIndex := -1;
    CurrentScript := nil;
  end;
end;

function RunScriptRouting(const Options: TSimulationOptions): Integer;
var
  L, R: THuman;
  Code: TCodeEC;
  Defaults, EndReason: Integer;
  Command: TPlayerCommand;
  SavedHandler: TScreenRequestHandler;
  TalkShip: TShip;

  procedure Fail(const Text: AnsiString);
  begin
    Emit('script routing failed: ' + Text);
    raise EAbort.Create(Text);
  end;

  procedure Expect(Condition: Boolean; const Text: AnsiString);
  begin
    if not Condition then
      Fail(Text);
  end;

  function Count(Queue: Integer; Human: THuman): Integer;
  begin
    Result := ScriptRequestCount(Queue, Human.Id);
  end;

begin
  Result := 0;
  try
    if not RoutingProbeRegistered then
    begin
      RegisterCommand(ckRoutingProbe, 'RoutingProbe', @ExecuteRoutingProbe);
      RoutingProbeRegistered := True;
    end;
    JoinHumans(3);
    L := Session.Humans[1];
    R := Session.Humans[2];
    SetLocalHuman(L);
    Expect(LocalHuman = L, 'the joined human is not local');
    // (a) The UI builtins of a remote human's script code show nothing and answer as a player
    // who declines.
    Defaults := ScriptUiDefaultCount;
    EndReason := Session.GameEndReason;
    Code := RunProbeScript(
        R,
        'int r1; str s1; str s2; str s3; int r2; int r3; int r4; str s4; int r5;'
            + 'MessageBox("probe");'
            + 'r1 = MessageBoxYesNo("probe");'
            + 's1 = CountBox("c", "d", 0, 10);'
            + 's2 = NumberBox("c", "d", 0, 10);'
            + 's3 = TextBox("c", "default");'
            + 'r2 = ListBox("c", "a", "b");'
            + 'r3 = OpenCustomForm("probe");'
            + 'r4 = RunChildForm("probe");'
            + 's4 = CurrentForm();'
            + 'r5 = StarMapCurPosX();'
            + 'StartMusic("probe");'
            + 'ButtonClick("a", "b");'
            + 'FormChange("probe");'
            + 'DText("probe");'
            + 'DAddText("probe");'
            + 'DAnswer("probe");'
            + 'DAnswer("exit_end");'
    );
    try
      Expect(Code.LocalVar.GetVar('r1').GetInt = 0, 'MessageBoxYesNo did not answer no');
      Expect(Code.LocalVar.GetVar('s1').GetString = 'Cancel', 'CountBox did not cancel');
      Expect(Code.LocalVar.GetVar('s2').GetString = 'Cancel', 'NumberBox did not cancel');
      Expect(
          Code.LocalVar.GetVar('s3').GetString = 'default',
          'TextBox did not give the default'
      );
      Expect(Code.LocalVar.GetVar('r2').GetInt = -1, 'ListBox did not cancel');
      Expect(Code.LocalVar.GetVar('r3').GetInt = 0, 'OpenCustomForm did not answer 0');
      Expect(Code.LocalVar.GetVar('r4').GetInt = 0, 'RunChildForm did not answer 0');
      Expect(Code.LocalVar.GetVar('s4').GetString = '', 'CurrentForm named a form');
      Expect(Code.LocalVar.GetVar('r5').GetInt = 0, 'StarMapCurPosX read the star map');
    finally
      Code.Free;
    end;
    Expect(
        ScriptUiDefaultCount - Defaults = 13,
        Format('%d defaults, not 13', [ScriptUiDefaultCount - Defaults])
    );
    Expect(Session.GameEndReason = EndReason, 'a remote exit_end changed the local game end');
    Emit(Format('script routing ui defaults=%d ok', [ScriptUiDefaultCount - Defaults]));
    // (b) A command a remote human's command submits is that human's, also from script code
    // of a third human's script; outside a command it is the local human's.
    RoutingProbeAction := @RecordNestedActor;
    RoutingScriptHuman := nil;
    SubmitKindFor(R, ckRoutingProbe);
    Expect(RoutingNestedActor = Cardinal(R.Id), 'a nested command is not its actor''s');
    RoutingScriptHuman := R;
    SubmitKindFor(L, ckRoutingProbe);
    Expect(
        RoutingNestedActor = Cardinal(R.Id),
        'a nested command is not the script''s human''s'
    );
    RoutingScriptHuman := nil;
    Expect(
        NewCommand(ckRoutingProbe).Actor = Cardinal(L.Id),
        'a command is not the local human''s'
    );
    Emit('script routing nested actor ok');
    // (c) Takeoff and end-turn requests are per human, and a command clears its actor's.
    RunProbeScript(R, 'ExtremalTakeOff(); ForceNextDay();').Free;
    Expect(R.ScriptTakeoffRequested and R.ScriptEndTurnRequested, 'the remote request is lost');
    Expect(
        not L.ScriptTakeoffRequested and not L.ScriptEndTurnRequested,
        'a remote request is the local human''s'
    );
    Expect(not HasPendingScriptRequests, 'a remote request is pending on this machine');
    RunProbeScript(L, 'ForceNextDay();').Free;
    SubmitKindFor(R, ckClearScriptEndTurn);
    Expect(not R.ScriptEndTurnRequested, 'the remote end turn was not cleared');
    Expect(L.ScriptEndTurnRequested, 'a remote command cleared the local end turn');
    SubmitKindFor(R, ckOrderScriptTakeoff);
    Expect(not R.ScriptTakeoffRequested, 'the remote takeoff was not taken');
    L.ScriptEndTurnRequested := False;
    Emit('script routing takeoff ok');
    // (d) Queued battles and videos: a remote human's are queued only in its own command, and
    // the command that finishes one finishes its actor's.
    Code := RunProbeScript(
        R,
        'int a; a = StartAB("probe"); StartRobots("m", "s", "w", "l", "p"); StartVideo("v", "s");'
    );
    try
      Expect(Code.LocalVar.GetVar('a').GetInt = 0, 'StartAB outside the human''s command started');
    finally
      Code.Free;
    end;
    Expect(
        (Count(srqArcadeBattle, R) = 0)
            and (Count(srqPlanetaryBattle, R) = 0)
            and (Count(srqVideo, R) = 0),
        'a remote request was queued outside its command'
    );
    RunInCommand(R, nil, 'StartRobots("m", "s", "w", "l", "p"); StartVideo("v", "s");').Free;
    Expect(
        (Count(srqPlanetaryBattle, R) = 1) and (Count(srqVideo, R) = 1),
        'a request in the human''s own command was not queued'
    );
    Expect(
        (LocalScriptRequest(srqPlanetaryBattle) = nil) and (LocalScriptRequest(srqVideo) = nil),
        'a remote request is the local human''s'
    );
    Command := NewCommand(ckFinishQueuedPlanetaryBattle);
    AddInt(Command, 2);
    SubmitFor(L, Command);
    Expect(Count(srqPlanetaryBattle, R) = 1, 'the local human''s report finished a remote battle');
    Command := NewCommand(ckFinishQueuedPlanetaryBattle);
    AddInt(Command, 2);
    SubmitFor(R, Command);
    Command := NewCommand(ckFinishQueuedVideo);
    AddInt(Command, 2);
    SubmitFor(R, Command);
    Expect(
        (Count(srqPlanetaryBattle, R) = 0) and (Count(srqVideo, R) = 0),
        'the remote human''s report did not finish its request'
    );
    // A video in the remote human's command while its ship screen shows plays there at once,
    // and is not reported: it is not queued here. Once the screen closes it is queued again.
    Command := NewCommand(ckOpenShipScreen);
    AddRef(Command, R.Player);
    AddInt(Command, 0);
    SubmitFor(R, Command);
    Expect(R.ShipScreenShown, 'the remote human''s ship screen does not show');
    RunInCommand(R, nil, 'StartVideo("v", "s");').Free;
    Expect(Count(srqVideo, R) = 0, 'a video on the remote human''s ship screen was queued');
    Command := NewCommand(ckCloseShipScreen);
    AddInt(Command, 0);
    SubmitFor(R, Command);
    Expect(not R.ShipScreenShown and (R.EditedShip = nil), 'the closed ship screen still shows');
    RunInCommand(R, nil, 'StartVideo("v", "s");').Free;
    Expect(Count(srqVideo, R) = 1, 'a video off the ship screen was not queued');
    Command := NewCommand(ckFinishQueuedVideo);
    AddInt(Command, 2);
    SubmitFor(R, Command);
    Expect(Count(srqVideo, R) = 0, 'the video was not finished');
    Emit('script routing queues ok');
    // (e) The talk builtins read the talking human's talk: the actor's, also in another
    // human's script, else the script's human's.
    TalkShip := L.Player;
    R.TalkShip := TalkShip;
    R.TalkType := 7;
    L.TalkShip := nil;
    L.TalkType := 0;
    Code := RunProbeScript(R, 'int k; dword t; k = GetTalkType(); t = GetTalkShip();');
    try
      Expect(Code.LocalVar.GetVar('k').GetInt = 7, 'GetTalkType read another human''s talk');
      Expect(
          Code.LocalVar.GetVar('t').GetDword = PtrUInt(TalkShip),
          'GetTalkShip read another human''s talk'
      );
    finally
      Code.Free;
    end;
    Code := RunInCommand(R, L, 'int k; k = GetTalkType();');
    try
      Expect(
          Code.LocalVar.GetVar('k').GetInt = 7,
          'GetTalkType in the talker''s command read the script''s human''s'
      );
    finally
      Code.Free;
    end;
    R.TalkShip := nil;
    R.TalkType := 0;
    Emit('script routing talk ok');
    // (f) Ruins mode: the state changes for its human, the screen only for the local one.
    SavedHandler := ScreenRequestHandler;
    ScreenRequestHandler := @CountScreenRequest;
    try
      RoutingScreenRequests := 0;
      R.Player.EnterRuinsMode(1);
      Expect(R.Player.RuinsMode = 1, 'the remote human did not enter ruins mode');
      R.Player.CloseRuinsModeScreen;
      Expect(R.Player.RuinsMode = 0, 'the remote human did not leave ruins mode');
      Expect(RoutingScreenRequests = 0, 'a remote human''s ruins mode requested a screen');
      L.Player.EnterRuinsMode(1);
      L.Player.CloseRuinsModeScreen;
      Expect(
          RoutingScreenRequests = 2,
          'the local human''s ruins mode did not request its screens'
      );
      Expect(L.Player.RuinsMode = 0, 'the local human did not leave ruins mode');
    finally
      ScreenRequestHandler := SavedHandler;
    end;
    Emit('script routing ruins ok');
    // (g) Scripts, injected answers and overrides by key; a remote human's dialogue state.
    Expect(CheckDialogKeys(L, R), 'dialog keys');
    Emit('script routing ok');
  except
    on E: EAbort do
      Result := 1;
  end;
end;

// CHANGE: ENHANCEMENT - Two humans act on one object from copies made before either acted, as
// two clients do between days (--sim-stale-commands; docs/network.md, Commands): the host
// applies the second command after the first, and must refuse it with its reason before it
// changes anything. Each part has two humans at one place send the same command, built from
// what both saw before the first acted: the second is refused, its human's money stays, and
// no item is lost or in two places.
function RunStaleCommands(const Options: TSimulationOptions): Integer;
var
  Joined: Integer;

  procedure Fail(const Text: AnsiString);
  begin
    Emit('stale commands failed: ' + Text);
    raise EAbort.Create(Text);
  end;

  procedure Expect(Condition: Boolean; const Text: AnsiString);
  begin
    if not Condition then
      Fail(Text);
  end;

  // '' when Human's command ran, else the reason it was refused for.
  function TryFor(Human: THuman; Command: TPlayerCommand): AnsiString;
  begin
    Result := '';
    try
      SubmitFor(Human, Command);
    except
      on E: ECommandRefused do
        Result := RefusalReasonName(E.Reason);
    end;
  end;

  procedure ExpectRefused(
      Human: THuman;
      const Command: TPlayerCommand;
      Reason: TRefusalReason;
      const What: AnsiString
  );
  var
    Money: Integer;
    Got: AnsiString;
  begin
    Money := Human.Player.Money;
    Got := TryFor(Human, Command);
    Expect(
        Got = RefusalReasonName(Reason),
        Format('%s: refused as "%s", not %s', [What, Got, RefusalReasonName(Reason)])
    );
    Expect(Human.Player.Money = Money, What + ': the refused human''s money changed');
  end;

  // The items in Lists and in the humans' holds, artefacts and storage, in Count; '' when none
  // is in two places.
  function CountItems(
      const Lists: array of TList;
      const Humans: array of THuman;
      out Count: Integer
  ): AnsiString;
  var
    Items: TList;
    I, J: Integer;
    P: TPlayer;
  begin
    Result := '';
    Items := TList.Create;
    try
      for I := 0 to High(Lists) do
        if Lists[I] <> nil then
          for J := 0 to Lists[I].Count - 1 do
            Items.Add(Lists[I][J]);
      for I := 0 to High(Humans) do
      begin
        P := Humans[I].Player;
        for J := 0 to P.Inventory.Count - 1 do
          Items.Add(P.Inventory[J]);
        for J := 0 to P.Artefacts.Count - 1 do
          Items.Add(P.Artefacts[J]);
        // CHANGE: ENHANCEMENT - The humans share one storage pool (docs/humans.md, Storage):
        // it is counted once.
        if (I > 0) and (Humans[0].Player.StorageEntries = P.StorageEntries) then
          Continue;
        for J := 0 to P.StorageEntries.Count - 1 do
          if PStorageEntry(P.StorageEntries[J]).Item <> nil then
            Items.Add(PStorageEntry(P.StorageEntries[J]).Item);
      end;
      Count := Items.Count;
      for I := 0 to Items.Count - 1 do
        for J := I + 1 to Items.Count - 1 do
          if Items[I] = Items[J] then
            Exit(Format('item %d is in two places', [TItem(Items[I]).Id]));
    finally
      Items.Free;
    end;
  end;

  // A planet of the coalition in Star, where humans can join; nil when there is none.
  function JoinPlanetIn(Star: TStar): TPlanet;
  var
    I: Integer;
  begin
    Result := nil;
    for I := 0 to Star.Planets.Count - 1 do
      if TPlanet(Star.Planets[I]).OwnerId <= Byte(oiGaal) then
        Exit(TPlanet(Star.Planets[I]));
  end;

  // A station of that type in a star with a planet humans can join at.
  function FindStation(StationType: TStationType; out Planet: TPlanet): TRuins;
  var
    I, J: Integer;
    Star: TStar;
  begin
    Result := nil;
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      for J := 0 to Star.Ships.Count - 1 do
        if (TShip(Star.Ships[J]) is TRuins)
            and (TShip(Star.Ships[J]).TypeId = Byte(StationType))
            and not IsRuinsProxy(TShip(Star.Ships[J]))
            and (JoinPlanetIn(Star) <> nil) then
        begin
          Planet := JoinPlanetIn(Star);
          Exit(TRuins(Star.Ships[J]));
        end;
    end;
  end;

  procedure JoinPair(Planet: TPlanet; out A, B: THuman);
  begin
    Inc(Joined);
    A := JoinHumanAt(Planet, WideString(Format('Stale%dA', [Joined])), 1);
    B := JoinHumanAt(Planet, WideString(Format('Stale%dB', [Joined])), 2);
    Expect((A <> nil) and (B <> nil), 'the humans did not join');
    A.Player.SetMoney(100000000);
    B.Player.SetMoney(100000000);
  end;

  procedure DockAt(Human: THuman; Station: TRuins);
  begin
    Human.Player.CurrentPlanet := nil;
    Human.Player.DockedTo := Station;
    Human.Player.Position := Station.Position;
  end;

  procedure CheckSpecialShip;
  var
    Station: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Stored: Integer;
  begin
    Station := FindStation(rstPirateBase, Planet);
    if Station = nil then
      Station := FindStation(rstMilitaryBase, Planet);
    if Station = nil then
      Station := FindStation(rstScienceBase, Planet);
    if Station = nil then
    begin
      Emit('stale special ship skipped: no station that sells one');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    DockAt(B, Station);
    Station.SpecialServiceActive := True;
    Stored := A.Player.StorageEntries.Count;
    Expect(TryFor(A, NewCommand(ckBuySpecialShip)) = '', 'the first special ship was refused');
    Expect(A.Player.StorageEntries.Count = Stored + 1, 'the first buyer got no special ship');
    Stored := B.Player.StorageEntries.Count;
    ExpectRefused(B, NewCommand(ckBuySpecialShip), rrOfferGone, 'the second special ship');
    Expect(B.Player.StorageEntries.Count = Stored, 'the second buyer got a special ship');
    Emit(Format('stale special ship station=%d ok', [Station.Id]));
  end;

  procedure CheckSatellite;
  var
    Station: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Command: TPlayerCommand;
    Offer: TItem;
    Before, After, Carried: Integer;
    Problem: AnsiString;
  begin
    Station := FindStation(rstScienceBase, Planet);
    if Station = nil then
    begin
      Emit('stale satellite skipped: no science base');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    DockAt(B, Station);
    A.Player.BaseSkills[Ord(psTechnical)] := 6;
    B.Player.BaseSkills[Ord(psTechnical)] := 6;
    if Station.SatelliteOffer = nil then
      Station.RegenerateSatelliteOffer;
    Offer := Station.SatelliteOffer;
    if Galaxy.CountExistingSatellites + 1 >= A.Player.GetSatelliteLimit then
    begin
      Emit('stale satellite skipped: the galaxy has its satellites');
      Exit;
    end;
    Command := NewCommand(ckBuySatellite);
    AddInt(Command, Integer(Offer.Id));
    AddInt(Command, Offer.Cost);
    Problem := CountItems([], [A, B], Before);
    Expect(Problem = '', Problem);
    Expect(TryFor(A, Command) = '', 'the first satellite was refused');
    Expect(A.Player.Inventory.IndexOf(Offer) >= 0, 'the first buyer has no satellite');
    Carried := B.Player.Inventory.Count;
    ExpectRefused(B, Command, rrOfferGone, 'the second satellite');
    Expect(B.Player.Inventory.Count = Carried, 'the second buyer got a satellite');
    Problem := CountItems([], [A, B], After);
    Expect(Problem = '', Problem);
    Expect(After = Before + 1, Format('the items went from %d to %d', [Before, After]));
    Emit(Format('stale satellite station=%d item=%d ok', [Station.Id, Offer.Id]));
  end;

  procedure CheckInvestment;
  var
    Station: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Command: TPlayerCommand;
    Star: TStar;
    I, Kind, Stations: Integer;
    Done: Boolean;
  begin
    Station := FindStation(rstBusinessCenter, Planet);
    if Station = nil then
    begin
      Emit('stale investment skipped: no business center');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    DockAt(B, Station);
    for Kind := cpCreateRangerCenter to cpCreateMedicalBase do
    begin
      A.Player.StationServiceLastUseTurns[Kind] := -100000;
      B.Player.StationServiceLastUseTurns[Kind] := -100000;
    end;
    // The first new station a star can take: a refused investment changes nothing.
    Done := False;
    Star := nil;
    Stations := 0;
    for Kind := cpCreateRangerCenter to cpCreateMedicalBase do
    begin
      for I := 0 to Galaxy.Stars.Count - 1 do
      begin
        Star := TStar(Galaxy.Stars[I]);
        if (Star = Station.CurrentStar) or (Star.Constellation.Id = 20) then
          Continue;
        Command := NewCommand(ckInvest);
        AddInt(Command, Kind);
        AddInt(Command, 1000);
        AddRef(Command, Star);
        Stations := Star.CountShipsByTypeMask([Ord(rstRangerCenter)..Ord(rstDominion)]);
        if TryFor(A, Command) = '' then
        begin
          Done := True;
          Break;
        end;
      end;
      if Done then
        Break;
    end;
    if not Done then
    begin
      Emit('stale investment skipped: no star can take a new station');
      Exit;
    end;
    Expect(
        Star.CountShipsByTypeMask([Ord(rstRangerCenter)..Ord(rstDominion)]) = Stations + 1,
        'the first investment built no station'
    );
    ExpectRefused(B, Command, rrOfferGone, 'the second investment');
    Expect(
        Star.CountShipsByTypeMask([Ord(rstRangerCenter)..Ord(rstDominion)]) = Stations + 1,
        'the second investment built a station'
    );
    Emit(Format('stale investment kind=%d star=%d ok', [Kind, Star.Id]));
  end;

  // A Dominion in a star humans can join in; one is made when the galaxy has none there.
  function FindDominion(out Planet: TPlanet): TRuins;
  var
    I: Integer;
    Star: TStar;
  begin
    Result := FindStation(rstDominion, Planet);
    if Result <> nil then
      Exit;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      if (Star.Dominion = nil) and (JoinPlanetIn(Star) <> nil) then
      begin
        Planet := JoinPlanetIn(Star);
        Result := TRuins.Create;
        Result.Init(rstDominion, Star, '');
        Emit(Format('stale dominion made star=%d', [Star.Id]));
        Exit;
      end;
    end;
  end;

  function OtherFreeStar(Dominion: TRuins; Skip: TStar): TStar;
  var
    I: Integer;
  begin
    Result := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
      if (TStar(Galaxy.Stars[I]) <> Dominion.CurrentStar)
          and (TStar(Galaxy.Stars[I]) <> Skip)
          and (TStar(Galaxy.Stars[I]).Dominion = nil) then
        Exit(TStar(Galaxy.Stars[I]));
  end;

  function CountDominionStars(Dominion: TRuins): Integer;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to Galaxy.Stars.Count - 1 do
      if TStar(Galaxy.Stars[I]).Dominion = Dominion then
        Inc(Result);
  end;

  procedure CheckDominion;
  var
    Dominion: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Hull: TItem;
    Ship: TShip;
    BuildA, BuildB, Command: TPlayerCommand;
    I, Part, Before, After, Carried: Integer;
    Problem: AnsiString;
    Target, Other: TStar;
    Built: TList;
  begin
    Dominion := FindDominion(Planet);
    if Dominion = nil then
    begin
      Emit('stale dominion skipped: no star for a Dominion');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Dominion);
    DockAt(B, Dominion);
    // A hull in the Dominion's shop: both build with it; B also with a part from its hold.
    Hull := THull.Create;
    THull(Hull).Init(1000, 8, Dominion.OwnerId, 9, -1, False);
    Dominion.EquipmentShop.Add(Hull);
    BuildA := NewCommand(ckBuildPirateShip);
    BuildB := NewCommand(ckBuildPirateShip);
    Part := -1;
    for I := 0 to B.Player.Inventory.Count - 1 do
      if (Part < 0) and (Ord(TItem(B.Player.Inventory[I]).ItemType) in [43..49]) then
        Part := I;
    for I := 0 to ConstructionPartCount - 1 do
      if I = 0 then
      begin
        AddInt(BuildA, 2);
        AddInt(BuildA, Integer(Hull.Id));
        AddInt(BuildB, 2);
        AddInt(BuildB, Integer(Hull.Id));
      end
      else
      begin
        AddInt(BuildA, 0);
        AddInt(BuildA, 0);
        AddInt(BuildB, 0);
        if (Part >= 0) and (I = Ord(TItem(B.Player.Inventory[Part]).ItemType) - 42) then
          AddInt(BuildB, Integer(TItem(B.Player.Inventory[Part]).Id))
        else
          AddInt(BuildB, 0);
      end;
    AddInt(BuildA, ShopVisibleColumnCount);
    AddInt(BuildB, ShopVisibleColumnCount);
    Problem := CountItems([Dominion.EquipmentShop], [A, B], Before);
    Expect(Problem = '', Problem);
    Expect(TryFor(A, BuildA) = '', 'the first build was refused');
    Expect(Dominion.EquipmentShop.IndexOf(Hull) < 0, 'the built hull is still in the shop');
    Built := TList.Create;
    try
      for I := 0 to Dominion.CurrentStar.Ships.Count - 1 do
      begin
        Ship := TShip(Dominion.CurrentStar.Ships[I]);
        if Ship.Inventory.IndexOf(Hull) >= 0 then
          Built.Add(Ship);
      end;
      Expect(Built.Count = 1, Format('the hull is in %d ships', [Built.Count]));
      Ship := TShip(Built[0]);
    finally
      Built.Free;
    end;
    Carried := B.Player.Inventory.Count;
    ExpectRefused(B, BuildB, rrItemGone, 'the second build');
    Expect(B.Player.Inventory.Count = Carried, 'the refused build took a part from the hold');
    Expect(Ship.Inventory.IndexOf(Hull) >= 0, 'the refused build moved the hull');
    Problem := CountItems([Dominion.EquipmentShop, Ship.Inventory], [A, B], After);
    Expect(Problem = '', Problem);
    Expect(After = Before, Format('the items went from %d to %d', [Before, After]));
    Emit(Format('stale build dominion=%d hull=%d part=%d ok', [Dominion.Id, Hull.Id, Ord(Part >= 0)]));
    // Relocation: B's orders to another star come after A's relocation.
    Dominion.RelocationAge := 1000;
    Dominion.FlyToStar := nil;
    if (Dominion.Order = soTeleport) or Dominion.HasScriptControl then
    begin
      Emit('stale relocation skipped: the Dominion is busy');
      Exit;
    end;
    Target := OtherFreeStar(Dominion, nil);
    Other := OtherFreeStar(Dominion, Target);
    Expect((Target <> nil) and (Other <> nil), 'no free star for the Dominion');
    Command := NewCommand(ckRelocateDominion);
    AddRef(Command, Target);
    Expect(TryFor(A, Command) = '', 'the first relocation was refused');
    Command := NewCommand(ckRelocateDominion);
    AddRef(Command, Other);
    ExpectRefused(B, Command, rrTargetGone, 'the second relocation');
    Command := NewCommand(ckOrderPirateAmbush);
    AddRef(Command, Other);
    ExpectRefused(B, Command, rrTargetGone, 'an ambush after the relocation');
    Command := NewCommand(ckOrderPirateAssault);
    AddRef(Command, Other);
    ExpectRefused(B, Command, rrTargetGone, 'an assault after the relocation');
    Expect(Other.Dominion = nil, 'a refused order pointed a star at the Dominion');
    Expect(
        CountDominionStars(Dominion) = 1,
        Format('%d stars point at the Dominion', [CountDominionStars(Dominion)])
    );
    Emit(Format('stale relocation dominion=%d star=%d ok', [Dominion.Id, Target.Id]));
  end;

  procedure CheckSaleInSpace;
  var
    I, J, Count, Cargo, PartnerCargo, Price: Integer;
    Star: TStar;
    Planet: TPlanet;
    Partner, Ship: TShip;
    A, B: THuman;
    Command: TPlayerCommand;
    Good: Byte;
  begin
    Partner := nil;
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      if (Partner <> nil) or (JoinPlanetIn(Star) = nil) then
        Continue;
      for J := 0 to Star.Ships.Count - 1 do
      begin
        Ship := TShip(Star.Ships[J]);
        if (Partner = nil) and (Ship is TRanger) and not IsHuman(Ship) and Ship.InNormalSpace then
        begin
          Partner := Ship;
          Planet := JoinPlanetIn(Star);
        end;
      end;
    end;
    if Partner = nil then
    begin
      Emit('stale sale skipped: no ranger in space');
      Exit;
    end;
    JoinPair(Planet, A, B);
    Good := 0;
    Count := 1;
    for I := 0 to 1 do
    begin
      if I = 0 then
        Ship := A.Player
      else
        Ship := B.Player;
      Ship.CurrentPlanet := nil;
      Ship.DockedTo := nil;
      Inc(Ship.CargoGoods[Good].Count, Count);
    end;
    A.TalkShip := Partner;
    B.TalkShip := Partner;
    Expect(A.Player.InNormalSpace and B.Player.InNormalSpace, 'the humans are not in space');
    // Room for both sales, and money for the first only.
    if Partner.GetCargoFreeSpace - Partner.GetDesiredCargoFreeSpace < 2 * Count then
      Inc(Partner.GetHull.Weight, 100);
    RefreshTradeRows(A, Partner);
    Price := A.Player.ShopGoodsSellPrice(Good, nil);
    Partner.SetMoney(Count * Price);
    Command := NewCommand(ckTradeGoods);
    AddRef(Command, Partner);
    AddInt(Command, Good);
    AddInt(Command, Count);
    AddInt(Command, 1);
    Expect(TryFor(A, Command) = '', 'the first sale was refused');
    Expect(Partner.Money = 0, Format('the partner has %d after the first sale', [Partner.Money]));
    Cargo := B.Player.CargoGoods[Good].Count;
    PartnerCargo := Partner.CargoGoods[Good].Count;
    ExpectRefused(B, Command, rrNoMoney, 'the second sale');
    Expect(B.Player.CargoGoods[Good].Count = Cargo, 'the refused seller lost its goods');
    Expect(
        (Partner.Money = 0) and (Partner.CargoGoods[Good].Count = PartnerCargo),
        'the refused sale changed the partner'
    );
    A.TalkShip := nil;
    B.TalkShip := nil;
    Emit(Format('stale sale partner=%d price=%d ok', [Partner.Id, Price]));
  end;

  procedure CheckMap;
  var
    I, J: Integer;
    Star: TStar;
    Planet: TPlanet;
    Map, Next, Other: TConstellation;
    A, B: THuman;
    Command: TPlayerCommand;
  begin
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
      if (Planet = nil)
          and (JoinPlanetIn(TStar(Galaxy.Stars[I])) <> nil)
          and (JoinPlanetIn(TStar(Galaxy.Stars[I])).FindUnchartedNeighborConstellation <> nil) then
        Planet := JoinPlanetIn(TStar(Galaxy.Stars[I]));
    // Every neighbour is charted: one is hidden again for the test.
    if Planet = nil then
      for I := 0 to Galaxy.Stars.Count - 1 do
      begin
        Star := TStar(Galaxy.Stars[I]);
        if (Planet <> nil) or (JoinPlanetIn(Star) = nil) then
          Continue;
        for J := 0 to Galaxy.Constellations.Count - 1 do
        begin
          Other := TConstellation(Galaxy.Constellations[J]);
          if (Planet = nil)
              and (Other <> Star.Constellation)
              and (Other.Id <> 20)
              and Other.SharesOutlineSegment(Star.Constellation) then
          begin
            Other.Visible := False;
            Planet := JoinPlanetIn(Star);
          end;
        end;
      end;
    if Planet = nil then
    begin
      Emit('stale map skipped: no constellation to chart');
      Exit;
    end;
    JoinPair(Planet, A, B);
    Map := Planet.FindUnchartedNeighborConstellation;
    Command := NewCommand(ckBuyMap);
    AddRef(Command, Map);
    Expect(TryFor(A, Command) = '', 'the first map was refused');
    Expect(Map.Visible, 'the first map charted nothing');
    Next := Planet.FindUnchartedNeighborConstellation;
    ExpectRefused(B, Command, rrOfferGone, 'the second map');
    Expect((Next = nil) or not Next.Visible, 'the refused map charted another constellation');
    Emit(Format('stale map constellation=%d next=%d ok', [Map.Id, Ord(Next <> nil)]));
  end;

  procedure CheckSurfaceLoot;
  var
    I, Before, After: Integer;
    Planet: TPlanet;
    A, B: THuman;
    Items: array[0..1] of TItem;
    Entry: PPlanetSurfaceLootEntry;
    Command: TPlayerCommand;
    Problem: AnsiString;
  begin
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
      if Planet = nil then
        Planet := JoinPlanetIn(TStar(Galaxy.Stars[I]));
    Expect(Planet <> nil, 'no planet for the surface loot');
    JoinPair(Planet, A, B);
    // Two items on the surface, after what is there.
    if Planet.SurfaceLootEntries = nil then
      Planet.SurfaceLootEntries := TList.Create;
    for I := 0 to 1 do
    begin
      Items[I] := THull.Create;
      THull(Items[I]).Init(10, 1, 0, 1, -1, False);
      New(Entry);
      FillChar(Entry^, SizeOf(Entry^), 0);
      Entry.Item := Items[I];
      Planet.SurfaceLootEntries.Add(Entry);
    end;
    Problem := CountItems([], [A, B], Before);
    Expect(Problem = '', Problem);
    // Both saw the two items at I and I + 1.
    I := Planet.SurfaceLootEntries.Count - 2;
    Command := NewCommand(ckPickUpSurfaceLoot);
    AddInt(Command, I);
    AddInt(Command, Integer(Items[0].Id));
    Expect(TryFor(A, Command) = '', 'the first pickup was refused');
    ExpectRefused(B, Command, rrItemGone, 'the second pickup');
    Command := NewCommand(ckPickUpSurfaceLoot);
    AddInt(Command, I + 1);
    AddInt(Command, Integer(Items[1].Id));
    Expect(TryFor(B, Command) = '', 'the pickup of an item that moved was refused');
    Expect(A.Player.Inventory.IndexOf(Items[0]) >= 0, 'the first item is not the first human''s');
    Expect(B.Player.Inventory.IndexOf(Items[1]) >= 0, 'the second item is not the second human''s');
    Problem := CountItems([], [A, B], After);
    Expect(Problem = '', Problem);
    Expect(After = Before + 2, Format('the items went from %d to %d', [Before, After]));
    Emit(Format('stale surface loot planet=%d ok', [Planet.Id]));
  end;

  // A station whose ship humans can see, in a star with a planet humans can join at.
  function FindAnyStation(out Planet: TPlanet): TRuins;
  const
    Types: array[0..5] of TStationType = (
        rstScienceBase,
        rstMilitaryBase,
        rstPirateBase,
        rstBusinessCenter,
        rstRangerCenter,
        rstMedicalBase
    );
  var
    I: Integer;
  begin
    Result := nil;
    Planet := nil;
    for I := 0 to High(Types) do
      if Result = nil then
        Result := FindStation(Types[I], Planet);
  end;

  function OpenShipCommand(Ship: TShip): TPlayerCommand;
  begin
    Result := NewCommand(ckOpenShipScreen);
    AddRef(Result, Ship);
    AddInt(Result, 0);
  end;

  function CloseShipCommand: TPlayerCommand;
  begin
    Result := NewCommand(ckCloseShipScreen);
    AddInt(Result, 0);
  end;

  // The hold cell (not expanded) of the human's view that shows Item, or -1.
  function HoldCellOf(Human: THuman; Item: TItem): Integer;
  var
    I: Integer;
  begin
    Result := -1;
    if Human.PlayerHoldEntries <> nil then
      for I := 0 to Human.PlayerHoldEntries.Count - 1 do
        if TPlayerHoldUnit(Human.PlayerHoldEntries[I]).Item = Item then
          Exit(I);
  end;

  function TakeCellCommand(Cell: Integer; Item: TItem): TPlayerCommand;
  begin
    Result := NewCommand(ckTakeHoldEntry);
    AddInt(Result, Cell);
    AddInt(Result, 0);
    AddInt(Result, Integer(Item.Id));
  end;

  // A sponsored station's ship: one human edits it at a time, and a take from a hold cell that
  // another human emptied is refused without holding the item.
  procedure CheckSharedShip;
  var
    Station: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Item: TItem;
    Command: TPlayerCommand;
    Cell, Before, After: Integer;
    Problem: AnsiString;
  begin
    Station := FindAnyStation(Planet);
    if Station = nil then
    begin
      Emit('stale shared ship skipped: no station');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    DockAt(B, Station);
    Station.ModernizationSponsor := True;
    Item := THull.Create;
    THull(Item).Init(10, 1, 0, 1, -1, False);
    Station.Inventory.Add(Item);
    A.Player.FreeExperience := 100;
    B.Player.FreeExperience := 200;
    Station.FreeExperience := 7;
    // B saw the item in the station's hold before A came.
    Expect(TryFor(B, OpenShipCommand(Station)) = '', 'the first open was refused');
    Expect(TryFor(B, NewCommand(ckRefreshHoldView)) = '', 'the hold view was refused');
    Cell := HoldCellOf(B, Item);
    Expect(Cell >= 0, 'the station''s hold does not show the item');
    Expect(TryFor(B, CloseShipCommand) = '', 'the close was refused');
    // A opens the ship, and B cannot while A has it open.
    Expect(TryFor(A, OpenShipCommand(Station)) = '', 'the open of a free ship was refused');
    Expect(Station.FreeExperience = 100, 'the ship does not show the editor''s experience');
    ExpectRefused(B, OpenShipCommand(Station), rrInUse, 'a second human opening the ship');
    Expect(
        (B.EditedShip = nil) and (B.Player.FreeExperience = 200) and (Station.FreeExperience = 100),
        'the refused open changed the experience'
    );
    // A takes the item and stores it.
    Expect(TryFor(A, NewCommand(ckRefreshHoldView)) = '', 'the hold view was refused');
    Expect(TryFor(A, TakeCellCommand(HoldCellOf(A, Item), Item)) = '', 'the first take was refused');
    Command := NewCommand(ckStoreHeld);
    AddInt(Command, -1);
    AddInt(Command, 1);
    Expect(TryFor(A, Command) = '', 'the item could not be stored');
    Expect(TryFor(A, CloseShipCommand) = '', 'the close was refused');
    Expect(
        (A.EditedShip = nil) and (A.Player.FreeExperience = 100) and (Station.FreeExperience = 7),
        'the close did not give the experience back'
    );
    // B opens again, with its view where the cell still shows the item.
    Problem := CountItems([Station.Inventory], [A, B], Before);
    Expect(Problem = '', Problem);
    Expect(TryFor(B, OpenShipCommand(Station)) = '', 'the open after the editor left was refused');
    ExpectRefused(B, TakeCellCommand(Cell, Item), rrItemGone, 'a take from a stale cell');
    Command := NewCommand(ckTakeHoldEntry);
    AddInt(Command, Cell);
    AddInt(Command, 0);
    ExpectRefused(B, Command, rrItemGone, 'a take from a stale cell, as an old log has it');
    Expect(
        (B.SelectedHoldKind = phkEmpty) and (B.SelectedHoldItem = nil),
        'the refused take holds the item'
    );
    Problem := CountItems([Station.Inventory], [A, B], After);
    Expect(Problem = '', Problem);
    Expect(After = Before, Format('the items went from %d to %d', [Before, After]));
    // B goes without closing the screen (a disconnect holds its position): the ship is free.
    SubmitKindFor(B, ckHoldPosition);
    Expect(
        (B.EditedShip = nil) and (B.Player.FreeExperience = 200) and (Station.FreeExperience = 7),
        'holding position did not free the ship'
    );
    Expect(TryFor(A, OpenShipCommand(Station)) = '', 'the ship stayed taken after its editor went');
    Expect(TryFor(A, CloseShipCommand) = '', 'the close was refused');
    Emit(Format('stale shared ship station=%d item=%d ok', [Station.Id, Item.Id]));
  end;

  // A second payment for a station's modernization, which the first one bought.
  procedure CheckModernization;
  var
    Station: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Command: TPlayerCommand;
  begin
    Station := FindAnyStation(Planet);
    if Station = nil then
    begin
      Emit('stale modernization skipped: no station');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    DockAt(B, Station);
    Station.ModernizationSponsor := False;
    Command := NewCommand(ckPayForModernization);
    AddInt(Command, Max(1, Station.CalculateEquippedItemCostWithoutHull));
    Expect(TryFor(A, Command) = '', 'the first payment was refused');
    Expect(Station.ModernizationSponsor, 'the first payment bought nothing');
    ExpectRefused(B, Command, rrOfferGone, 'the second payment');
    Emit(Format('stale modernization station=%d ok', [Station.Id]));
  end;

  // A ranger in space in a star with a planet humans can join at; nil when there is none.
  function FindRangerInSpace(out Planet: TPlanet): TShip;
  var
    I, J: Integer;
    Star: TStar;
    Ship: TShip;
  begin
    Result := nil;
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
    begin
      Star := TStar(Galaxy.Stars[I]);
      if (Result <> nil) or (JoinPlanetIn(Star) = nil) then
        Continue;
      for J := 0 to Star.Ships.Count - 1 do
      begin
        Ship := TShip(Star.Ships[J]);
        if (Result = nil) and (Ship is TRanger) and not IsHuman(Ship) and Ship.InNormalSpace then
        begin
          Result := Ship;
          Planet := JoinPlanetIn(Star);
        end;
      end;
    end;
  end;

  // Gifts beyond the money, a truce that would replace another human's, and a deposit beyond
  // the money.
  procedure CheckGiftsTruceDeposit;
  var
    Partner: TShip;
    Planet: TPlanet;
    Station: TRuins;
    A, B: THuman;
    Command: TPlayerCommand;
    Money: Integer;
  begin
    Partner := FindRangerInSpace(Planet);
    if Partner = nil then
      Emit('stale gift skipped: no ranger in space')
    else
    begin
      JoinPair(Planet, A, B);
      A.TalkShip := Partner;
      A.Player.SetMoney(50);
      Money := Partner.Money;
      Command := NewCommand(ckGivePartnerGift);
      AddInt(Command, 100);
      ExpectRefused(A, Command, rrNoMoney, 'a partner gift beyond the money');
      Command := NewCommand(ckGivePiratePartnerGift);
      AddInt(Command, 100);
      ExpectRefused(A, Command, rrNoMoney, 'a pirate partner gift beyond the money');
      Expect(Partner.Money = Money, 'a refused gift paid the partner');
      Command := NewCommand(ckGivePartnerGift);
      AddInt(Command, 50);
      Expect(TryFor(A, Command) = '', 'a gift of the money there is was refused');
      Expect(
          (A.Player.Money = 0) and (Partner.Money = Money + 50),
          'the gift did not move its money'
      );
      A.TalkShip := nil;
      // A has a truce with the ranger; B's offer would replace it.
      Partner.TruceWithShip(A.Player);
      B.TalkShip := Partner;
      Command := NewCommand(ckShowTruceOffer);
      Expect(TryFor(B, Command) = '', 'the truce offer was refused');
      Expect(TalkOutcome = toRefused, 'the ranger offered a second human a truce');
      Command := NewCommand(ckAcceptTruceOffer);
      AddInt(Command, 10);
      ExpectRefused(B, Command, rrTargetGone, 'a truce that replaces another human''s');
      Expect(
          (Partner.TruceShip = A.Player) and (A.Player.TruceShip = Partner),
          'the refused truce replaced the first'
      );
      B.TalkShip := nil;
      Emit(Format('stale gift truce partner=%d ok', [Partner.Id]));
    end;
    Station := FindStation(rstBusinessCenter, Planet);
    if Station = nil then
    begin
      Emit('stale deposit skipped: no business center');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    A.Player.SetMoney(1000);
    Command := NewCommand(ckOpenDeposit);
    AddInt(Command, 5000);
    AddFloat(Command, 3.0);
    ExpectRefused(A, Command, rrNoMoney, 'a deposit beyond the money');
    Expect(A.Player.DepositAmount = 0, 'the refused deposit was opened');
    Command := NewCommand(ckOpenDeposit);
    AddInt(Command, 1000);
    AddFloat(Command, 3.0);
    Expect(TryFor(A, Command) = '', 'a deposit of the money there is was refused');
    Expect(
        (A.Player.DepositAmount = 1000) and (A.Player.Money = 0),
        'the deposit did not take its money'
    );
    Emit(Format('stale deposit station=%d ok', [Station.Id]));
  end;

  // Another human's medals and interceptors, and a configuration that is not there.
  procedure CheckOwnership;
  var
    Planet: TPlanet;
    A, B: THuman;
    Command: TPlayerCommand;
    I, First, Visible: Integer;
  begin
    Planet := nil;
    for I := 0 to Galaxy.Stars.Count - 1 do
      if Planet = nil then
        Planet := JoinPlanetIn(TStar(Galaxy.Stars[I]));
    Expect(Planet <> nil, 'no planet to join at');
    JoinPair(Planet, A, B);
    if A.Player.AwardIds = nil then
      A.Player.AwardIds := TList.Create;
    while A.Player.AwardIds.Count < 2 do
      A.Player.AwardIds.Add(Pointer(PtrInt(A.Player.AwardIds.Count + 1)));
    First := PtrInt(A.Player.AwardIds[0]);
    Visible := A.Player.AwardVisibleCount;
    Command := NewCommand(ckExchangeAwards);
    AddRef(Command, A.Player);
    AddInt(Command, 0);
    AddInt(Command, 1);
    ExpectRefused(B, Command, rrOther, 'reordering another human''s medals');
    Expect(PtrInt(A.Player.AwardIds[0]) = First, 'the refused exchange moved the medals');
    Expect(TryFor(A, Command) = '', 'reordering the human''s own medals was refused');
    Command := NewCommand(ckChangeAwardVisibleCount);
    AddRef(Command, A.Player);
    AddInt(Command, -1);
    ExpectRefused(B, Command, rrOther, 'changing another human''s shown medals');
    Expect(A.Player.AwardVisibleCount = Visible, 'the refused change showed other medals');
    Command := NewCommand(ckRecallInterceptors);
    AddRef(Command, A.Player);
    ExpectRefused(B, Command, rrTargetGone, 'recalling interceptors that are not the human''s');
    Command := NewCommand(ckChooseEquipmentConfiguration);
    AddInt(Command, 10);
    AddInt(Command, 1);
    ExpectRefused(A, Command, rrOther, 'an equipment configuration that is not there');
    Emit('stale ownership ok');
  end;

  // A side change priced up by another human's, and the nodes of an empty base.
  procedure CheckPirateBase;
  var
    Station: TRuins;
    Planet: TPlanet;
    A, B: THuman;
    Command: TPlayerCommand;
    I, Quote, Owner: Integer;
  begin
    Station := FindStation(rstPirateBase, Planet);
    if Station = nil then
    begin
      Emit('stale pirate base skipped: no pirate base');
      Exit;
    end;
    JoinPair(Planet, A, B);
    DockAt(A, Station);
    DockAt(B, Station);
    // The quote, as TfRuinsTalk.ShowPirateBaseSideChangeDialog computes it.
    Quote := Galaxy.ComputeScaledHugeMoney(2);
    for I := Galaxy.GalaxyEvents.Count - 1 downto 0 do
    begin
      if TGalaxyEvent(Galaxy.GalaxyEvents[I]).Turn + 365 < Galaxy.CurrentTurn then
        Break;
      if TGalaxyEvent(Galaxy.GalaxyEvents[I]).EventType = 'PlayerChangesSide' then
        Quote := Min(Int64(100000000), Round(Quote * 1.5));
    end;
    if Quote >= 100000000 then
      Emit('stale side change skipped: the price is at its limit')
    else
    begin
      Command := NewCommand(ckChangeSide);
      AddInt(Command, Quote);
      Expect(TryFor(A, Command) = '', 'the first side change was refused');
      Owner := B.Player.OwnerId;
      ExpectRefused(B, Command, rrOfferGone, 'a side change at a price that went up');
      Expect(B.Player.OwnerId = Owner, 'the refused side change changed the side');
      Emit(Format('stale side change quote=%d ok', [Quote]));
    end;
    Station.NodeReserve := 0;
    ExpectRefused(A, NewCommand(ckBuyPirateNodes), rrOutOfStock, 'nodes of a base that has none');
    Emit(Format('stale pirate nodes station=%d ok', [Station.Id]));
  end;

begin
  Result := 0;
  Joined := 0;
  try
    CheckSpecialShip;
    CheckSatellite;
    CheckInvestment;
    CheckDominion;
    CheckSaleInSpace;
    CheckMap;
    CheckSurfaceLoot;
    CheckSharedShip;
    CheckModernization;
    CheckGiftsTruceDeposit;
    CheckOwnership;
    CheckPirateBase;
    Emit('stale commands ok');
  except
    on E: EAbort do
      Result := 1;
  end;
end;

// CHANGE: ENHANCEMENT - --sim-text-quest=ID|NAME (docs/progress/2026-10-19-text-quests-plan.md,
// Phase A): the save's planet quests (the planets whose TextQuestId is set, in the galaxy's
// order), then the player parked as the turn runner parks it plays the quest on the quest
// screen's terms with the headless quest player: one line per page, the outcome, and the state
// hash after it. Single player only.
function RunTextQuest(const Options: TSimulationOptions): Integer;
var
  I, Count, First: Integer;
  Planet: TPlanet;
  Player: THeadlessQuestPlayer;
  Outcome: TQuestRunOutcome;
  Died: Boolean;
begin
  Result := 0;
  if Session.Humans.Count > 1 then
    raise Exception.Create('--sim-text-quest takes a single-player save');
  Count := 0;
  First := -1;
  for I := 0 to Galaxy.Planets.Count - 1 do
  begin
    Planet := TPlanet(Galaxy.Planets[I]);
    if Planet.TextQuestId <> -1 then
    begin
      Inc(Count);
      if First < 0 then
        First := Planet.TextQuestId;
    end;
  end;
  Emit(Format('quest save planet-quests=%d first=%d', [Count, First]));
  ParkObserverPlayer;
  // The galaxy's days in the quest see the human on the quest screen, as in the game.
  CurrentScreenId := screenPlanetQuest;
  RequestedScreenId := screenNone;
  Player := THeadlessQuestPlayer.Create(Options.Seed);
  try
    Outcome := Player.Play(UTF8Decode(Options.TextQuest));
    Emit(
        Format(
            'quest done name=%s outcome=%s pages=%d steps=%d days=%d errors=%d',
            [Options.TextQuest, QuestOutcomeName(Outcome), Player.Pages, Player.Steps,
                Player.Run.DaysElapsed, Player.Errors]
        )
    );
    Died := Player.Run.Died;
  finally
    Player.Free;
  end;
  CurrentScreenId := screenPlanet;
  // A ranger who died in the quest is gone and the game over: there is no state to save.
  if Died then
    Emit('quest state none: the ranger died')
  else
    EmitHash(0, Options.DumpDirectory);
  Emit(Format('done text-quest day=%d', [Galaxy.CurrentTurn]));
end;

procedure GiveProbePlanetQuest(Human: THuman; Planet: TObject);
var
  Quest: PQuest;
  Target: TPlanet;
begin
  Target := Planet as TPlanet;
  New(Quest);
  Quest.QuestType := qtPlanetQuest;
  Quest.QuestNumber := Word(Target.TextQuestId);
  Quest.Planet := Target;
  Quest.DeadlineTurn := Galaxy.CurrentTurn + 100;
  Quest.RewardMoney := 1000;
  Quest.ObjectiveTarget := Target;
  Quest.Successful := False;
  Quest.Description := 'Probe';
  Quest.CompletionText := '';
  Quest.SpecialCompletionText := '';
  Human.Player.Quests.Add(Quest);
end;

// Human's BeginTextQuest for Planet's quest: 'applied', or the refusal's name.
function TryBeginPlanetQuest(Human: THuman; Planet: TPlanet): AnsiString;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckBeginTextQuest);
  AddInt(Command, tqkPlanet);
  AddRef(Command, Planet);
  Result := 'applied';
  try
    SubmitFor(Human, Command);
  except
    on E: ECommandRefused do
      Result := RefusalReasonName(E.Reason);
  end;
end;

// CHANGE: ENHANCEMENT - --sim-quest-lock (docs/progress/2026-10-19-text-quests-plan.md, Phase
// B, the lock): two humans join at the first inhabited planet with a text quest, and both hold
// a government quest to it. The first plays it from its visit (TQuestRun.Open) with the
// headless quest player; while it plays, the second's BeginTextQuest must be refused
// (in-use); once the quest has ended (and the planet's quest is gone), again (offer-gone).
function RunQuestLock(const Options: TSimulationOptions): Integer;
var
  I: Integer;
  Planet, Candidate: TPlanet;
  A, B: THuman;
  Player: THeadlessQuestPlayer;
  Opened: Boolean;
  Outcome: TQuestRunOutcome;
  WhilePlaying, After: AnsiString;
begin
  Result := 0;
  Planet := nil;
  for I := 0 to Galaxy.Planets.Count - 1 do
  begin
    Candidate := TPlanet(Galaxy.Planets[I]);
    if (Candidate.TextQuestId <> -1)
        and not Candidate.NoLanding
        and (Candidate.OwnerId <= Byte(oiGaal)) then
    begin
      Planet := Candidate;
      Break;
    end;
  end;
  if Planet = nil then
  begin
    Emit('quest lock skipped: no inhabited planet with a text quest');
    Exit;
  end;
  A := JoinHumanAt(Planet, 'HumanA', 1);
  B := JoinHumanAt(Planet, 'HumanB', 2);
  GiveProbePlanetQuest(A, Planet);
  GiveProbePlanetQuest(B, Planet);
  SetLocalHuman(A);
  CurrentScreenId := screenPlanet;
  RequestedScreenId := screenNone;
  Player := THeadlessQuestPlayer.Create(Options.Seed);
  try
    Opened := Player.OpenVisit;
    Emit(
        Format(
            'quest lock planet=%d quest=%d first=%d open=%d locked=%d',
            [Planet.Id, Planet.TextQuestId, Ord(Opened), Ord(A.TextQuestOpen),
                Ord(A.TextQuestPlanetId = Planet.Id)]
        )
    );
    WhilePlaying := TryBeginPlanetQuest(B, Planet);
    Outcome := Player.Finish;
  finally
    Player.Free;
  end;
  After := TryBeginPlanetQuest(B, Planet);
  Emit(
      Format(
          'quest lock outcome=%s quest=%d released=%d while-playing=%s after=%s',
          [QuestOutcomeName(Outcome), Planet.TextQuestId, Ord(not A.TextQuestOpen), WhilePlaying,
              After]
      )
  );
  if Opened and (WhilePlaying = 'in-use') and (After = 'offer-gone') and not A.TextQuestOpen
      and not B.TextQuestOpen then
    Emit('quest lock ok')
  else
  begin
    Emit('quest lock failed');
    Result := 1;
  end;
  Emit(Format('done quest-lock humans=%d', [Session.Humans.Count]));
end;

procedure EmitHumans(const Options: TSimulationOptions);
var
  Lines: TStringList;
  I: Integer;
begin
  if not Options.HumansDump then
    Exit;
  Lines := TStringList.Create;
  try
    DescribeHumans(Lines);
    for I := 0 to Lines.Count - 1 do
      Emit('state ' + Lines[I]);
  finally
    Lines.Free
  end;
end;

function RunHeadlessSimulation(const Options: TSimulationOptions): Integer;
var
  Turn: Integer;
  Killed: TList;
begin
  Result := 0;
  LoadSave(Options.SavePath, Options.Seed);
  if Options.SharedShop then
  begin
    Result := RunSharedShop(Options);
    Exit;
  end;
  if Options.SharedStorage then
  begin
    Result := RunSharedStorage(Options);
    Exit;
  end;
  if Options.SharedQuests then
  begin
    Result := RunSharedQuests(Options);
    Exit;
  end;
  if Options.ScriptRouting then
  begin
    Result := RunScriptRouting(Options);
    Exit;
  end;
  if Options.StaleCommands then
  begin
    Result := RunStaleCommands(Options);
    Exit;
  end;
  // With --sim-hotseat, the hot-seat run plays the quest (RunHotSeat).
  if (Options.TextQuest <> '') and (Options.HotSeatDays <= 0) then
  begin
    Result := RunTextQuest(Options);
    Exit;
  end;
  if Options.QuestLock then
  begin
    Result := RunQuestLock(Options);
    Exit;
  end;
  if Options.Pvp then
  begin
    Result := RunPvp(Options);
    Emit(Format('done pvp humans=%d', [Session.Humans.Count]));
    Exit;
  end;
  JoinHumans(Options.Humans);
  Emit(Format('sim save=%s seed=%d day=%d', [Options.SavePath, Options.Seed, Galaxy.CurrentTurn]));
  if Options.RoundTrip then
  begin
    if Options.SessionProbe then
      ProbeSession;
    if not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
      Result := 1;
    // Simulate from the save itself, not from its round-tripped copy.
    if Options.Turns > 0 then
    begin
      LoadSave(Options.SavePath, Options.Seed);
      JoinHumans(Options.Humans);
    end;
  end;
  if Options.HotSeatDays > 0 then
  begin
    Result := RunHotSeat(Options);
    Exit;
  end;
  if Options.Turns <= 0 then
  begin
    EmitHumans(Options);
    Exit;
  end;
  ParkObserverPlayer;
  CurrentScreenId := screenPlanet;
  RequestedScreenId := screenNone;
  if Options.Hash and not Options.HashLastOnly then
    EmitHash(0, Options.DumpDirectory);
  Killed := TList.Create;
  try
    for Turn := 1 to Options.Turns do
    begin
      if Turn = Options.KillHumansAt then
        KillHumans(Killed);
      SimulateParkedTurn;
      if Turn = Options.KillHumansAt then
        ReportRespawns(Killed);
      if Turn = Options.ReloadAt then
        ReloadFromCheckpoint;
      if Options.Hash and (not Options.HashLastOnly or (Turn = Options.Turns)) then
        EmitHash(Turn, Options.DumpDirectory);
    end;
  finally
    Killed.Free;
  end;
  // A game that has run turns holds script references made during play, which
  // a round trip from the save alone does not exercise.
  if Options.RoundTrip and Options.SessionProbe then
    ProbeSession;
  if Options.RoundTrip and not CheckRoundTrip(Options.DumpDirectory, Options.Seed) then
    Result := 1;
  EmitHumans(Options);
  Emit(
      Format(
          'done turns=%d day=%d humans=%d',
          [Options.Turns, Galaxy.CurrentTurn, Session.Humans.Count]
      )
  );
end;

end.
