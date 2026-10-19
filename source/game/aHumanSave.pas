{$EXCESSPRECISION OFF}
unit aHumanSave;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - The per-human save block (ROADMAP.md, Phase 4, items 5 and 10).
// TGalaxy.SaveToBuffer appends it after the original layout and the object reference table
// (aObjectRefs). It holds what the original layout has no room for:
// - the session flags (aSession);
// - every human, in Session.Humans order and keyed by id: the cheats it has used and, for
//   every human but the local one, the THuman state the original layout writes for the
//   local human only;
// - the human each script is bound to (TScript.HumanId);
// - the human each galaxy event is about (TGalaxyEvent.HumanId);
// - since version 2, whether each human's game has ended (THuman.Finished, FinishReason);
// - since version 3, the items of the open shop grids that do not write them (aShopStock:
//   a second grid at a location writes its slots empty), by id, so that a load shows them
//   again;
// - since version 4, the game days each human owes for a text quest (THuman.QuestDaysOwed).
// It is written only when some of this differs from what a save without it loads as: more
// than one human, a flag that is not its default, a cheat on record, or a script or event
// bound to a human other than the first. A single-player save is therefore byte for byte as
// before and loads by the original layout rules. A human whose game has ended also needs it.
//
// Layout: 'SRHU', a version, the byte size of the rest, then the fields below. A later
// version only appends fields; a reader reads the ones it knows and skips to the end.
interface
uses
  EC_Buf,
  aGalaxy;
// Whether Galaxy's save needs the block.
function HumanSaveBlockNeeded(Galaxy: TGalaxy): Boolean;
// Appends the block when it is needed.
procedure SaveHumanBlock(Galaxy: TGalaxy; Buffer: TBufEC);
// Reads the block if the buffer holds one at its position, and applies it to the humans
// the load has rebuilt, the scripts and the events. A buffer without it is left as it was.
procedure LoadHumanBlock(Galaxy: TGalaxy; Buffer: TBufEC);
// The session state the block holds that a new galaxy starts without: the flags and the
// local human's cheats. The other humans are created afresh.
procedure ResetHumanSessionState;
implementation
uses
  Classes,
  EC_Expression,
  Globals,
  aGalaxyEvent,
  aGalaxyStruct,
  aHold,
  aHuman,
  aPlanet,
  aPlayer,
  aRanger,
  aRuins,
  aScript,
  aSession,
  aShip,
  aShopStock;

const
  HumanBlockMagic = $55485253; // 'SRHU'
  // 2: whether each human's game has ended.
  // 3: the items of the shop grids that write their slots empty.
  // 4: the days each human owes for a text quest.
  HumanBlockVersion = 4;

procedure ResetHumanSessionState;
begin
  ResetSessionFlags;
  LocalHuman.ClearCheats;
  LocalHuman.Finished := False;
  LocalHuman.FinishReason := -1;
  LocalHuman.QuestDaysOwed := 0;
end;

function FirstHumanId: Integer;
begin
  if Session.Humans.Count > 0 then
    Result := Session.Humans[0].Id
  else
    Result := -1;
end;

// A save without the block loads every script and event as bound to the first human, and
// -1 means the same.
function IsDefaultBinding(HumanId: Integer): Boolean;
begin
  Result := (HumanId = -1) or (HumanId = FirstHumanId);
end;

function HumanSaveBlockNeeded(Galaxy: TGalaxy): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Session.Humans.Count > 1 then
    Exit;
  if not SessionFlagsAreDefault then
    Exit;
  for I := 0 to Session.Humans.Count - 1 do
    if Session.Humans[I].HasCheated
        or Session.Humans[I].Finished
        or (Session.Humans[I].QuestDaysOwed > 0) then
      Exit;
  if Galaxy.Scripts <> nil then
    for I := 0 to Galaxy.Scripts.Count - 1 do
      if not IsDefaultBinding(TScript(Galaxy.Scripts[I]).HumanId) then
        Exit;
  if Galaxy.GalaxyEvents <> nil then
    for I := 0 to Galaxy.GalaxyEvents.Count - 1 do
      if not IsDefaultBinding(TGalaxyEvent(Galaxy.GalaxyEvents[I]).HumanId) then
        Exit;
  Result := False;
