{$EXCESSPRECISION OFF}
unit HeadlessSim;

// CHANGE: ENHANCEMENT - Headless turn runner and state hash for regression tests.
// Loads a save, parks the player as the observer does, advances turns without
// a window and prints one line per result. The state hash covers the bytes
// TGalaxy.SaveToBuffer writes, so the save writer is the only serialiser.
interface
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
  end;
function RunHeadlessSimulation(const Options: TSimulationOptions): Integer;
implementation
uses
  SysUtils,
  Classes,
  EC_Buf,
  EC_Expression,
  Globals,
  GlobalsV,
  aMyFunction,
  aGalaxy,
  aGalaxyEvent,
  aGalaxyStruct,
  aHold,
  aHuman,
  aCommands,
  aItem,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aObjectRefs,
  aRanger,
  aScript,
  aShip,
  aShopStock,
  aSaveLoad,
  aSession,
  SaveTrace,
  ThreadCalc,
  aMissile,
  WorkerErrors,
  ObserverHooks,
  ObserverSimulation;

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

procedure LoadSave(const FileName: AnsiString; Seed: Cardinal);
begin
  if not LoadGameFromFile(UTF8Decode(FileName)) then
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
  Lines.Add(
      Format(
          'session textquests-off=%d friendly-fire=%d',
          [Ord(Session.TextQuestsDisabled), Ord(Session.FriendlyFireEnabled)]
      )
  );
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

// Gives the session, the humans, the scripts and an event state that a load without the
// per-human save block would lose: the flags, set by command, a cheat for every human, the
// other humans' THuman state with a shop for those who are landed, scripts bound to every
// human in turn, and the last event bound to the last human. With more than one human, the
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
  SetSessionFlagValue(SessionFlagTextQuestsDisabled, True);
  SetSessionFlagValue(SessionFlagFriendlyFire, False);
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Human.RecordCheat('Probe' + WideString(IntToStr(Human.Id)), I + 1);
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
    AddInt(Command, SessionFlagTextQuestsDisabled);
    AddInt(Command, 0);
    SubmitCommand(Command);
    if Session.TextQuestsDisabled then
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
// that holds no other human. The choice depends only on the galaxy, so runs repeat.
procedure JoinHumans(Total: Integer);
var
  I: Integer;
  Planet: TPlanet;
  Human: THuman;
begin
  I := 0;
  while Session.Humans.Count < Total do
  begin
    if I >= Galaxy.Planets.Count then
      raise Exception.Create('Not enough coalition planets for the humans');
    Planet := TPlanet(Galaxy.Planets[I]);
    Inc(I);
    if (Planet.OwnerId > Byte(oiGaal))
        or (Planet.CurrentStar.ControlFaction <> sfCoalition)
        or StarHasHuman(Planet.CurrentStar) then
      Continue;
    Human := JoinHuman(
        Planet,
        'Human' + IntToStr(Session.Humans.Count + 1),
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
