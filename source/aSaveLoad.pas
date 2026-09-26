{$EXCESSPRECISION OFF}
unit aSaveLoad;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  EC_Buf,
  EC_Thread,
  SyncObjs;
type
  TSaver = class;
  TSaver = class(TThreadEC)
    FileName: WideString;
    HeaderBuffer: TBufEC;
    PreviewBuffer: TBufEC;
    SecondaryPreviewBuffer: TBufEC;
    GameStateBuffer: TBufEC;
    FilmBuffer: TBufEC;
    ErrorText: AnsiString;
    procedure Execute; override;
    procedure QueueSave(
        AFileName: WideString;
        Header: TBufEC;
        Preview: TBufEC;
        SecondaryPreview: TBufEC;
        GameState: TBufEC;
        Films: TBufEC
    );
  end;
var
  MemorySnapshotBuffer: TBufEC = nil;
  SaveLoadLock: TCriticalSection = nil;
  SaveWriter: TSaver = nil;
  LastSaveLoadError: WideString;
  // Told after a save file has been loaded (the command log starts from it).
  GameLoadedHook: procedure(const FileName: WideString);
function SaveGameToFile(FileName: WideString; Description: WideString): Boolean;
procedure LoadGameFromSaveBuffer(Buffer: TBufEC);
function LoadGameFromFile(FileName: WideString): Boolean;
procedure SaveGameToMemorySnapshot;
procedure RestoreGameFromMemorySnapshot;
procedure WriteGameCheckpoint(Buffer: TBufEC);
procedure ReadGameCheckpoint(Buffer: TBufEC);
procedure InitializeSaveWriter;
procedure FinalizeSaveWriter;
procedure LinkRecoveredTypes;
implementation

uses
  aSession,
  aHold,
  aPlayerActions,
  aItem,
  aObjectRefs,
  Classes,
  aHuman,
  aCalc,
  RTLFileSystem,
  Math,
  aMyFunction,
  aGalaxyStruct,
  aKling,
  Windows,
  SysUtils,
  EC_File,
  EC_Str,
  EC_BlockPar,
  aGalaxy,
  aGalaxyEvent,
  aConst,
  aPlayer,
  GR_Main,
  Globals,
  GlobalsV,
  fSaveManager,
  fShip2,
  fStarMap,
  fFilmFile,
  GI_Main,
  GI_MessageBox,
  EC_Struct,
  Types,
  aShip,
  aRuins,
  GI_MessageLoop,
  fGov,
  fEquipmentShop,
  aShopStock,
  fCount2,
  fRating2,
  fJournal,
  fSelectFace,
  fScaner,
  fGalaxy2,
  fGameMenu,
  fRewards,
  fChameleon,
  fTalk,
  ab_MainForm,
  fLoad,
  fGameLoad,
  fHangar,
  fPlanet,
  fPlanetNO,
  fPlanetQuest,
  fGoodsShop2,
  fRuinsTalk,
  fInfo,
  fJump;

var
  MemorySnapshotGalaxy: TGalaxy = nil;

procedure TSaver.Execute;
var
  F: TFileEC;
  Size, I, Seed: Integer;
  SourceName, TargetName, NewName, OldName, Prefix, QuickName, TempName: WideString;
  FastCompression: Boolean;
begin
  SaveLoadLock.Enter;
  F := nil;
  TempName := '';
  try
    try
      // CHANGE: PERFORMANCE - Use cheaper compression for fast-travel autosaves.
      FastCompression := FastTravelTransitions and (FileName = SaveManagerScreen.GetAutoSavePath);
      QuickName := SaveManagerScreen.GetQuickSavePath(1);
      if not ForceDirectories(NativePath(GetGameUserDirectory + 'Save')) then
        raise Exception.Create('Cannot create save directory');
      F := TFileEC.Create;
      TempName := GetGameUserDirectory + 'Save\save.tmp';
      if FileExists(AnsiString(TempName)) then
        DeleteFileA(PAnsiChar(AnsiString(TempName)));
      F.SetFileName(TempName);
      F.CreateNew;
      HeaderBuffer.SaveToFile(F);
      if PreviewBuffer.DataSize > 0 then
        PreviewBuffer.CompressZlibPayloadInPlace(FastCompression);
      Size := PreviewBuffer.DataSize;
      F.WriteBuffer(@Size, 4);
      if Size > 0 then
        F.WriteBuffer(PreviewBuffer.Data, Size);
      if SecondaryPreviewBuffer.DataSize > 0 then
        SecondaryPreviewBuffer.CompressZlibPayloadInPlace(FastCompression);
      Size := SecondaryPreviewBuffer.DataSize;
      F.WriteBuffer(@Size, 4);
      if Size > 0 then
        F.WriteBuffer(SecondaryPreviewBuffer.Data, Size);
      GameStateBuffer.CompressZlibPayloadInPlace(FastCompression);
      Size := GameStateBuffer.ComputeCrc32;
      F.WriteBuffer(@Size, 4);
      Seed := RandomIntRange(0, 2000000000);
      GameStateBuffer.ApplyDatXorCipher(Seed);
      F.WriteBuffer(@Seed, 4);
      Size := GameStateBuffer.DataSize;
      F.WriteBuffer(@Size, 4);
      if Size > 0 then
        F.WriteBuffer(GameStateBuffer.Data, Size);
      FilmBuffer.CompressZlibPayloadInPlace(FastCompression);
      Size := FilmBuffer.DataSize;
      F.WriteBuffer(FilmBuffer.Data, Size);
      F.ReleaseHandle;
      SourceName := TempName;
      TargetName := FileName;
      if (FileName = QuickName) and (QuickSaveExtraSlots > 0) then
      begin
        Prefix :=
            TrimWideString(ExtractFileDirW(QuickName))
                + '\'
                + TrimWideString(ExtractFileNameNoExtW(QuickName));
        NewName := Prefix + IntToWideString(QuickSaveExtraSlots + 1) + '.sav';
        for I := QuickSaveExtraSlots downto 1 do
        begin
          if I > 1 then
            OldName := Prefix + IntToWideString(I) + '.sav'
          else
            OldName := QuickName;
          if RTLFileSystem.FileExists(UTF8Encode(OldName)) then
            if not MoveFileW(PWideChar(OldName), PWideChar(NewName)) then
              raise Exception.Create('Cannot rotate quicksave: ' + UTF8Encode(OldName));
          NewName := OldName;
        end;
      end;
      // CHANGE: BUGFIX - Replace the destination only after writing and closing the complete save.
      // POSIX rename atomically replaces the destination; keep the old save until
      // the complete temporary file has been closed successfully.
      if not MoveFileW(PWideChar(SourceName), PWideChar(TargetName)) then
        raise Exception.Create('Cannot commit save: ' + UTF8Encode(TargetName));

    except
      on E: Exception do
      begin
        ErrorText := E.ClassName + ': ' + E.Message;
        AppendLogLineThreadSafe('Save failed: ' + ErrorText);
        LogExceptionBackTrace;
      end;
    end;
  finally
    try
      F.Free;
      if (TempName <> '') and RTLFileSystem.FileExists(UTF8Encode(TempName)) then
        DeleteFileA(PAnsiChar(UTF8Encode(TempName)));
      FreeAndNil(HeaderBuffer);
      FreeAndNil(PreviewBuffer);
      FreeAndNil(SecondaryPreviewBuffer);
      FreeAndNil(GameStateBuffer);
      FreeAndNil(FilmBuffer);
    finally
      SaveLoadLock.Leave;
    end;
  end;