end;

function ShipId(Ship: TShip): Cardinal;
begin
  if Ship = nil then
    Result := 0
  else
    Result := Cardinal(Ship.Id);
end;

// The state the original layout writes for the local human. What only the screens use (the
// hangar's slots, the hold order, the star map's weapon panel) is left out of the state hash,
// as the original layout's own copies are.
procedure SaveHumanState(Human: THuman; Buffer: TBufEC);
var
  I, Count: Integer;
  Hashing: Boolean;
  Message: TMessagePlayer;
  OldQuest: PPlayerOldQuest;
  Entry: TPlayerHoldUnit;
begin
  Hashing := Assigned(SnapshotObjectIdentity);
  if Human.PlayerStar = nil then
    Buffer.AddDWord(0)
  else
    Buffer.AddDWord(Cardinal(Human.PlayerStar.Id));
  Buffer.AddDWord(ShipId(Human.PendingPlayerFollowTarget));
  Buffer.AddBoolean(Human.PlayerAutomaticControl);
  Buffer.AddBoolean(Human.PlayerEquipmentBrokenThisTurn);
  Buffer.AddByte(Human.PlayerDialogueRequestCount);
  Buffer.AddDWord(Human.ShownPlayerTips);
  Buffer.AddBoolean(Human.StarMapWeaponPanelOpen and not Hashing);
  for I := 0 to 8 do
    if Hashing then
      Buffer.AddDWord(0)
    else
      Buffer.AddDWord(Cardinal(Human.HangarShipIds[I]));
  if Hashing or (Human.PlayerHoldEntries = nil) then
    Buffer.AddIntegerValue(0)
  else
  begin
    Buffer.AddIntegerValue(Human.PlayerHoldEntries.Count);
    for I := 0 to Human.PlayerHoldEntries.Count - 1 do
    begin
      Entry := TPlayerHoldUnit(Human.PlayerHoldEntries[I]);
      Buffer.AddByte(Byte(Entry.Kind));
      Buffer.AddByte(Entry.GoodsIndex);
      Buffer.AddDWord(Cardinal(Entry.ItemId));
    end;
  end;
  PersistentPlayerMessageLock.Enter;
  try
    Count := 0;
    Message := Human.FirstPersistentPlayerMessage;
    while Message <> nil do
    begin
      Inc(Count);
      Message := Message.Next;
    end;
    Buffer.AddIntegerValue(Count);
    Message := Human.FirstPersistentPlayerMessage;
    while Message <> nil do
    begin
      Message.SaveToBuffer(Buffer);
      Message := Message.Next;
    end;
  finally
    PersistentPlayerMessageLock.Leave;
  end;
  if Human.PlayerOldQuests = nil then
    Buffer.AddIntegerValue(0)
  else
  begin
    Buffer.AddIntegerValue(Human.PlayerOldQuests.Count);
    for I := 0 to Human.PlayerOldQuests.Count - 1 do
    begin
      OldQuest := PPlayerOldQuest(Human.PlayerOldQuests[I]);
      if OldQuest.Planet = nil then
        Buffer.AddDWord(0)
      else
        Buffer.AddDWord(Cardinal(OldQuest.Planet.Id));
      Buffer.AddByte(Byte(OldQuest.QuestType));
      Buffer.AddWord(OldQuest.QuestNumber);
      Buffer.AddWideStringZ(OldQuest.Description);
      Buffer.AddBoolean(OldQuest.Successful);
      Buffer.AddBoolean(OldQuest.Declined);
    end;
  end;
  if Human.TemporaryShopSlots = nil then
    Buffer.AddIntegerValue(0)
  else
  begin
    Buffer.AddIntegerValue(Human.TemporaryShopSlots.Count);
    for I := 0 to Human.TemporaryShopSlots.Count - 1 do
      TShopStockSlot(Human.TemporaryShopSlots[I]).SaveToBuffer(
          Buffer,
          ShopViewSavesItems(Human)
      );
  end;
end;

// Version 3: for each human but the local one whose shop grid wrote its slots empty, the ids
// of the items the slots show (0 for none), to find them again in the location's list.
procedure SaveShopViewItems(Buffer: TBufEC);
var
  I, J, Count: Integer;
  Human: THuman;
  Slot: TShopStockSlot;
begin
  Count := 0;
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human <> LocalHuman)
        and (Human.TemporaryShopSlots <> nil)
        and not ShopViewSavesItems(Human) then
      Inc(Count);
  end;
  Buffer.AddIntegerValue(Count);
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    if (Human = LocalHuman)
        or (Human.TemporaryShopSlots = nil)
        or ShopViewSavesItems(Human) then
      Continue;
    Buffer.AddDWord(Cardinal(Human.Id));
    Buffer.AddIntegerValue(Human.TemporaryShopSlots.Count);
    for J := 0 to Human.TemporaryShopSlots.Count - 1 do
    begin
      Slot := TShopStockSlot(Human.TemporaryShopSlots[J]);
      if (Slot.Item = nil) or (FindShopStockItem(ShopViewLocation(Human), Slot.Item.Id) = nil) then
        Buffer.AddDWord(0)
      else
        Buffer.AddDWord(Cardinal(Slot.Item.Id));
    end;
  end;
end;

procedure LoadShopViewItems(Buffer: TBufEC);
var
  I, J, Count, SlotCount: Integer;
  Human: THuman;
  Id: Cardinal;
begin
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Human := FindHuman(Integer(Buffer.GetUInt32));
    SlotCount := Buffer.GetInt32;
    for J := 0 to SlotCount - 1 do
    begin
      Id := Buffer.GetUInt32;
      if (Human = nil)
          or (Human.TemporaryShopSlots = nil)
          or (Human.TemporaryShopSlots.Count <> SlotCount)
          or (Id = 0) then
        Continue;
      TShopStockSlot(Human.TemporaryShopSlots[J]).Item :=
          FindShopStockItem(ShopViewLocation(Human), Integer(Id));
    end;
  end;
end;

procedure ClearOldQuests(Human: THuman);
var
  I: Integer;
begin
  if Human.PlayerOldQuests = nil then
    Exit;
  for I := 0 to Human.PlayerOldQuests.Count - 1 do
    Dispose(PPlayerOldQuest(Human.PlayerOldQuests[I]));
  Human.PlayerOldQuests.Free;
  Human.PlayerOldQuests := nil;
end;

// Reads what SaveHumanState wrote into Human, which the load has created with defaults.
procedure LoadHumanState(Galaxy: TGalaxy; Human: THuman; Buffer: TBufEC);
var
  I, Count: Integer;
  Message: TMessagePlayer;
  OldQuest: PPlayerOldQuest;
  Entry: TPlayerHoldUnit;
  Slot: TShopStockSlot;
begin
  Human.PlayerStar := Galaxy.IdToStar(Buffer.GetUInt32);
  Human.PendingPlayerFollowTarget := TShip(Galaxy.IdToShip(Buffer.GetUInt32, False));
  Human.PlayerAutomaticControl := Buffer.GetBoolean;
  Human.PlayerEquipmentBrokenThisTurn := Buffer.GetBoolean;
  Human.PlayerDialogueRequestCount := Buffer.GetByte;
  Human.ShownPlayerTips := Buffer.GetUInt32;
  Human.StarMapWeaponPanelOpen := Buffer.GetBoolean;
  for I := 0 to 8 do
    Human.HangarShipIds[I] := Integer(Buffer.GetUInt32);
  InitializePlayerHoldView(Human);
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Entry := TPlayerHoldUnit.Create;
    Human.PlayerHoldEntries.Add(Entry);
    Entry.Kind := TPlayerHoldKind(Buffer.GetByte);
    Entry.GoodsIndex := Buffer.GetByte;
    Entry.ItemId := Integer(Buffer.GetUInt32);
  end;
  Human.ClearBubbles;
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Message := Human.CreateBubble;
    Message.LoadFromBuffer(Buffer);
  end;
  ClearOldQuests(Human);
  Human.PlayerOldQuests := TList.Create;
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    New(OldQuest);
    Human.PlayerOldQuests.Add(OldQuest);
    OldQuest.Planet := TPlanet(Galaxy.IdToPlanet(Buffer.GetUInt32, False));
    OldQuest.QuestType := TQuestType(Buffer.GetByte);
    OldQuest.QuestNumber := Buffer.GetWord;
    OldQuest.Description := Buffer.ReadWideString;
    OldQuest.Successful := Buffer.GetBoolean;
    OldQuest.Declined := Buffer.GetBoolean;
  end;
  ClearTemporaryShopSlotGrid(Human);
  Count := Buffer.GetInt32;
  if Count > 0 then
  begin
    Human.TemporaryShopSlots := TList.Create;
    for I := 0 to Count - 1 do
    begin
      Slot := ShopSlotClass.Create;
      Human.TemporaryShopSlots.Add(Slot);
      Slot.LoadFromBuffer(Buffer, Galaxy);
    end;
    // Where the shop came from, as TGalaxy.LoadFromBuffer finds it for the local human;
    // the items the grid was saved with go back to it.
    AdoptLoadedShopView(Human);
  end;