end;
procedure TSaver.QueueSave(
    AFileName: WideString;
    Header, Preview, SecondaryPreview, GameState, Films: TBufEC
);
begin
  if IsRunning then
    WaitForIdle(INFINITE);
  ErrorText := '';
  FileName := AFileName;
  HeaderBuffer := Header;
  PreviewBuffer := Preview;
  SecondaryPreviewBuffer := SecondaryPreview;
  GameStateBuffer := GameState;
  FilmBuffer := Films;
  Start;
end;

function SaveGameToFile(FileName, Description: WideString): Boolean;
var
  Header, Preview, SecondaryPreview, GameState, Films, FilmEntry: TBufEC;
  Size, I, Count: Integer;
  Message: TMessagePlayer;
  Entry: TPlayerHoldUnit;
  AutoName, TurnName, QuickName: WideString;
begin
  Result := False;
  LastSaveLoadError := '';
  Header := nil;
  Preview := nil;
  SecondaryPreview := nil;
  GameState := nil;
  Films := nil;
  if (Galaxy <> nil) and (LocalPlayer <> nil) then
  begin
    FilmEntry := nil;
    AutoName := SaveManagerScreen.GetAutoSavePath;
    TurnName := SaveManagerScreen.GetTurnSavePath;
    QuickName := SaveManagerScreen.GetQuickSavePath(1);
    if FileName = AutoName then
      Description := SaveManagerScreen.BuildCurrentSaveDescription;
    try
      Header := TBufEC.Create;
      Header.AddWideStringZ('RSG');
      Header.AddWideStringZ('v' + IntToStr(CurrentSaveVersion));
      Header.AddWideStringZ(Description);
      Header.AddWideStringZ(IntToStr(Galaxy.CurrentTurn));
      Header.AddWideStringZ(IntToStr(LocalPlayer.Money));
      Header.AddWideStringZ(LocalPlayer.Name);
      if LocalPlayer.OwnerId = Byte(oiPirate) then
        Header.AddWideStringZ(
            OwnerInfo[Ord(oiPirate)].InternalName
                + OwnerInfo[Integer(RaceToOwner(LocalPlayer.PilotRace)) and $7F].InternalName
        )
      else
        Header.AddWideStringZ(OwnerInfo[LocalPlayer.OwnerId].InternalName);
      Header.AddWideStringZ('EZ');
      Preview := TBufEC.Create;
      if SavePreviewGraph <> nil then
        SavePreviewGraph.SaveToBuffer(Preview);
      SecondaryPreview := TBufEC.Create;
      if SecondarySavePreviewGraph <> nil then
        SecondarySavePreviewGraph.SaveToBuffer(SecondaryPreview);
      GameState := TBufEC.Create;
      GameState.AddIntegerValue(Ord(SaveManagerReturnScreenId));
      GameState.AddIntegerValue(StarMapScreen.GetMapCenter.X);
      GameState.AddIntegerValue(StarMapScreen.GetMapCenter.Y);
      GameState.AddBoolean(LocalHuman.StarMapWeaponPanelOpen);
      GameState.AddAnsiChar(#0);
      GameState.AddBoolean(FilmCameraFollow);
      GameState.AddAnsiChar(#0);
      GameState.AddAnsiChar(#0);
      GameState.AddAnsiChar(#0);
      GameState.AddBoolean(False);
      GameState.AddBoolean(Session.PlayerStarDayPrepared);
      GameState.AddDWord(LocalHuman.ShownPlayerTips);
      GameState.AddIntegerValue(0);
      Count := CountPersistentPlayerMessages;
      GameState.AddIntegerValue(Count);
      Message := LocalHuman.FirstPersistentPlayerMessage;
      while Message <> nil do
      begin
        Message.SaveToBuffer(GameState);
        Message := Message.Next;
      end;
      LocalHuman.PlayerHoldShip := LocalPlayer;
      RefreshPlayerHoldView(LocalHuman, False);
      Count := LocalHuman.PlayerHoldEntries.Count;
      GameState.AddWideChar(WideChar(Count));
      for I := 0 to Count - 1 do
      begin
        Entry := LocalHuman.PlayerHoldEntries[I];
        GameState.AddAnsiChar(AnsiChar(Entry.Kind));
        GameState.AddAnsiChar(AnsiChar(Entry.GoodsIndex));
        GameState.AddDWord(Entry.ItemId);
      end;
      // CHANGE: BUGFIX - Moved out of TGalaxy.SaveToBuffer so that hashing the state
      // changes nothing; a command, since it can change the game.
      PrepareSave;
      Galaxy.SaveToBuffer(GameState);
      Films := TBufEC.Create;
      FilmEntry := TBufEC.Create;
      Count := 0;
      Count := FilmHistory.GetCount;
      Films.AddBytes(@Count, 4);
      for I := 0 to Count - 1 do
      begin
        FilmHistory.SaveEntryToBuffer(FilmHistory.GetEntry(I), FilmEntry);
        Size := FilmEntry.DataSize;
        Films.AddBytes(@Size, 4);
        if Size > 0 then
          Films.AddBytes(FilmEntry.Data, Size);
      end;
      SaveWriter.QueueSave(FileName, Header, Preview, SecondaryPreview, GameState, Films);
      Header := nil;
      Preview := nil;
      SecondaryPreview := nil;
      GameState := nil;
      Films := nil; // Ownership passed to the writer.
      SaveWriter.WaitForIdle(INFINITE);
      if SaveWriter.ErrorText <> '' then
        raise Exception.Create(SaveWriter.ErrorText);
      if Galaxy.CampaignFlag183 <> 0 then
      begin
        EditableSaveFileName := SaveManagerScreen.GetSaveConfigPath(FileName);
        if (UserSettingsConfig.CountParams('UnicodeDump') > 0)
            and ParseEnabledNameGI(
                TrimWideString(UserSettingsConfig.GetParamByPathOrMarker('UnicodeDump'))) then
          Session.EditableSaveBlock.SaveTextFile(PWideChar(EditableSaveFileName), False, False)
        else
          Session.EditableSaveBlock.SaveTextFile(PWideChar(EditableSaveFileName), True, False);
        Session.EditableSaveBlock.Clear;
        Galaxy.CampaignFlag183 := 0;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        LastSaveLoadError := E.ClassName + ': ' + E.Message;
        AppendLogLineThreadSafe(UTF8Encode(LastSaveLoadError));
        LogExceptionBackTrace;
        if FileName = AutoName then
          Galaxy.ShowLocalizedWarning('Warning.AutoSaveFailed');
        if FileName = TurnName then
          Galaxy.ShowLocalizedWarning('Warning.TurnSaveFailed');
        if FileName = QuickName then
          Galaxy.ShowLocalizedWarning('Warning.QuickSaveFailed');
      end;
    end;
    Header.Free;
    Preview.Free;
    SecondaryPreview.Free;
    GameState.Free;
    Films.Free;
    if FilmEntry <> nil then
      FilmEntry.Free;
    if Result = True then
      FreeSavePreviewBuffers;
  end;

end;
procedure LoadGameFromSaveBuffer(Buffer: TBufEC);
var
  I, Count: Integer;
  Entry: TPlayerHoldUnit;
  LoadingGalaxy: TGalaxy;
begin
  InitializePlayerHoldView(LocalHuman);
  Count := Buffer.GetWord;
  for I := 0 to Count - 1 do
  begin
    Entry := TPlayerHoldUnit.Create;
    LocalHuman.PlayerHoldEntries.Add(Entry);
    Entry.Kind := TPlayerHoldKind(Buffer.GetByte);
    Entry.GoodsIndex := Buffer.GetByte;
    Entry.ItemId := Buffer.GetUInt32;
  end;
  LoadingGalaxy := Galaxy;
  Galaxy := nil;
  LoadingGalaxy.LoadFromBuffer(Buffer);
  if Session.ApplyEditableSaveOnLoad then
  begin
    Galaxy.ApplyEditableState;
    Session.ApplyEditableSaveOnLoad := False;
    aCalc.WaitForTurnCalculationUI;
  end;
  Galaxy.RunConfigOnLoadHandlers;
end;
function LoadGameFromFile(FileName: WideString): Boolean;
var
  F: TFileEC;
  Buffer, Films: TBufEC;
  Center: TPoint;
  Size, I, Count, Seed: Integer;
  Crc: Cardinal;
  Message: TMessagePlayer;
begin
  Result := False;
  LastSaveLoadError := '';
  Session.LoadedSaveModSet := SelectedMods;

  SaveLoadLock.Enter;

  try
    F := nil;
    Buffer := nil;
    try
      if MemorySnapshotBuffer <> nil then
        MemorySnapshotBuffer.Free;
      MemorySnapshotBuffer := nil;
      MemorySnapshotActive := False;
      if (Galaxy <> nil) and not Galaxy.Destroying then
        Galaxy.Free;
      Galaxy := nil;

      F := TFileEC.Create;
      F.SetFileName(FileName);
      if not F.TryAcquireReadHandle(False) then
        raise EAbort.Create('Cannot open file ' + FileName);
      if F.ReadWideString <> 'RSG' then
        raise EAbort.Create('Bad pre-signature of file' + FileName);
      Session.LoadedSaveVersion := ExtractDigitsToIntW(F.ReadWideString);
      F.ReadWideString;
      StrToInt(F.ReadWideString);
      StrToInt(F.ReadWideString);
      F.ReadWideString;
      F.ReadWideString;
      if F.ReadWideString <> 'EZ' then
        raise EAbort.Create('Bad post-signature of file' + FileName);
      Buffer := TBufEC.Create;
      F.ReadBuffer(@Size, 4);
      if Size > 0 then
        F.SetPointer(Size, 1);
      F.ReadBuffer(@Size, 4);
      if Size > 0 then
        F.SetPointer(Size, 1);
      F.ReadBuffer(@Crc, 4);
      F.ReadBuffer(@Seed, 4);
      F.ReadBuffer(@Size, 4);
      if Size > 0 then
      begin
        Buffer.SetSize(Size);
        try
          F.ReadBuffer(Buffer.Data, Size);
        except
          ShowMessageBoxGI(nil, 'Compressed galaxy read fail', 1, 0, 0, 0);
        end;
      end;

      Buffer.ApplyDatXorCipher(Seed);
      if Buffer.ComputeCrc32 <> Crc then
        raise EAbort.Create('Integrity check fail');

      Buffer.ExpandZlibPayloadInPlace;

      ActiveLoadBuffer := Buffer;
      RequestedScreenId := TGameScreenId(Buffer.GetInt32);
      Galaxy := TGalaxy.Create;
      Center.X := Buffer.GetInt32;
      Center.Y := Buffer.GetInt32;
      SpaceViewPosition := PointToPointF(Center);
      StarMapScreen.SetMapCenterManually(Center);
      LocalHuman.StarMapWeaponPanelOpen := Buffer.GetBoolean;
      Buffer.GetByte;
      FilmCameraFollow := Buffer.GetBoolean;
      Buffer.GetByte;
      Buffer.GetByte;
      Buffer.GetByte;
      Buffer.GetBoolean;
      Session.PlayerStarDayPrepared := Buffer.GetBoolean;
      LocalHuman.ShownPlayerTips := Buffer.GetUInt32;
      Buffer.GetInt32;
      Count := Buffer.GetInt32;
      for I := 0 to Count - 1 do
      begin
        Message := CreatePersistentPlayerMessage;
        Message.LoadFromBuffer(Buffer);
      end;

      LoadGameFromSaveBuffer(Buffer);

      Films := nil;
      try
        Films := TBufEC.Create;
        Films.Clear;
        Size := F.GetSize - F.GetPointer;
        if Size > 0 then
        begin
          Films.SetSize(Size);
          F.ReadBuffer(Films.Data, Size);
          Films.ExpandZlibPayloadInPlace;
          FilmHistory.Clear;
          Films.ReadBytes(@Count, 4);
          LoadingFilmCount := Count;
          LoadedFilmCount := 0;
          for I := 0 to Count - 1 do
          begin
            Films.ReadBytes(@Size, 4);
            if Size > 0 then
            begin
              Buffer.SetSize(Size);
              Films.ReadBytes(Buffer.Data, Size);
              Buffer.SetPosition(0);
              FilmHistory.LoadEntryFromBuffer(Buffer);
            end;
            Inc(LoadedFilmCount);
          end;
          LoadingFilmCount := -1;
        end;
      finally
        if Films <> nil then
          Films.Free;
      end;
      LoadingFilmCount := -1;

      PreviousFilmActivity := 0;
      Result := True;
    except
      on E: Exception do
      begin
        LastSaveLoadError := E.ClassName + ': ' + E.Message;
        AppendLogLineThreadSafe('Load failed: ' + UTF8Encode(LastSaveLoadError));
        LogExceptionBackTrace;
        if MemorySnapshotBuffer <> nil then
          MemorySnapshotBuffer.Free;
        MemorySnapshotBuffer := nil;
        MemorySnapshotActive := False;
        if (Galaxy <> nil) and not Galaxy.Destroying then
        begin
          try
            Galaxy.Free;
          finally
            Galaxy := nil;
          end;
        end;
        if Session.EditableSaveBlock <> nil then
          Session.EditableSaveBlock.Clear;
      end;
    end;
    LoadingFilmCount := -1;
    ActiveLoadBuffer := nil;
    if Buffer <> nil then
      Buffer.Free;
    if F <> nil then
      F.Free;
  finally
    SaveLoadLock.Leave;
  end;
  if Result and Assigned(GameLoadedHook) then
    GameLoadedHook(FileName);

end;
procedure SaveGameToMemorySnapshot;
var
  I, Count: Integer;
  Message: TMessagePlayer;
  Entry: TPlayerHoldUnit;
  Loop: TMessageLoopGI;
begin
  MemorySnapshotBuffer := TBufEC.Create;
  if (CurrentScreenId <> screenPlanetQuest)
      and ((CurrentScreenId <> screenGovernment) or (GovernmentScreen.PendingTransition = 0))
      and ((CurrentScreenId <> screenStarMap) or (StarMapScreen.PlanetBattleState = 0)) then
    (TObject(RegisteredScreens[Ord(CurrentScreenId)]) as TMessageLoopGI).OnClose;
  for I := MessageLoopStack.Count - 1 downto 0 do
  begin
    Loop := MessageLoopStack[I];
    if Loop is TfShip2 then
      (Loop as TfShip2).ReturnSelectedHoldEntry;
  end;
  if (LocalPlayer.IsOnPlanet and (LocalPlayer.CurrentPlanet.OwnerId <> Byte(oiUninhabited)))
      or (LocalPlayer.IsDockedToShip and (LocalPlayer.DockedTo is TRuins)) then
    RestoreTemporaryShopStock;
  Count := CountPersistentPlayerMessages;
  MemorySnapshotBuffer.AddIntegerValue(Count);
  Message := LocalHuman.FirstPersistentPlayerMessage;
  while Message <> nil do
  begin
    Message.SaveToBuffer(MemorySnapshotBuffer);
    Message := Message.Next;
  end;
  MemorySnapshotBuffer.AddDWord(LocalHuman.ShownPlayerTips);
  LocalHuman.PlayerHoldShip := LocalPlayer;
  RefreshPlayerHoldView(LocalHuman, False);
  Count := LocalHuman.PlayerHoldEntries.Count;
  MemorySnapshotBuffer.AddWideChar(WideChar(Count));
  for I := 0 to Count - 1 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    MemorySnapshotBuffer.AddAnsiChar(AnsiChar(Entry.Kind));
    MemorySnapshotBuffer.AddAnsiChar(AnsiChar(Entry.GoodsIndex));
    MemorySnapshotBuffer.AddDWord(Entry.ItemId);
  end;
  Dec(Galaxy.SaveCount);
  PrepareGalaxyForSave;
  Galaxy.SaveToBuffer(MemorySnapshotBuffer);
  if Galaxy.ContainsShipReference(LocalHuman.TalkShip) then
    MemorySnapshotBuffer.AddDWord(LocalHuman.TalkShip.Id)
  else
    MemorySnapshotBuffer.AddDWord(0);
  if Galaxy.ContainsPlanetReference(LocalHuman.TalkPlanet) then
    MemorySnapshotBuffer.AddDWord(LocalHuman.TalkPlanet.Id)
  else
    MemorySnapshotBuffer.AddDWord(0);
  if Galaxy.ContainsShipReference(ShipScreen.ShipToInspect) then
    MemorySnapshotBuffer.AddDWord(ShipScreen.ShipToInspect.Id)
  else
    MemorySnapshotBuffer.AddDWord(0);
  MemorySnapshotGalaxy := Galaxy;
  Galaxy := nil;
  BlazerShip := nil;
  KellerShip := nil;
  TerronShip := nil;
  MemorySnapshotActive := True;
end;
procedure RestoreGameFromMemorySnapshot;
var
  ReopenScreen: Boolean;
  I, Count: Integer;
  Entry: TPlayerHoldUnit;
  Message: TMessagePlayer;
  Loop: TMessageLoopGI;
begin
  ReopenScreen := True;
  Galaxy := MemorySnapshotGalaxy;
  MemorySnapshotGalaxy := nil;
  if DominatorSpawnPlanet <> nil then
  begin
    DominatorSpawnPlanet.Free;
    DominatorSpawnPlanet := nil;
  end;
  Galaxy.Free;
  MemorySnapshotBuffer.SetPosition(0);
  MemorySnapshotActive := True;
  Galaxy := TGalaxy.Create;
  Session.LoadedSaveVersion := CurrentSaveVersion;
  Count := MemorySnapshotBuffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Message := CreatePersistentPlayerMessage;
    Message.LoadFromBuffer(MemorySnapshotBuffer);
  end;
  LocalHuman.ShownPlayerTips := MemorySnapshotBuffer.GetUInt32;
  InitializePlayerHoldView(LocalHuman);
  Count := MemorySnapshotBuffer.GetWord;
  for I := 0 to Count - 1 do
  begin
    Entry := TPlayerHoldUnit.Create;
    LocalHuman.PlayerHoldEntries.Add(Entry);
    Entry.Kind := TPlayerHoldKind(MemorySnapshotBuffer.GetByte);
    Entry.GoodsIndex := MemorySnapshotBuffer.GetByte;
    Entry.ItemId := MemorySnapshotBuffer.GetUInt32;
  end;
  Galaxy.LoadFromBuffer(MemorySnapshotBuffer);
  Dec(Galaxy.LoadCount);
  LocalHuman.TalkShip := Galaxy.IdToShip(MemorySnapshotBuffer.GetUInt32, True);
  LocalHuman.TalkPlanet := Galaxy.IdToPlanet(MemorySnapshotBuffer.GetUInt32);
  ShipScreen.ShipToInspect := Galaxy.IdToShip(MemorySnapshotBuffer.GetUInt32, True);
  for I := MessageLoopStack.Count - 1 downto 0 do
  begin
    Loop := MessageLoopStack[I];
    if Loop is TMessageBoxGI then
      Loop.RequestClose(254)
    else if Loop is TfCount2 then
      Loop.RequestClose(254)
    else if (Loop is TfStarMap) and (StarMapScreen.PlanetBattleState <> 0) then
      ReopenScreen := False
    else if Loop is TfRating2 then
      Loop.RequestClose(1)
    else if Loop is TfJournal then
      Loop.RequestClose(1)
    else if Loop is TfSelectFace then
      Loop.RequestClose(254)
    else if Loop is TfScaner then
    begin
      RequestedScreenId := ScannerReturnScreenId;
      Loop.RequestClose(1);
      ReopenScreen := False;
    end
    else if (Loop is TfShip2) and not LocalPlayer.InNormalSpace then
      Loop.RequestClose(1)
    else if (Loop is TfGalaxy2) and not LocalPlayer.InNormalSpace then
      Loop.RequestClose(1)
    else if (Loop is TfShip2) and LocalPlayer.InNormalSpace then
    begin
      RequestedScreenId := ShipReturnScreenId;
      Loop.RequestClose(1);
    end
    else if (Loop is TfGalaxy2) and LocalPlayer.InNormalSpace then
    begin
      RequestedScreenId := GalaxyReturnScreenId;
      Loop.RequestClose(1);
    end
    else if Loop is TfGameMenu then
    begin
      RequestedScreenId := GameMenuReturnScreenId;
      Loop.RequestClose(1);
    end
    else if Loop is TfSaveManager then
    begin
      RequestedScreenId := SaveManagerReturnScreenId;
      Loop.RequestClose(1);
    end
    else if Loop is TfRewards then
      Loop.RequestClose(254)
    else if Loop is TfChameleon then
      Loop.RequestClose(254)
    else if Loop is TfTalk then
    begin
      RequestedScreenId := TalkReturnScreenId;
      if LocalHuman.TalkScripted then
        RaiseWideMessage('gtalk AI');
      Loop.RequestClose(1);
    end
    else if Loop is TfAB then
    begin
      RequestedScreenId := screenMainMenu;
      Loop.RequestClose(1);
      ReopenScreen := False;
    end
    else if Loop is TfLoad then
    begin
      if LocalPlayer.InNormalSpace then
      begin
        RequestedScreenId := screenStarMap;
        StarMapScreen.ResumeMode := smrOrders;
      end;
      PostLoadScreenId := RequestedScreenId;
      Loop.RequestClose(1);
    end
    else if Loop is TfGameLoad then
    begin
      Loop.RequestClose(1);
      ReopenScreen := False;
    end
    else if LocalPlayer.InNormalSpace
        and ((Loop is TfHangar)
            or (Loop is TfPlanet)
            or (Loop is TfPlanetNO)
            or (Loop is TfGov)
            or (Loop is TfPlanetQuest)
            or (Loop is TfEquipmentShop)
            or (Loop is TfGoodsShop2)
            or (Loop is TfRuinsTalk)
            or (Loop is TfInfo)) then
    begin
      RequestedScreenId := screenStarMap;
      StarMapScreen.ResumeMode := smrOrders;
      if Loop is TfGoodsShop2 then
      begin
        Loop.RequestClose(2);
        TalkScreen.Flag128 := 0;
        GoodsShopScreen.FlagEC := False;
        StarMapScreen.RequestClose(1);
      end
      else
        Loop.RequestClose(1);
      ReopenScreen := False;
    end
    else if (LocalPlayer.IsOnPlanet or LocalPlayer.IsDockedToShip) and (Loop is TfStarMap) then
    begin
      Loop.RequestClose(1);
      if LocalPlayer.IsOnPlanet and (LocalPlayer.CurrentPlanet.OwnerId = Byte(oiUninhabited)) then
        RequestedScreenId := screenPlanetNO
      else if LocalPlayer.IsOnPlanet and (LocalPlayer.CurrentPlanet.OwnerId <> Byte(oiUninhabited)) then
        RequestedScreenId := screenPlanet
      else if LocalPlayer.IsDockedToShip then
        RequestedScreenId := screenRuinsTalk;
    end
    else if LocalPlayer.InHyperspace
        and (LocalPlayer.Order = soJumpHole)
        and ((Loop is TfStarMap) or (Loop is TfAB)) then
    begin
      RequestedScreenId := screenMainMenu;
      Loop.RequestClose(1);
      ReopenScreen := False;
    end
    else if LocalPlayer.InHyperspace and (LocalPlayer.Order = soJump) and (Loop is TfStarMap) then
    begin
      RequestedScreenId := screenJump;
      Loop.RequestClose(1);
      ReopenScreen := False;
    end
    else if Loop is TfPlanetQuest then
      ReopenScreen := False
    else if (Loop is TfGov) and (GovernmentScreen.PendingTransition <> 0) then
      ReopenScreen := False
    else if Loop is TfJump then
      JumpScreen.RestoreOrdersOnArrival := True;
  end;
  if (LocalPlayer.IsOnPlanet and (LocalPlayer.CurrentPlanet.OwnerId <> Byte(oiUninhabited)))
      or (LocalPlayer.IsDockedToShip and (LocalPlayer.DockedTo is TRuins)) then
    BuildTemporaryShopSlotGrid;
  if ReopenScreen then
    (TObject(RegisteredScreens[Ord(CurrentScreenId)]) as TMessageLoopGI).OnOpen;
  aCalc.WaitForTurnCalculationUI;
  MemorySnapshotBuffer.Free;
  MemorySnapshotBuffer := nil;
  MemorySnapshotActive := False;
  Galaxy.RunConfigOnLoadHandlers;
end;

// CHANGE: ENHANCEMENT - The state a command log checkpoint holds (CommandLog): what the
// memory snapshot holds, plus the per-human and session state the simulation reads between
// days. Unlike a save it does not prepare the galaxy, touch screens or count as a save or a
// load, so writing one changes nothing and reading one gives back the same state.
const
  CheckpointVersion = 1;

procedure WriteShipId(Buffer: TBufEC; Ship: TShip);
begin
  if (Ship <> nil) and Galaxy.ContainsShipReference(Ship) then
    Buffer.AddDWord(Ship.Id)
  else
    Buffer.AddDWord(0);
end;

// A loaded game would drift from the one it was saved from: a save rounds some values the
// game keeps at higher precision (an equipment's condition and the captain's health are
// Doubles saved as Singles, as in the original game), and it leaves out caches that the
// game refreshes only now and then (a ship's wealth and strength). Checkpoints carry the
// exact values by object id; objects that share an id are matched in the order aObjectRefs
// lists them.
type
  TExactKind = (ekEquipment, ekShip);

function ExactKindOf(Instance: TObject; out Kind: TExactKind): Boolean;
begin
  Result := True;
  if Instance is TEquipment then
    Kind := ekEquipment
  else if Instance is TShip then
    Kind := ekShip
  else
    Result := False;
end;

function ExactId(Instance: TObject): Cardinal;
begin
  if Instance is TItem then
    Result := Cardinal(TItem(Instance).Id)
  else
    Result := Cardinal(TShip(Instance).Id);
end;

procedure WriteExactFields(Buffer: TBufEC; Instance: TObject; Kind: TExactKind);
var
  Ship: TShip;
  I: Integer;
begin
  if Kind = ekEquipment then
    Buffer.AddDouble(TEquipment(Instance).ConditionPercent)
  else
  begin
    Ship := TShip(Instance);
    Buffer.AddInt32(Ship.Wealth);
    Buffer.AddSingle(Ship.WealthInBestRanger);
    Buffer.AddSingle(Ship.Strength);
    Buffer.AddSingle(Ship.StrengthInBestRanger);
    Buffer.AddSingle(Ship.StrengthInAverageRanger);
    Buffer.AddDouble(Ship.MovementDirection);
    for I := 1 to 24 do
      Buffer.AddDouble(Ship.CaptainHealth[I].Progress);
    Buffer.AddDouble(Ship.RadiationHealth[1].Progress);
  end;
end;

procedure ReadExactFields(Buffer: TBufEC; Instance: TObject; Kind: TExactKind);
var
  Ship: TShip;
  I: Integer;
begin
  if Kind = ekEquipment then
    TEquipment(Instance).ConditionPercent := Buffer.GetDouble
  else
  begin
    Ship := TShip(Instance);
    Ship.Wealth := Buffer.GetInt32;
    Ship.WealthInBestRanger := Buffer.GetSingle;
    Ship.Strength := Buffer.GetSingle;
    Ship.StrengthInBestRanger := Buffer.GetSingle;
    Ship.StrengthInAverageRanger := Buffer.GetSingle;
    Ship.MovementDirection := Buffer.GetDouble;
    for I := 1 to 24 do
      Ship.CaptainHealth[I].Progress := Buffer.GetDouble;
    Ship.RadiationHealth[1].Progress := Buffer.GetDouble;
  end;
end;

// The objects that have exact values, each once, in listing order.
procedure ListExactObjects(Objects: TList);
var
  Listed: TList;
  I: Integer;
  Kind: TExactKind;
begin
  Listed := TList.Create;
  try
    ListIdentifiedObjects(Listed);
    for I := 0 to Listed.Count - 1 do
      if ExactKindOf(TObject(Listed[I]), Kind) and (Objects.IndexOf(Listed[I]) < 0) then
        Objects.Add(Listed[I]);
  finally
    Listed.Free
  end;
end;

procedure WriteExactValues(Buffer: TBufEC);
var
  Objects: TList;
  I: Integer;
  Kind: TExactKind;
begin
  Objects := TList.Create;
  try
    ListExactObjects(Objects);
    Buffer.AddInt32(Objects.Count);
    for I := 0 to Objects.Count - 1 do
    begin
      ExactKindOf(TObject(Objects[I]), Kind);
      Buffer.AddByte(Ord(Kind));
      Buffer.AddDWord(ExactId(TObject(Objects[I])));
      WriteExactFields(Buffer, TObject(Objects[I]), Kind);
    end;
  finally
    Objects.Free
  end;
end;

// Orders by kind, then id; a stable sort keeps objects that share both in listing order.
function CompareExact(Left, Right: TObject): Integer;
var
  LeftKind, RightKind: TExactKind;
begin
  ExactKindOf(Left, LeftKind);
  ExactKindOf(Right, RightKind);
  if LeftKind <> RightKind then
    Exit(Ord(LeftKind) - Ord(RightKind));
  if ExactId(Left) < ExactId(Right) then
    Result := -1
  else if ExactId(Left) > ExactId(Right) then
    Result := 1
  else
    Result := 0;
end;

procedure ReadExactValues(Buffer: TBufEC);
var
  Objects: TList;
  Used: array of Boolean;
  I, J, Low, High, Middle, Count: Integer;
  Kind, FoundKind: TExactKind;
  Id: Cardinal;
  Found: TObject;
begin
  Objects := TList.Create;
  try
    ListExactObjects(Objects);
    for I := 1 to Objects.Count - 1 do
    begin
      J := I;
      while (J > 0) and (CompareExact(TObject(Objects[J - 1]), TObject(Objects[J])) > 0) do
      begin
        Objects.Exchange(J - 1, J);
        Dec(J);
      end;
    end;
    SetLength(Used, Objects.Count);
    Count := Buffer.GetInt32;
    for I := 0 to Count - 1 do
    begin
      Kind := TExactKind(Buffer.GetByte);
      Id := Buffer.GetUInt32;
      Low := 0;
      High := Objects.Count;
      while Low < High do
      begin
        Middle := (Low + High) div 2;
        ExactKindOf(TObject(Objects[Middle]), FoundKind);
        if (FoundKind < Kind) or ((FoundKind = Kind) and (ExactId(TObject(Objects[Middle])) < Id)) then
          Low := Middle + 1
        else
          High := Middle;
      end;
      Found := nil;
      while Low < Objects.Count do
      begin
        ExactKindOf(TObject(Objects[Low]), FoundKind);
        if (FoundKind <> Kind) or (ExactId(TObject(Objects[Low])) <> Id) then
          Break;
        if not Used[Low] then
        begin
          Found := TObject(Objects[Low]);
          Used[Low] := True;
          Break;
        end;
        Inc(Low);
      end;
      if Found = nil then
        raise Exception.Create('Checkpoint names an object the galaxy does not hold');
      ReadExactFields(Buffer, Found, Kind);
    end;
  finally
    Objects.Free
  end;
end;

procedure WriteGameCheckpoint(Buffer: TBufEC);
var
  I, Count: Integer;
  Message: TMessagePlayer;
  Entry: TPlayerHoldUnit;
begin
  Buffer.AddInt32(CheckpointVersion);
  Buffer.AddBoolean(Session.PlayerStarDayPrepared);
  Buffer.AddBoolean(LocalHuman.StarMapWeaponPanelOpen);
  Buffer.AddBoolean(LocalHuman.PlayerAutomaticControl);
  Buffer.AddBoolean(LocalHuman.PlayerEquipmentBrokenThisTurn);
  Buffer.AddByte(LocalHuman.PlayerDialogueRequestCount);
  Buffer.AddDWord(LocalHuman.ShownPlayerTips);
  Buffer.AddDWord(ChaoticRandomState);
  Count := CountPersistentPlayerMessages;
  Buffer.AddIntegerValue(Count);
  Message := LocalHuman.FirstPersistentPlayerMessage;
  while Message <> nil do
  begin
    Message.SaveToBuffer(Buffer);
    Message := Message.Next;
  end;
  if LocalHuman.PlayerHoldEntries = nil then
    Count := 0
  else
    Count := LocalHuman.PlayerHoldEntries.Count;
  Buffer.AddInt32(Count);
  for I := 0 to Count - 1 do
  begin
    Entry := LocalHuman.PlayerHoldEntries[I];
    Buffer.AddByte(Byte(Entry.Kind));
    Buffer.AddByte(Entry.GoodsIndex);
    Buffer.AddDWord(Entry.ItemId);
  end;
  // Write the counters so that loading them gives back the ones the galaxy has now.
  Dec(Galaxy.SaveCount);
  Dec(Galaxy.LoadCount);
  try
    Galaxy.SaveToBuffer(Buffer);
  finally
    Inc(Galaxy.LoadCount);
  end;
  WriteExactValues(Buffer);
  WriteShipId(Buffer, LocalHuman.TalkShip);
  if (LocalHuman.TalkPlanet <> nil) and Galaxy.ContainsPlanetReference(LocalHuman.TalkPlanet) then
    Buffer.AddDWord(LocalHuman.TalkPlanet.Id)
  else
    Buffer.AddDWord(0);
  WriteShipId(Buffer, LocalHuman.PendingPlayerFollowTarget);
end;

procedure ReadGameCheckpoint(Buffer: TBufEC);
var
  I, Count: Integer;
  Message: TMessagePlayer;
  Entry: TPlayerHoldUnit;
  Event: TObject;
  PresentationSeed: Integer;
  Prepared, WeaponPanelOpen, AutomaticControl, EquipmentBroken: Boolean;
  DialogueRequestCount: Byte;
  ChaoticState: Cardinal;
begin
  if Buffer.GetInt32 <> CheckpointVersion then
    raise Exception.Create('Unknown checkpoint version');
  Prepared := Buffer.GetBoolean;
  WeaponPanelOpen := Buffer.GetBoolean;
  AutomaticControl := Buffer.GetBoolean;
  EquipmentBroken := Buffer.GetBoolean;
  DialogueRequestCount := Buffer.GetByte;
  // TGalaxy.Create reseeds the presentation stream; keep it as it was.
  PresentationSeed := System.RandSeed;
  if Galaxy <> nil then
    Galaxy.Free;
  Galaxy := TGalaxy.Create;
  System.RandSeed := PresentationSeed;
  Session.LoadedSaveVersion := CurrentSaveVersion;
  Session.PlayerStarDayPrepared := Prepared;
  LocalHuman.StarMapWeaponPanelOpen := WeaponPanelOpen;
  LocalHuman.PlayerAutomaticControl := AutomaticControl;
  LocalHuman.PlayerEquipmentBrokenThisTurn := EquipmentBroken;
  LocalHuman.PlayerDialogueRequestCount := DialogueRequestCount;
  LocalHuman.ShownPlayerTips := Buffer.GetUInt32;
  ChaoticState := Buffer.GetUInt32;
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Message := CreatePersistentPlayerMessage;
    Message.LoadFromBuffer(Buffer);
  end;
  InitializePlayerHoldView(LocalHuman);
  Count := Buffer.GetInt32;
  for I := 0 to Count - 1 do
  begin
    Entry := TPlayerHoldUnit.Create;
    LocalHuman.PlayerHoldEntries.Add(Entry);
    Entry.Kind := TPlayerHoldKind(Buffer.GetByte);
    Entry.GoodsIndex := Buffer.GetByte;
    Entry.ItemId := Buffer.GetUInt32;
  end;
  // The writer stored one less than the load count, which loading adds back.
  Galaxy.LoadFromBuffer(Buffer);
  Event := TObject(Galaxy.GalaxyEvents.Last);
  if (Event is TGalaxyEvent) and (TGalaxyEvent(Event).EventType = 'SaveLoaded') then
  begin
    Galaxy.GalaxyEvents.Extract(Event);
    Event.Free;
  end;
  ReadExactValues(Buffer);
  LocalHuman.TalkShip := Galaxy.IdToShip(Buffer.GetUInt32, False);
  LocalHuman.TalkPlanet := Galaxy.IdToPlanet(Buffer.GetUInt32, False);
  LocalHuman.PendingPlayerFollowTarget := Galaxy.IdToShip(Buffer.GetUInt32, False);
  // Loading seeds the chaotic stream from the clock.
  ChaoticRandomState := ChaoticState;
end;

procedure InitializeSaveWriter;
begin
  SaveWriter := TSaver.Create;
end;
procedure FinalizeSaveWriter;
begin
  if SaveWriter <> nil then
  begin
    if SaveWriter.IsRunning then
      SaveWriter.WaitForIdle(INFINITE);
    SaveWriter.Free;
    SaveWriter := nil;
  end;
end;
procedure LinkRecoveredTypes;
begin
  TMessageBoxGI.ClassName;
  TMessageLoopGI.ClassName;
  TRuins.ClassName;
  TfAB.ClassName;
  TfChameleon.ClassName;
  TfCount2.ClassName;
  TfEquipmentShop.ClassName;
  TfGalaxy2.ClassName;
  TfGameLoad.ClassName;
  TfGameMenu.ClassName;
  TfGoodsShop2.ClassName;
  TfGov.ClassName;
  TfHangar.ClassName;
  TfInfo.ClassName;
  TfJournal.ClassName;
  TfJump.ClassName;
  TfLoad.ClassName;
  TfPlanet.ClassName;
  TfPlanetNO.ClassName;
  TfPlanetQuest.ClassName;
  TfRating2.ClassName;
  TfRewards.ClassName;
  TfRuinsTalk.ClassName;
  TfSaveManager.ClassName;
  TfScaner.ClassName;
  TfSelectFace.ClassName;
  TfShip2.ClassName;
  TfStarMap.ClassName;
  TfTalk.ClassName;
end;
end.