end;

procedure SaveHumanBlock(Galaxy: TGalaxy; Buffer: TBufEC);
var
  I, Count, SizeOffset: Integer;
  Human: THuman;
  Event: TGalaxyEvent;
begin
  if not HumanSaveBlockNeeded(Galaxy) then
    Exit;
  Buffer.AddDWord(HumanBlockMagic);
  Buffer.AddDWord(HumanBlockVersion);
  SizeOffset := Buffer.Position;
  Buffer.AddIntegerValue(0);
  // The retired text-quest flag (aSession), always off.
  Buffer.AddBoolean(False);
  Buffer.AddBoolean(Session.FriendlyFireEnabled);
  Buffer.AddIntegerValue(Session.Humans.Count);
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Buffer.AddDWord(Cardinal(Human.Id));
    Buffer.AddIntegerValue(Human.CheatPoints);
    Buffer.AddIntegerValue(Length(Human.UsedCheats));
    for Count := 0 to High(Human.UsedCheats) do
      Buffer.AddWideStringZ(Human.UsedCheats[Count]);
    // The local human's state is in the original layout.
    Buffer.AddBoolean(Human <> LocalHuman);
    if Human <> LocalHuman then
      SaveHumanState(Human, Buffer);
  end;
  Buffer.AddIntegerValue(Galaxy.Scripts.Count);
  for I := 0 to Galaxy.Scripts.Count - 1 do
    Buffer.AddIntegerValue(TScript(Galaxy.Scripts[I]).HumanId);
  Count := 0;
  for I := 0 to Galaxy.GalaxyEvents.Count - 1 do
    if TGalaxyEvent(Galaxy.GalaxyEvents[I]).HumanId <> -1 then
      Inc(Count);
  Buffer.AddIntegerValue(Count);
  for I := 0 to Galaxy.GalaxyEvents.Count - 1 do
  begin
    Event := TGalaxyEvent(Galaxy.GalaxyEvents[I]);
    if Event.HumanId <> -1 then
    begin
      Buffer.AddIntegerValue(I);
      Buffer.AddIntegerValue(Event.HumanId);
    end;
  end;
  // Version 2.
  Buffer.AddIntegerValue(Session.Humans.Count);
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Human := Session.Humans[I];
    Buffer.AddDWord(Cardinal(Human.Id));
    Buffer.AddBoolean(Human.Finished);
    Buffer.AddIntegerValue(Human.FinishReason);
  end;
  // Version 3.
  SaveShopViewItems(Buffer);
  // Version 4.
  Buffer.AddIntegerValue(Session.Humans.Count);
  for I := 0 to Session.Humans.Count - 1 do
  begin
    Buffer.AddDWord(Cardinal(Session.Humans[I].Id));
    Buffer.AddIntegerValue(Session.Humans[I].QuestDaysOwed);
  end;
  Buffer.SetInt32At(SizeOffset, Buffer.Position - SizeOffset - 4);
end;

procedure LoadHumanBlock(Galaxy: TGalaxy; Buffer: TBufEC);
var
  I, J, Count, Start, Size, Index, HumanId: Integer;
  Version: Cardinal;
  Human, Scratch: THuman;
  Order: TList;
  Cheats: array of WideString;
  Points: Integer;
  NextItemId: Cardinal;
  Finished: Boolean;
  Reason, Days: Integer;
begin
  Start := Buffer.Position;
  if (Buffer.DataSize - Start < 12) or (Buffer.GetUInt32 <> HumanBlockMagic) then
  begin
    Buffer.SetPosition(Start);
    Exit;
  end;
  Version := Buffer.GetUInt32;
  Size := Buffer.GetInt32;
  Start := Buffer.Position;
  if Version < 1 then
  begin
    Buffer.SetPosition(Start + Size);
    Exit;
  end;
  // The retired text-quest flag: text quests are always on.
  Buffer.GetBoolean;
  Session.FriendlyFireEnabled := Buffer.GetBoolean;
  // Loading a shop's items raises the next item id past theirs. The original layout reads
  // the saved value after its own shop, so that one stands; keep it here too.
  NextItemId := Galaxy.NextItemId;
  Order := TList.Create;
  try
    Count := Buffer.GetInt32;
    for I := 0 to Count - 1 do
    begin
      HumanId := Integer(Buffer.GetUInt32);
      Human := FindHuman(HumanId);
      Points := Buffer.GetInt32;
      SetLength(Cheats, Buffer.GetInt32);
      for J := 0 to High(Cheats) do
        Cheats[J] := Buffer.ReadWideString;
      if Human <> nil then
      begin
        Human.CheatPoints := Points;
        Human.UsedCheats := Copy(Cheats);
        if Order.IndexOf(Human) < 0 then
          Order.Add(Human);
      end;
      if Buffer.GetBoolean then
        if (Human <> nil) and (Human <> LocalHuman) then
          LoadHumanState(Galaxy, Human, Buffer)
        else
        begin
          // A human whose ranger the galaxy no longer has: read past its state.
          Scratch := THuman.Create;
          try
            LoadHumanState(Galaxy, Scratch, Buffer);
            ClearTemporaryShopSlotGrid(Scratch);
            ClearOldQuests(Scratch);
          finally
            Scratch.Free;
          end;
        end;
    end;
    // Loops over the humans run in the saved order.
    for I := 0 to Session.Humans.Count - 1 do
      if Order.IndexOf(Session.Humans[I]) < 0 then
        Order.Add(Session.Humans[I]);
    Session.Humans.Clear;
    for I := 0 to Order.Count - 1 do
      Session.Humans.Add(Order[I]);
  finally
    Order.Free;
  end;
  Galaxy.NextItemId := NextItemId;
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    HumanId := Buffer.GetInt32;
    if (Count = Galaxy.Scripts.Count) then
      TScript(Galaxy.Scripts[I]).HumanId := HumanId;
  end;
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Index := Buffer.GetInt32;
    HumanId := Buffer.GetInt32;
    if (Index >= 0) and (Index < Galaxy.GalaxyEvents.Count) then
      TGalaxyEvent(Galaxy.GalaxyEvents[Index]).HumanId := HumanId;
  end;
  // Version 1 has no finished humans: every human plays.
  if Version >= 2 then
  begin
    Count := Buffer.GetInt32;
    for I := 0 to Count - 1 do
    begin
      Human := FindHuman(Integer(Buffer.GetUInt32));
      Finished := Buffer.GetBoolean;
      Reason := Buffer.GetInt32;
      if Human <> nil then
      begin
        Human.Finished := Finished;
        Human.FinishReason := Reason;
        Human.EndedTurn := Human.EndedTurn or Finished;
      end;
    end;
  end;
  if Version >= 3 then
    LoadShopViewItems(Buffer);
  // Version 3 and older owe no quest days.
  if Version >= 4 then
  begin
    Count := Buffer.GetInt32;
    for I := 0 to Count - 1 do
    begin
      Human := FindHuman(Integer(Buffer.GetUInt32));
      Days := Buffer.GetInt32;
      if Human <> nil then
        Human.QuestDaysOwed := Days;
    end;
  end;
  Buffer.SetPosition(Start + Size);
end;

end.
